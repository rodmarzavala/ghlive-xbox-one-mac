import Foundation
import IOKit

/// Watches the registry for the dongle with `IOServiceAddMatchingNotification`: first-match for arrival,
/// terminated for removal. This is what makes automatic reconnection possible.
public struct DongleMonitor: DongleEventSource {
    private let log: @Sendable (String) -> Void

    /// `log` receives the reason when the notifications cannot be set up; the event stream then ends.
    public init(log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.log = log
    }

    public func events() -> AsyncStream<DongleEvent> {
        AsyncStream { continuation in
            let registration = Registration(continuation: continuation, log: log)
            registration.start()
            continuation.onTermination = { _ in registration.stop() }
        }
    }
}

private final class Registration: @unchecked Sendable {
    private let continuation: AsyncStream<DongleEvent>.Continuation
    private let queue = DispatchQueue(label: "ghlive.monitor")
    private var port: IONotificationPortRef?
    private var arrivedIterator = io_iterator_t()
    private var removedIterator = io_iterator_t()
    private var retainedSelf: Unmanaged<Registration>?

    private let log: @Sendable (String) -> Void

    init(continuation: AsyncStream<DongleEvent>.Continuation, log: @escaping @Sendable (String) -> Void) {
        self.continuation = continuation
        self.log = log
    }

    func start() {
        queue.async { [self] in
            let port = IONotificationPortCreate(kIOMainPortDefault)
            self.port = port
            IONotificationPortSetDispatchQueue(port, queue)
            let context = Unmanaged.passRetained(self)
            retainedSelf = context
            // Removal first, so the arrival drain below cannot race a terminate that is already queued.
            guard
                register(
                    kIOTerminatedNotification, callback: removedCallback, context: context, iterator: &removedIterator)
            else { return }
            drain(removedIterator, event: nil)
            guard
                register(
                    kIOFirstMatchNotification, callback: arrivedCallback, context: context, iterator: &arrivedIterator)
            else { return }
            drain(arrivedIterator, event: .arrived)
        }
    }

    func stop() {
        queue.async { [self] in
            if let port { IONotificationPortDestroy(port) }
            port = nil
            for iterator in [arrivedIterator, removedIterator] where iterator != IO_OBJECT_NULL {
                IOObjectRelease(iterator)
            }
            arrivedIterator = IO_OBJECT_NULL
            removedIterator = IO_OBJECT_NULL
            retainedSelf?.release()
            retainedSelf = nil
        }
    }

    /// Reading the iterator is what re-arms the notification, so every callback must drain it.
    fileprivate func drain(_ iterator: io_iterator_t, event: DongleEvent?) {
        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            IOObjectRelease(service)
            if let event { continuation.yield(event) }
        }
    }

    private func register(
        _ type: String,
        callback: IOServiceMatchingCallback,
        context: Unmanaged<Registration>,
        iterator: inout io_iterator_t
    ) -> Bool {
        let status = IOServiceAddMatchingNotification(
            port, type, DongleIdentity.matchingDictionary(), callback, context.toOpaque(), &iterator
        )
        guard status != KERN_SUCCESS else { return true }
        log("cannot watch for the dongle (\(type), kern_return 0x\(String(UInt32(bitPattern: status), radix: 16)))")
        continuation.finish()
        return false
    }
}

private let arrivedCallback: IOServiceMatchingCallback = { context, iterator in
    guard let context else { return }
    Unmanaged<Registration>.fromOpaque(context).takeUnretainedValue().drain(iterator, event: .arrived)
}

private let removedCallback: IOServiceMatchingCallback = { context, iterator in
    guard let context else { return }
    Unmanaged<Registration>.fromOpaque(context).takeUnretainedValue().drain(iterator, event: .removed)
}
