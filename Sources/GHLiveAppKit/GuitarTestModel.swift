import Combine
import GHLiveCore
import GuitarInput

/// Holds the guitar test between Input Monitor openings: closing the window or losing the guitar keeps the
/// progress, and only `startOver` clears it.
@MainActor
public final class GuitarTestModel: ObservableObject {
    @Published public private(set) var session: GuitarTestSession
    @Published public var isActive = false

    private var subscription: AnyCancellable?

    public init() {
        session = GuitarTestSession()
    }

    /// Feeds every published snapshot to the test, such as the driver's.
    public func follow<Snapshots: Publisher<GuitarSnapshot?, Never>>(_ snapshots: Snapshots) {
        subscription = snapshots.sink { [weak self] snapshot in
            MainActor.assumeIsolated { self?.receive(snapshot) }
        }
    }

    /// A nil snapshot (no guitar report yet) changes nothing.
    public func receive(_ snapshot: GuitarSnapshot?) {
        guard isActive, let snapshot else { return }
        var updated = session
        updated.record(state: snapshot.state, controls: snapshot.controls)
        if updated != session { session = updated }
    }

    public func startOver() {
        session.reset()
    }
}

extension GuitarTestSession {
    public static let completionMessage = "All controls work. You're ready to play."

    private static let notMovedText = "Not moved yet"

    public var progressText: String { "\(verifiedCount) of \(totalCount) verified" }

    public func statusText(for control: Control) -> String { isVerified(control) ? "Verified" : "Not yet" }

    /// The range seen so far for whammy and tilt; nil for every other control.
    public func rangeText(for control: Control) -> String? {
        switch control {
        case .whammy:
            whammyRange.map { String(format: "Seen %.2f to %.2f", $0.lowerBound, $0.upperBound) }
                ?? Self.notMovedText
        case .tilt:
            tiltRange.map { "Seen \($0.lowerBound) to \($0.upperBound)" } ?? Self.notMovedText
        default:
            nil
        }
    }
}
