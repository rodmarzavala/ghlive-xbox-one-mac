import Foundation
import Testing

@testable import GIPProtocol

private let sampleSequence: UInt8 = 0x07
private let clientIDThree: UInt8 = 0x03

@Suite("GIP packet builders")
struct BuildersTests {
    @Test("power on")
    func powerOn() {
        #expect(GipPacket.powerOn(sequence: sampleSequence).encoded() == Data([0x05, 0x20, 0x07, 0x01, 0x00]))
    }

    @Test("LED on")
    func ledOn() {
        #expect(
            GipPacket.ledOn(sequence: sampleSequence).encoded() == Data([0x0A, 0x20, 0x07, 0x03, 0x00, 0x01, 0x14])
        )
    }

    @Test("authentication done")
    func authenticationDone() {
        #expect(
            GipPacket.authenticationDone(sequence: sampleSequence).encoded()
                == Data([0x06, 0x20, 0x07, 0x02, 0x01, 0x00])
        )
    }

    @Test("GHL keep-alive matches the reference bytes")
    func keepAlive() {
        #expect(
            GipPacket.ghlKeepAlive().encoded()
                == Data([0x22, 0x00, 0x00, 0x08, 0x02, 0x08, 0x0A, 0x00, 0x00, 0x00, 0x00, 0x00])
        )
    }

    @Test("the acknowledgement echoes command, sequence and length")
    func acknowledgementEchoes() {
        let received = GipPacket(
            command: .virtualKey,
            flags: [.system, .acknowledgeRequired],
            sequence: sampleSequence,
            payload: Data(count: 2)
        )
        #expect(
            received.acknowledgement().encoded()
                == Data([0x01, 0x20, 0x07, 0x09, 0x00, 0x07, 0x20, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00])
        )
    }

    @Test("the acknowledgement keeps the client id in header and options")
    func acknowledgementKeepsClientID() {
        let received = GipPacket(
            command: .navigationInput,
            flags: GipFlags(rawValue: GipFlags.acknowledgeRequired.rawValue | clientIDThree),
            sequence: 4,
            payload: Data()
        )
        let acknowledgement = received.acknowledgement()
        #expect(acknowledgement.flags.rawValue == 0x23)
        #expect(acknowledgement.payload[acknowledgement.payload.startIndex + 2] == clientIDThree)
    }
}

@Suite("Sequence counter")
struct SequenceCounterTests {
    @Test("starts at one and skips zero on wrap")
    func wraps() {
        var counter = SequenceCounter()
        #expect(counter.next() == SequenceCounter.first)
        for _ in 0..<(Int(SequenceCounter.last) - Int(SequenceCounter.first) - 1) {
            _ = counter.next()
        }
        #expect(counter.next() == SequenceCounter.last)
        #expect(counter.next() == SequenceCounter.first)
    }
}
