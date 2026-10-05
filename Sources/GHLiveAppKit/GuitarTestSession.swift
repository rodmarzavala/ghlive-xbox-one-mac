import GuitarInput

/// Follows a player pressing every control of the guitar once, so they can confirm each one is read correctly.
/// Feed it every guitar report in order.
public struct GuitarTestSession: Equatable, Sendable {
    /// The whammy bar must go at least this far down to count as fully pressed.
    public static let whammyFullLevel = 0.9
    /// ...and come back to this level or lower to count as released.
    public static let whammyReleasedLevel = 0.1

    private static let analogControls: Set<Control> = [.whammy, .tilt]

    /// Every control that is simply pressed or not, in the enum's order.
    public static let digitalControls: [Control] = Control.allCases.filter { !analogControls.contains($0) }

    public var thresholds: Thresholds
    public private(set) var whammyRange: ClosedRange<Double>?
    public private(set) var tiltRange: ClosedRange<Int>?

    private var verifiedDigital: Set<Control> = []
    private var whammyProgress = AnalogProgress()
    private var tiltProgress = AnalogProgress()

    public init(thresholds: Thresholds = Thresholds()) {
        self.thresholds = thresholds
    }

    public var totalCount: Int { Self.digitalControls.count + Self.analogControls.count }

    public var verifiedCount: Int { Control.allCases.count(where: isVerified) }

    public var isComplete: Bool { verifiedCount == totalCount }

    public func isVerified(_ control: Control) -> Bool {
        switch control {
        case .whammy: whammyProgress.isVerified
        case .tilt: tiltProgress.isVerified
        default: verifiedDigital.contains(control)
        }
    }

    public mutating func record(state: GuitarState, controls: Set<Control>) {
        verifiedDigital.formUnion(controls.subtracting(Self.analogControls))
        recordWhammy(state.whammy)
        recordTilt(Int(state.tilt))
    }

    /// Starts over; the thresholds stay.
    public mutating func reset() {
        self = GuitarTestSession(thresholds: thresholds)
    }

    private mutating func recordWhammy(_ value: Double) {
        whammyRange = whammyRange.map { min($0.lowerBound, value)...max($0.upperBound, value) } ?? value...value
        whammyProgress.observe(
            isEngaged: value >= thresholds.whammy,
            isFullPress: value >= Self.whammyFullLevel,
            isReleased: value <= Self.whammyReleasedLevel)
    }

    private mutating func recordTilt(_ value: Int) {
        tiltRange = tiltRange.map { min($0.lowerBound, value)...max($0.upperBound, value) } ?? value...value
        tiltProgress.observe(
            isEngaged: value >= thresholds.tilt,
            isFullPress: true,
            isReleased: value < thresholds.tilt - thresholds.tiltHysteresis)
    }
}

/// An analog control is verified by going up (past its threshold and to its far end) and then back down.
private struct AnalogProgress: Equatable, Sendable {
    private var hasEngaged = false
    private var hasPressedFully = false
    private(set) var isVerified = false

    mutating func observe(isEngaged: Bool, isFullPress: Bool, isReleased: Bool) {
        hasEngaged = hasEngaged || isEngaged
        hasPressedFully = hasPressedFully || isFullPress
        if hasEngaged, hasPressedFully, isReleased { isVerified = true }
    }
}
