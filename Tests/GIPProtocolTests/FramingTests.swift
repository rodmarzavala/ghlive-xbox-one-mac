import Foundation
import Testing

@testable import GIPProtocol

private let sampleSequence: UInt8 = 0x07
private let clientIDThree: UInt8 = 0x03
private let usbMaxPacketSize = 64
private let guitarReportLength = 27

@Suite("GIP framing")
struct FramingTests {
    @Test("encodes header then payload")
    func encodesHeaderThenPayload() {
        let packet = GipPacket(command: .power, flags: .system, sequence: sampleSequence, payload: Data([0x00]))
        #expect(packet.encoded() == Data([0x05, 0x20, 0x07, 0x01, 0x00]))
    }

    @Test("round trips a guitar report")
    func roundTrip() throws {
        let packet = GipPacket(
            command: .ghlGuitarInput,
            flags: [],
            sequence: sampleSequence,
            payload: Data(0..<UInt8(guitarReportLength))
        )
        let decoded = try GipPacket.decode(packet.encoded())
        #expect(decoded == packet)
    }

    @Test("long payloads use a varint length")
    func longPayloadUsesVarint() throws {
        let payload = Data(count: 200)
        let encoded = GipPacket(command: .announce, flags: .system, sequence: 1, payload: payload).encoded()
        #expect(encoded[3...4] == Data([0xC8, 0x01]))
        #expect(try GipPacket.decode(encoded).payload == payload)
    }

    @Test("truncated header is rejected")
    func truncatedHeader() {
        #expect(throws: GipDecodeError.packetTooShort(2)) {
            try GipPacket.decode(Data([0x20, 0x00]))
        }
    }

    @Test("truncated payload is rejected")
    func truncatedPayload() {
        #expect(throws: GipDecodeError.payloadTruncated(expected: 14, available: 1)) {
            try GipPacket.decode(Data([0x20, 0x00, 0x01, 0x0E, 0x00]))
        }
    }

    @Test("a payload one byte short is rejected")
    func payloadOneByteShort() {
        #expect(throws: GipDecodeError.payloadTruncated(expected: 2, available: 1)) {
            try GipPacket.decode(Data([0x03, 0x20, 0x01, 0x02, 0x83]))
        }
    }

    @Test("a length varint that never ends is rejected")
    func unterminatedVarint() {
        #expect(throws: GipDecodeError.truncatedLength) {
            try GipPacket.decode(Data([0x20, 0x00, 0x01, 0x80]))
        }
    }

    @Test("an absurdly long varint is rejected instead of overflowing")
    func overlongVarint() {
        let data = Data([0x20, 0x00, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01])
        #expect(throws: GipDecodeError.lengthTooLong) {
            try GipPacket.decode(data)
        }
    }

    @Test("trailing USB padding after one packet is ignored")
    func trailingPaddingIgnored() throws {
        let packet = try GipPacket.decode(Data([0x05, 0x20, 0x01, 0x01, 0x00, 0xAA, 0xAA]))
        #expect(packet.payload == Data([0x00]))
    }

    @Test("decoding works on a slice that does not start at index zero")
    func decodesSlices() throws {
        let buffer = Data([0xFF, 0xFF, 0x05, 0x20, 0x01, 0x01, 0x00])
        let packet = try GipPacket.decode(buffer.dropFirst(2))
        #expect(packet.command == GipCommand.power.rawValue)
    }
}

@Suite("GIP bundled transfers")
struct BundledTransferTests {
    private let status = Data([0x03, 0x20, 0x13, 0x01, 0x83])

    @Test("a transfer bundling STATUS and a guitar report yields both")
    func bundledStatusAndGuitar() {
        let guitarPayload = Data([0x00, 0x00, 0x0F]) + Data(count: 24)
        let guitar = Data([0x21, 0x00, 0x95, 0x1B]) + guitarPayload
        let result = decodePackets(status + guitar)
        #expect(
            result.packets == [
                GipPacket(command: .status, flags: .system, sequence: 0x13, payload: Data([0x83])),
                GipPacket(command: .ghlGuitarInput, flags: [], sequence: 0x95, payload: guitarPayload),
            ]
        )
        #expect(result.failure == nil)
    }

    @Test("a single message yields one packet")
    func singleMessage() {
        #expect(decodePackets(Data([0x05, 0x20, 0x01, 0x01, 0x00])).packets.count == 1)
    }

    @Test("trailing zero padding is not decoded as packets")
    func zeroPaddingIgnored() {
        let padded = status + Data(count: usbMaxPacketSize - status.count)
        let result = decodePackets(padded)
        #expect(result.packets.count == 1)
        #expect(result.failure == nil)
    }

    @Test("an empty message is followed by the next one")
    func emptyPayloadThenNext() {
        let empty = Data([0x03, 0x20, 0x01, 0x00])
        let next = Data([0x03, 0x20, 0x02, 0x01, 0x83])
        #expect(decodePackets(empty + next).packets.map(\.payload) == [Data(), Data([0x83])])
    }

    @Test("a truncated second message reports the first packet plus the error")
    func truncatedTail() {
        let first = Data([0x05, 0x20, 0x01, 0x01, 0x00])
        let truncated = Data([0x21, 0x00, 0x02, 0x1B, 0x00])
        let result = decodePackets(first + truncated)
        #expect(result.packets.map(\.command) == [GipCommand.power.rawValue])
        #expect(result.failure?.tail == truncated)
        #expect(result.failure?.error == .payloadTruncated(expected: 27, available: 1))
    }

    @Test("an empty transfer yields nothing")
    func emptyTransfer() {
        let result = decodePackets(Data())
        #expect(result.packets.isEmpty)
        #expect(result.failure == nil)
    }
}

@Suite("GIP packet flags")
struct PacketFlagsTests {
    @Test("an acknowledge-required packet reports it")
    func requiresAcknowledgement() {
        let packet = GipPacket(
            command: .announce, flags: [.system, .acknowledgeRequired], sequence: 1, payload: Data())
        #expect(packet.requiresAcknowledgement)
    }

    @Test("plain input does not require acknowledgement")
    func inputDoesNotRequireIt() {
        let packet = GipPacket(command: .navigationInput, flags: [], sequence: 1, payload: Data())
        #expect(!packet.requiresAcknowledgement)
    }

    @Test("the client id is the low nibble of the flags")
    func clientID() {
        let flags = GipFlags(rawValue: GipFlags.acknowledgeRequired.rawValue | clientIDThree)
        #expect(flags.clientID == clientIDThree)
    }
}
