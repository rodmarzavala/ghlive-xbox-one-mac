import Foundation

/// A digital control a key can be bound to. Raw values are the names used in keymap files.
public enum Control: String, CaseIterable, Hashable, Sendable {
    case black1 = "black_1"
    case black2 = "black_2"
    case black3 = "black_3"
    case white1 = "white_1"
    case white2 = "white_2"
    case white3 = "white_3"
    case strumUp = "strum_up"
    case strumDown = "strum_down"
    case heroPower = "hero_power"
    case pause
    case ghtv
    case dpadUp = "dpad_up"
    case dpadDown = "dpad_down"
    case dpadLeft = "dpad_left"
    case dpadRight = "dpad_right"
    case whammy
    case tilt
}

extension GuitarButton {
    var control: Control {
        switch self {
        case .black1: .black1
        case .black2: .black2
        case .black3: .black3
        case .white1: .white1
        case .white2: .white2
        case .white3: .white3
        case .strumUp: .strumUp
        case .strumDown: .strumDown
        case .heroPower: .heroPower
        case .pause: .pause
        case .ghtv: .ghtv
        }
    }
}

extension DpadDirection {
    var control: Control {
        switch self {
        case .up: .dpadUp
        case .down: .dpadDown
        case .left: .dpadLeft
        case .right: .dpadRight
        }
    }
}

/// Digitises the analog whammy and tilt. Each engages at its threshold and releases once it falls
/// `hysteresis` below it, so jitter around the threshold cannot make a key chatter.
public struct Thresholds: Equatable, Sendable {
    public static let defaultWhammy = 0.5
    public static let defaultWhammyHysteresis = 0.1
    /// Measured on hardware: tilt rests at 95-115 and reaches about 171 when raised.
    public static let defaultTilt = 150
    public static let defaultTiltHysteresis = 10

    public var whammy: Double
    public var whammyHysteresis: Double
    public var tilt: Int
    public var tiltHysteresis: Int

    public init(
        whammy: Double = Thresholds.defaultWhammy,
        whammyHysteresis: Double = Thresholds.defaultWhammyHysteresis,
        tilt: Int = Thresholds.defaultTilt,
        tiltHysteresis: Int = Thresholds.defaultTiltHysteresis
    ) {
        self.whammy = whammy
        self.whammyHysteresis = whammyHysteresis
        self.tilt = tilt
        self.tiltHysteresis = tiltHysteresis
    }
}

/// Turns an analog value into a flag: on at `engageAt`, off again only below `releaseBelow`.
public struct HysteresisDetector<Value: Comparable & Sendable>: Sendable {
    private let engageAt: Value
    private let releaseBelow: Value
    private var isActive = false

    public init(engageAt: Value, releaseBelow: Value) {
        self.engageAt = engageAt
        self.releaseBelow = releaseBelow
    }

    public mutating func update(_ value: Value) -> Bool {
        isActive = isActive ? value >= releaseBelow : value >= engageAt
        return isActive
    }

    public mutating func reset() {
        isActive = false
    }
}

/// Stateful (the hysteresis remembers the last answer): feed it every report in order.
public struct ControlDetector: Sendable {
    private var whammy: HysteresisDetector<Double>
    private var tilt: HysteresisDetector<Int>

    public init(thresholds: Thresholds) {
        whammy = HysteresisDetector(
            engageAt: thresholds.whammy,
            releaseBelow: thresholds.whammy - thresholds.whammyHysteresis
        )
        tilt = HysteresisDetector(
            engageAt: thresholds.tilt,
            releaseBelow: thresholds.tilt - thresholds.tiltHysteresis
        )
    }

    public mutating func detect(_ state: GuitarState) -> Set<Control> {
        var active = Set(state.pressedButtons.map(\.control))
        active.formUnion(state.dpad.map(\.control))
        if whammy.update(state.whammy) { active.insert(.whammy) }
        if tilt.update(Int(state.tilt)) { active.insert(.tilt) }
        return active
    }

    /// Forgets the whammy and tilt state, for example after a reconnect.
    public mutating func reset() {
        whammy.reset()
        tilt.reset()
    }
}
