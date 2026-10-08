import Foundation
import IOKit

/// USB identity of the Guitar Hero Live Xbox One dongle (Activision).
public enum DongleIdentity {
    public static let vendorID = 0x1430
    public static let productID = 0x079B

    /// A fresh matching dictionary (IOKit consumes it per call) for this dongle's USB device.
    public static func matchingDictionary() -> NSMutableDictionary {
        let matching = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
        matching["idVendor"] = vendorID
        matching["idProduct"] = productID
        return matching
    }
}

/// A byte pipe to the dongle: one GIP message bundle per USB transfer in, raw bytes out.
public protocol PacketTransport: Sendable {
    /// Finishes normally after `close()`; throws `DongleError.disconnected` when the dongle goes away.
    func incomingPackets() -> AsyncThrowingStream<Data, Error>
    func write(_ data: Data) async throws
    /// Aborts pending I/O and releases the device. Safe to call more than once.
    func close()
}

/// Opens a transport to the dongle, ready for the GIP handshake.
public protocol DongleConnecting: Sendable {
    func connect() async throws -> any PacketTransport
}

public enum DongleEvent: Equatable, Sendable {
    case arrived
    case removed
}

/// Reports the dongle being plugged in or pulled out. A dongle that is already plugged in when the
/// stream is created is reported as `arrived`.
public protocol DongleEventSource: Sendable {
    func events() -> AsyncStream<DongleEvent>
}

public enum DongleError: Error, Hashable, LocalizedError, Sendable {
    case notFound
    case exclusiveAccess
    case noGipInterface
    case disconnected
    case ioFailure(operation: String, code: Int32)

    public var errorDescription: String? {
        switch self {
        case .notFound:
            "The dongle was not found. Is it plugged in?"
        case .exclusiveAccess:
            "Another program has the dongle open. Quit Steam (or any other app that reads Xbox controllers) and try again."
        case .noGipInterface:
            "The dongle does not expose the expected GIP interface."
        case .disconnected:
            "The dongle was disconnected."
        case .ioFailure(let operation, let code):
            "USB \(operation) failed (IOReturn 0x\(String(UInt32(bitPattern: code), radix: 16)))."
        }
    }
}
