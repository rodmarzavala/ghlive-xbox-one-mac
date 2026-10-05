import Foundation

public enum MIDIError: Error, Equatable, Sendable, LocalizedError {
    case notAMIDIFile
    case truncated(String)
    case malformedQuantity
    case missingRunningStatus
    case unsupportedStatus(UInt8)
    case unsupportedFormat(Int)

    public var errorDescription: String? {
        switch self {
        case .notAMIDIFile: "not a Standard MIDI File"
        case .truncated(let what): "the MIDI file ends inside \(what)"
        case .malformedQuantity: "malformed variable-length quantity"
        case .missingRunningStatus: "a MIDI event has no status byte and there is no running status"
        case .unsupportedStatus(let status): "unsupported MIDI status byte 0x\(String(status, radix: 16))"
        case .unsupportedFormat(let format): "MIDI format \(format) is not supported (only type 1)"
        }
    }
}

/// Variable-length quantities: seven bits per byte, most significant group first, high bit set on all but
/// the last byte; at most four bytes (Standard MIDI Files spec, section 1).
enum VariableLengthQuantity {
    static let maxByteCount = 4
    static let continuationBit: UInt8 = 0x80
    static let payloadMask: UInt8 = 0x7F
    static let bitsPerByte: UInt32 = 7

    static func encode(_ value: UInt32) -> [UInt8] {
        var groups: [UInt8] = [UInt8(value & UInt32(payloadMask))]
        var rest = value >> bitsPerByte
        while rest > 0 {
            groups.append(UInt8(rest & UInt32(payloadMask)) | continuationBit)
            rest >>= bitsPerByte
        }
        return groups.reversed()
    }
}

struct ByteReader {
    private let bytes: [UInt8]
    private(set) var offset = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    var isAtEnd: Bool { offset >= bytes.count }
    var remaining: Int { bytes.count - offset }

    mutating func readByte(_ what: String) throws -> UInt8 {
        guard offset < bytes.count else { throw MIDIError.truncated(what) }
        defer { offset += 1 }
        return bytes[offset]
    }

    func peekByte() -> UInt8? {
        offset < bytes.count ? bytes[offset] : nil
    }

    mutating func readBytes(_ count: Int, _ what: String) throws -> [UInt8] {
        guard count >= 0, count <= remaining else { throw MIDIError.truncated(what) }
        defer { offset += count }
        return Array(bytes[offset..<offset + count])
    }

    mutating func readUInt32(_ what: String) throws -> UInt32 {
        try readBytes(4, what).reduce(0) { $0 << 8 | UInt32($1) }
    }

    mutating func readVariableLengthQuantity() throws -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<VariableLengthQuantity.maxByteCount {
            guard let byte = try? readByte("a variable-length quantity") else { throw MIDIError.malformedQuantity }
            value = value << VariableLengthQuantity.bitsPerByte | UInt32(byte & VariableLengthQuantity.payloadMask)
            if byte & VariableLengthQuantity.continuationBit == 0 { return value }
        }
        throw MIDIError.malformedQuantity
    }
}
