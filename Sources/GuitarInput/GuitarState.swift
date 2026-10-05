import Foundation

/// Digital buttons carried by the 0x21 report (frets, strum bar and the three face buttons).
public enum GuitarButton: String, CaseIterable, Sendable {
    case black1, black2, black3, white1, white2, white3
    case strumUp, strumDown
    case heroPower, pause, ghtv
}

public enum DpadDirection: CaseIterable, Hashable, Sendable {
    case up, right, down, left
}

public struct GuitarState: Equatable, Sendable {
    public var pressedButtons: Set<GuitarButton>
    public var dpad: Set<DpadDirection>
    /// 0 (released) to 1 (fully pressed).
    public var whammy: Double
    /// Raw tilt byte: about 95-115 at rest, about 171 when raised (measured on hardware).
    public var tilt: UInt8

    public init(pressedButtons: Set<GuitarButton>, dpad: Set<DpadDirection>, whammy: Double, tilt: UInt8) {
        self.pressedButtons = pressedButtons
        self.dpad = dpad
        self.whammy = whammy
        self.tilt = tilt
    }
}

public enum GuitarReportError: Error, Equatable, Sendable {
    case invalidLength(Int)
}

/// Layout of the GHL_GUITAR_INPUT (0x21) payload, confirmed on hardware; it matches PlasticBand
/// "6-Fret Guitar/Xbox One.md".
public enum GuitarReport {
    public static let length = 27
    public static let fretOffset = 0
    public static let buttonOffset = 1
    public static let dpadOffset = 2
    public static let strumOffset = 4
    public static let whammyOffset = 6
    public static let tiltOffset = 19

    static let strumUpValue: UInt8 = 0x00
    static let strumDownValue: UInt8 = 0xFF
    static let whammyReleased: UInt8 = 0x80
    static let whammyPressed: UInt8 = 0xFF

    static let fretBits: [(mask: UInt8, button: GuitarButton)] = [
        (0x01, .white1), (0x02, .black1), (0x04, .black2), (0x08, .black3), (0x10, .white2), (0x20, .white3),
    ]
    static let buttonBits: [(mask: UInt8, button: GuitarButton)] = [
        (0x01, .heroPower), (0x02, .pause), (0x04, .ghtv),
    ]

    /// Hat switch: 0 = up, then clockwise in 45 degree steps (odd values are diagonals); anything else is centred.
    static let hatDirections: [UInt8: Set<DpadDirection>] = [
        0: [.up], 1: [.up, .right], 2: [.right], 3: [.right, .down],
        4: [.down], 5: [.down, .left], 6: [.left], 7: [.left, .up],
    ]
}

public func parseGuitarReport(_ payload: Data) throws -> GuitarState {
    guard payload.count == GuitarReport.length else {
        throw GuitarReportError.invalidLength(payload.count)
    }
    let bytes = [UInt8](payload)
    var pressed = Set<GuitarButton>()
    for (mask, button) in GuitarReport.fretBits where bytes[GuitarReport.fretOffset] & mask != 0 {
        pressed.insert(button)
    }
    for (mask, button) in GuitarReport.buttonBits where bytes[GuitarReport.buttonOffset] & mask != 0 {
        pressed.insert(button)
    }
    switch bytes[GuitarReport.strumOffset] {
    case GuitarReport.strumUpValue: pressed.insert(.strumUp)
    case GuitarReport.strumDownValue: pressed.insert(.strumDown)
    default: break
    }
    return GuitarState(
        pressedButtons: pressed,
        dpad: GuitarReport.hatDirections[bytes[GuitarReport.dpadOffset]] ?? [],
        whammy: normalisedWhammy(bytes[GuitarReport.whammyOffset]),
        tilt: bytes[GuitarReport.tiltOffset]
    )
}

private func normalisedWhammy(_ raw: UInt8) -> Double {
    let span = Double(GuitarReport.whammyPressed - GuitarReport.whammyReleased)
    return min(max((Double(raw) - Double(GuitarReport.whammyReleased)) / span, 0), 1)
}
