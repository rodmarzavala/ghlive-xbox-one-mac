import Foundation

// Header layout per MS-GIPUSB: command, flags, sequence, then the payload length as a little-endian
// base-128 varint.
private let fixedHeaderLength = 3
private let minimumPacketLength = fixedHeaderLength + 1
private let varintValueMask: UInt8 = 0x7F
private let varintContinuationBit: UInt8 = 0x80
private let varintBitsPerByte = 7
// A 4-byte varint spans 28 bits, far beyond any USB transfer; longer ones are corruption.
private let varintMaximumBytes = 4

func encodeVarint(_ value: Int) -> Data {
    var remaining = value
    var encoded = Data()
    repeat {
        let lowBits = UInt8(remaining & Int(varintValueMask))
        remaining >>= varintBitsPerByte
        encoded.append(remaining == 0 ? lowBits : lowBits | varintContinuationBit)
    } while remaining != 0
    return encoded
}

/// Returns the value and the offset just past the varint.
func decodeVarint(_ bytes: [UInt8], at start: Int) throws -> (value: Int, next: Int) {
    var value = 0
    var offset = start
    for index in 0..<varintMaximumBytes {
        guard offset < bytes.count else { throw GipDecodeError.truncatedLength }
        let byte = bytes[offset]
        offset += 1
        value |= Int(byte & varintValueMask) << (index * varintBitsPerByte)
        if byte & varintContinuationBit == 0 { return (value, offset) }
    }
    throw GipDecodeError.lengthTooLong
}

extension GipPacket {
    public func encoded() -> Data {
        var data = Data([command, flags.rawValue, sequence])
        data.append(encodeVarint(payload.count))
        data.append(payload)
        return data
    }

    /// Decodes the first packet in `data`; bytes after it are ignored (USB padding).
    public static func decode(_ data: Data) throws -> GipPacket {
        try decode([UInt8](data), at: 0).packet
    }

    fileprivate static func decode(_ bytes: [UInt8], at start: Int) throws -> (packet: GipPacket, next: Int) {
        guard bytes.count - start >= minimumPacketLength else {
            throw GipDecodeError.packetTooShort(bytes.count - start)
        }
        let (length, payloadStart) = try decodeVarint(bytes, at: start + fixedHeaderLength)
        let payloadEnd = payloadStart + length
        guard payloadEnd <= bytes.count else {
            throw GipDecodeError.payloadTruncated(expected: length, available: bytes.count - payloadStart)
        }
        let packet = GipPacket(
            command: bytes[start],
            flags: GipFlags(rawValue: bytes[start + 1]),
            sequence: bytes[start + 2],
            payload: Data(bytes[payloadStart..<payloadEnd])
        )
        return (packet, payloadEnd)
    }
}

/// A USB transfer can carry several back-to-back messages. A bad tail does not discard the good
/// packets before it: both are reported.
public func decodePackets(_ data: Data) -> DecodedTransfer {
    let bytes = [UInt8](data)
    var packets: [GipPacket] = []
    var offset = 0
    while offset < bytes.count {
        // No GIP command is 0x00, so an all-zero remainder is USB padding, not a message.
        if bytes[offset...].allSatisfy({ $0 == 0 }) { break }
        do {
            let (packet, next) = try GipPacket.decode(bytes, at: offset)
            packets.append(packet)
            offset = next
        } catch let error as GipDecodeError {
            let failure = UndecodableTail(tail: Data(bytes[offset...]), error: error)
            return DecodedTransfer(packets: packets, failure: failure)
        } catch {
            preconditionFailure("decode only throws GipDecodeError")
        }
    }
    return DecodedTransfer(packets: packets, failure: nil)
}
