import GHLiveCore
import GuitarInput
import KeyMapping

/// Everything the Input Monitor draws, as plain values so it can be rendered for any sample state.
public struct MonitorPresentation: Equatable, Sendable {
    public static let tiltMaximum: Double = 255

    public let status: StatusPresentation
    public let state: GuitarState?
    public let controls: Set<Control>
    public let thresholds: Thresholds
    public let bindings: [Control: KeyCode]
    public let isPaused: Bool

    public init(
        status: StatusPresentation,
        snapshot: GuitarSnapshot?,
        thresholds: Thresholds,
        bindings: [Control: KeyCode],
        isPaused: Bool
    ) {
        self.status = status
        state = snapshot?.state
        controls = snapshot?.controls ?? []
        self.thresholds = thresholds
        self.bindings = bindings
        self.isPaused = isPaused
    }

    /// The keys held down right now, as the keyboard sink would hold them. Empty while paused.
    public var keysBeingSent: [String] {
        guard !isPaused else { return [] }
        let keys = Set(controls.compactMap { bindings[$0] })
        return keys.sorted { $0.rawValue < $1.rawValue }.map(KeyLabel.text(for:))
    }

    public func isActive(_ control: Control) -> Bool { controls.contains(control) }

    public func keyLabel(for control: Control) -> String? { bindings[control].map(KeyLabel.text(for:)) }

    public var whammyLevel: Double { state?.whammy ?? 0 }
    public var tiltLevel: Double { Double(state?.tilt ?? 0) / Self.tiltMaximum }
    public var tiltThresholdLevel: Double { Double(thresholds.tilt) / Self.tiltMaximum }
}
