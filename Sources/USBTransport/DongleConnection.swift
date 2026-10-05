import Foundation
import IOKit
import IOUSBHost

// The GIP interface triplet (class, subclass, protocol) from the descriptor dump in docs/protocol-notes.md.
private let gipInterfaceClass = 0xFF
private let gipInterfaceSubClass = 0x47
private let gipInterfaceProtocol = 0xD0
// Interrupt endpoints of that interface (docs/protocol-notes.md, confirmed on hardware).
private let outEndpointAddress = 0x01
private let inEndpointAddress = 0x81
private let maxPacketSize = 64
private let usbConfigurationValue = 1
// Interrupt pipes only accept 0 ("never time out"); any other value is kIOReturnBadArgument.
private let interruptCompletionTimeout: TimeInterval = 0
// About a second of reports at the guitar's ~80 Hz: if the consumer stalls, old input is dropped, not replayed.
private let incomingBufferLimit = 64
// The interface service shows up asynchronously after the device is configured.
private let interfacePollAttempts = 30
private let interfacePollInterval: Duration = .milliseconds(100)

/// An open, configured GIP interface of the dongle. Obtain one with `DongleConnection.open()`.
/// The object is thread-safe: I/O completes on a private serial queue, `close()` may come from anywhere.
public final class DongleConnection: PacketTransport, @unchecked Sendable {
    private let device: IOUSBHostDevice
    private let interface: IOUSBHostInterface
    private let outPipe: IOUSBHostPipe
    private let inPipe: IOUSBHostPipe
    private let lock = NSLock()
    private var isClosed = false

    private init(device: IOUSBHostDevice, interface: IOUSBHostInterface, outPipe: IOUSBHostPipe, inPipe: IOUSBHostPipe)
    {
        self.device = device
        self.interface = interface
        self.outPipe = outPipe
        self.inPipe = inPipe
    }

    public static func open() async throws -> DongleConnection {
        guard let service = findDeviceService() else { throw DongleError.notFound }
        defer { IOObjectRelease(service) }
        let queue = DispatchQueue(label: "ghlive.usb")
        let device = try wrapping("open device") {
            try IOUSBHostDevice(__ioService: service, options: [], queue: queue, interestHandler: nil)
        }
        do {
            try wrapping("configure device") {
                try device.__configure(withValue: usbConfigurationValue, matchInterfaces: true)
            }
            let interfaceService = try await waitForGipInterface(below: service)
            defer { IOObjectRelease(interfaceService) }
            let interface = try wrapping("open interface") {
                try IOUSBHostInterface(__ioService: interfaceService, options: [], queue: queue, interestHandler: nil)
            }
            do {
                let outPipe = try copyPipe(interface, address: outEndpointAddress)
                let inPipe = try copyPipe(interface, address: inEndpointAddress)
                return DongleConnection(device: device, interface: interface, outPipe: outPipe, inPipe: inPipe)
            } catch {
                interface.destroy()
                throw error
            }
        } catch {
            device.destroy()
            throw error
        }
    }

    // MARK: PacketTransport

