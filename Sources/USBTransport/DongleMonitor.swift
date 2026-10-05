import Foundation
import IOKit

/// Watches the registry for the dongle with `IOServiceAddMatchingNotification`: first-match for arrival,
/// terminated for removal. This is what makes automatic reconnection possible.
public struct DongleMonitor: DongleEventSource {
    public init() {}

    public func events() -> AsyncStream<DongleEvent> {
        AsyncStream { continuation in
            let registration = Registration(continuation: continuation)
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

    init(continuation: AsyncStream<DongleEvent>.Continuation) {
        self.continuation = continuation
    }

    func start() {
        queue.async { [self] in
            let port = IONotificationPortCreate(kIOMainPortDefault)
            self.port = port
            IONotificationPortSetDispatchQueue(port, queue)
            let context = Unmanaged.passRetained(self)
            retainedSelf = context
            // Removal first, so the arrival drain below cannot race a terminate that is already queued.
            register(kIOTerminatedNotification, callback: removedCallback, context: context, iterator: &removedIterator)
            drain(removedIterator, event: nil)
            register(kIOFirstMatchNotification, callback: arrivedCallback, context: context, iterator: &arrivedIterator)
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
    ) {
        let matching = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
        matching["idVendor"] = DongleIdentity.vendorID
        matching["idProduct"] = DongleIdentity.productID
        IOServiceAddMatchingNotification(port, type, matching, callback, context.toOpaque(), &iterator)
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
