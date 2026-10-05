import Foundation

/// Command ids. 0x01-0x0A: MS-GIPUSB system messages. 0x20-0x22: PlasticBand "6-Fret Guitar/Xbox One.md".
public enum GipCommand: UInt8, Sendable {
    case acknowledge = 0x01
    case announce = 0x02
    case status = 0x03
    case identify = 0x04
    case power = 0x05
    case authenticate = 0x06
    case virtualKey = 0x07
    case led = 0x0A
    case navigationInput = 0x20
    case ghlGuitarInput = 0x21
    case ghlOutput = 0x22
}

/// MS-GIPUSB header flags byte: bit 4 acknowledge required, bit 5 system message, bits 6-7 chunking.
/// The low nibble carries the client id.
public struct GipFlags: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let acknowledgeRequired = GipFlags(rawValue: 0x10)
    public static let system = GipFlags(rawValue: 0x20)
    public static let chunkStart = GipFlags(rawValue: 0x40)
    public static let chunked = GipFlags(rawValue: 0x80)

    static let clientIDMask: UInt8 = 0x0F

    public var clientID: UInt8 { rawValue & Self.clientIDMask }
}

public struct GipPacket: Equatable, Sendable {
    public let command: UInt8
    public let flags: GipFlags
    public let sequence: UInt8
    public let payload: Data

    public init(command: UInt8, flags: GipFlags, sequence: UInt8, payload: Data) {
        self.command = command
        self.flags = flags
        self.sequence = sequence
        self.payload = payload
    }

    public init(command: GipCommand, flags: GipFlags, sequence: UInt8, payload: Data) {
        self.init(command: command.rawValue, flags: flags, sequence: sequence, payload: payload)
    }

    public var requiresAcknowledgement: Bool { flags.contains(.acknowledgeRequired) }

    public var knownCommand: GipCommand? { GipCommand(rawValue: command) }
}

public enum GipDecodeError: Error, Equatable, Sendable {
    case packetTooShort(Int)
    case truncatedLength
    case lengthTooLong
    case payloadTruncated(expected: Int, available: Int)
}

/// The bytes left over when a transfer ends in something that is not a whole message.
public struct UndecodableTail: Equatable, Sendable {
    public let tail: Data
    public let error: GipDecodeError
}

public struct DecodedTransfer: Equatable, Sendable {
    public let packets: [GipPacket]
    public let failure: UndecodableTail?
}

/// Wraps a send counter: sequences run 1...255 and skip 0, which belongs to the GHL keep-alive.
public struct SequenceCounter: Sendable {
    public static let first: UInt8 = 1
    public static let last: UInt8 = 0xFF

    private var current: UInt8 = SequenceCounter.first - 1

    public init() {}

    public mutating func next() -> UInt8 {
        current = current < Self.last ? current + 1 : Self.first
        return current
    }
}