    public func incomingPackets() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(incomingBufferLimit)) { continuation in
            continuation.onTermination = { [weak self] _ in self?.close() }
            submitRead(continuation)
        }
    }

    public func write(_ data: Data) async throws {
        let buffer = NSMutableData(data: data)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try outPipe.enqueueIORequest(with: buffer, completionTimeout: interruptCompletionTimeout) { status, _ in
                    if status == kIOReturnSuccess {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: DongleError.from(status, operation: "write"))
                    }
                }
            } catch {
                continuation.resume(throwing: DongleError.from(error, operation: "write"))
            }
        }
    }

    public func close() {
        lock.lock()
        let alreadyClosed = isClosed
        isClosed = true
        lock.unlock()
        guard !alreadyClosed else { return }
        try? inPipe.__abort(with: .asynchronous)
        try? outPipe.__abort(with: .asynchronous)
        interface.destroy()
        device.destroy()
    }

    private var closing: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isClosed
    }

    // MARK: Reading

    private func submitRead(_ continuation: AsyncThrowingStream<Data, Error>.Continuation) {
        guard !closing, let storage = NSMutableData(length: maxPacketSize) else {
            continuation.finish()
            return
        }
        let buffer = TransferBuffer(storage)
        do {
            try inPipe.enqueueIORequest(with: storage, completionTimeout: interruptCompletionTimeout) {
                [self] status, count in
                if status == kIOReturnSuccess {
                    if count > 0 { continuation.yield(buffer.copy(count: count)) }
                    submitRead(continuation)
                } else if closing {
                    continuation.finish()
                } else {
                    continuation.finish(throwing: DongleError.from(status, operation: "read"))
                }
            }
        } catch {
            continuation.finish(throwing: closing ? nil : DongleError.from(error, operation: "read"))
        }
    }

    // MARK: Discovery

    private static func findDeviceService() -> io_service_t? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, DongleIdentity.matchingDictionary())
        return service == IO_OBJECT_NULL ? nil : service
    }

    private static func waitForGipInterface(below device: io_service_t) async throws -> io_service_t {
        for _ in 0..<interfacePollAttempts {
            if let service = gipInterfaceService(below: device) { return service }
            try await Task.sleep(for: interfacePollInterval)
        }
        throw DongleError.noGipInterface
    }

    private static func gipInterfaceService(below device: io_service_t) -> io_service_t? {
        var iterator = io_iterator_t()
        guard IORegistryEntryGetChildIterator(device, kIOServicePlane, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let child = IOIteratorNext(iterator), child != IO_OBJECT_NULL {
            if isGipInterface(child) { return child }
            IOObjectRelease(child)
        }
        return nil
    }

    private static func isGipInterface(_ service: io_service_t) -> Bool {
        guard IOObjectConformsTo(service, "IOUSBHostInterface") != 0 else { return false }
        return registryInt(service, "bInterfaceClass") == gipInterfaceClass
            && registryInt(service, "bInterfaceSubClass") == gipInterfaceSubClass
            && registryInt(service, "bInterfaceProtocol") == gipInterfaceProtocol
    }

    private static func registryInt(_ service: io_service_t, _ key: String) -> Int? {
        let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)
        return value?.takeRetainedValue() as? Int
    }

    private static func copyPipe(_ interface: IOUSBHostInterface, address: Int) throws -> IOUSBHostPipe {
        do {
            return try interface.copyPipe(withAddress: address)
        } catch {
            throw DongleError.noGipInterface
        }
    }

    private static func wrapping<T>(_ operation: String, _ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch {
            throw DongleError.from(error, operation: operation)
        }
    }
}

/// The buffer of one read; only the completion handler of that read touches it.
private final class TransferBuffer: @unchecked Sendable {
    private let storage: NSMutableData

    init(_ storage: NSMutableData) {
        self.storage = storage
    }

    func copy(count: Int) -> Data {
        Data(bytes: storage.bytes, count: count)
    }
}

/// Connects on demand; the `DongleConnecting` the driver uses on real hardware.
public struct DongleConnector: DongleConnecting {
    public init() {}

    public func connect() async throws -> any PacketTransport {
        try await DongleConnection.open()
    }
}

extension DongleError {
    static func from(_ error: Error, operation: String) -> DongleError {
        if let known = error as? DongleError { return known }
        return from(IOReturn(truncatingIfNeeded: (error as NSError).code), operation: operation)
    }

    static func from(_ status: IOReturn, operation: String) -> DongleError {
        switch status {
        case kIOReturnExclusiveAccess:
            .exclusiveAccess
        // Aborted only reaches here when we did not close ourselves, so the device went away under us.
        case kIOReturnNoDevice, kIOReturnNotAttached, kIOReturnNotResponding, kIOReturnAborted:
            .disconnected
        default:
            .ioFailure(operation: operation, code: status)
        }
    }
}
