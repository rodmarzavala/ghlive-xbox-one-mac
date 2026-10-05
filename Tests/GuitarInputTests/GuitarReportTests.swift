import Foundation
import Testing

@testable import GuitarInput

/// Real idle report captured on hardware; byte 19 (tilt) is 0x70.
let idlePayload = Data(hexString: "00000f808080800000000000000000000000007000800100020002")
let idleTilt: UInt8 = 0x70

extension Data {
    init(hexString: String) {
        let digits = Array(hexString)
        self.init(
            stride(from: 0, to: digits.count, by: 2).map { index in
                UInt8(String(digits[index..<index + 2]), radix: 16)!
            }
        )
    }
}

/// The idle payload with byte overrides, keyed by offset.
func payload(overriding changes: [Int: UInt8]) -> Data {
    var bytes = [UInt8](idlePayload)
    for (offset, value) in changes { bytes[offset] = value }
    return Data(bytes)
}

private let hatCases: [(UInt8, Set<DpadDirection>)] = [
    (0x00, [.up]),
    (0x01, [.up, .right]),
    (0x02, [.right]),
    (0x03, [.right, .down]),
    (0x04, [.down]),
    (0x05, [.down, .left]),
    (0x06, [.left]),
    (0x07, [.left, .up]),
    (0x0F, []),
]

@Suite("Guitar report parsing")
struct GuitarReportTests {
    @Test("the idle payload is the documented 27 bytes with tilt at byte 19")
    func idlePayloadShape() {
        #expect(idlePayload.count == GuitarReport.length)
        #expect(idlePayload[GuitarReport.tiltOffset] == idleTilt)
    }

    @Test("an idle report has nothing pressed")
    func idle() throws {
        let state = try parseGuitarReport(idlePayload)
        #expect(state.pressedButtons.isEmpty)
        #expect(state.dpad.isEmpty)
        #expect(state.whammy == 0)
        #expect(state.tilt == idleTilt)
    }

    @Test(
        "each fret bit sets exactly one fret",
        arguments: [
            (UInt8(0x02), GuitarButton.black1), (0x04, .black2), (0x08, .black3),
            (0x01, .white1), (0x10, .white2), (0x20, .white3),
        ]
    )
    func fretBits(bit: UInt8, expected: GuitarButton) throws {
        let state = try parseGuitarReport(payload(overriding: [0: bit]))
        #expect(state.pressedButtons == [expected])
    }

    @Test(
        "each button bit sets exactly one button",
        arguments: [(UInt8(0x01), GuitarButton.heroPower), (0x02, .pause), (0x04, .ghtv)]
    )
    func buttonBits(bit: UInt8, expected: GuitarButton) throws {
        let state = try parseGuitarReport(payload(overriding: [1: bit]))
        #expect(state.pressedButtons == [expected])
    }

    @Test("strum up and down")
    func strum() throws {
        #expect(try parseGuitarReport(payload(overriding: [4: 0x00])).pressedButtons == [.strumUp])
        #expect(try parseGuitarReport(payload(overriding: [4: 0xFF])).pressedButtons == [.strumDown])
    }

    @Test("d-pad hat values, including diagonals and centred", arguments: hatCases)
    func dpad(hat: UInt8, expected: Set<DpadDirection>) throws {
        #expect(try parseGuitarReport(payload(overriding: [2: hat])).dpad == expected)
    }

    @Test("whammy is normalised from released to fully pressed")
    func whammyNormalised() throws {
        #expect(try parseGuitarReport(payload(overriding: [6: 0x80])).whammy == 0)
        #expect(try parseGuitarReport(payload(overriding: [6: 0xFF])).whammy == 1)
        let half = try parseGuitarReport(payload(overriding: [6: 0xBF])).whammy
        #expect(abs(half - 0.5) < 0.01)
    }

    @Test("whammy below the released value clamps to zero")
    func whammyClamped() throws {
        #expect(try parseGuitarReport(payload(overriding: [6: 0x00])).whammy == 0)
    }

    @Test("tilt is the raw byte")
    func tiltRaw() throws {
        #expect(try parseGuitarReport(payload(overriding: [19: 171])).tilt == 171)
    }

    @Test("a wrong length is rejected", arguments: [0, 14, 26, 28])
    func wrongLength(length: Int) {
        #expect(throws: GuitarReportError.invalidLength(length)) {
            try parseGuitarReport(Data(count: length))
        }
    }

    @Test("a slice that does not start at zero parses the same")
    func slice() throws {
        let buffer = Data([0xAA]) + idlePayload
        #expect(try parseGuitarReport(buffer.dropFirst()) == parseGuitarReport(idlePayload))
    }
}
