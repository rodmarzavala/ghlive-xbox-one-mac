import GHLiveCore

public enum StatusTone: Equatable, Sendable {
    case waiting
    case ready
    case active
    case paused
    case error
}

/// What the menu bar icon and the status line say for a driver state, in plain language.
public struct StatusPresentation: Equatable, Sendable {
    public let tone: StatusTone
    public let headline: String
    public let detail: String?
    public let symbolName: String

    public init(status: DriverStatus, isPaused: Bool) {
        switch (status, isPaused) {
        case (.error(let message), _):
            self.init(tone: .error, headline: message, detail: Self.retryHint)
        case (_, true):
            self.init(tone: .paused, headline: "Paused", detail: "No keys are sent until you resume.")
        case (.waitingForDongle, false):
            self.init(tone: .waiting, headline: "Waiting for the dongle", detail: "Plug in the Xbox wireless adapter.")
        case (.connecting, false):
            self.init(tone: .waiting, headline: "Connecting to the dongle", detail: nil)
        case (.dongleReady, false):
            self.init(tone: .ready, headline: "Dongle ready, turn on your guitar", detail: nil)
        case (.guitarActive, false):
            self.init(tone: .active, headline: "Guitar connected", detail: nil)
        }
    }

    private init(tone: StatusTone, headline: String, detail: String?) {
        self.tone = tone
        self.headline = headline
        self.detail = detail
        self.symbolName = Self.symbolName(for: tone)
    }

    private static let retryHint = "GHLive tries again every couple of seconds."

    static func symbolName(for tone: StatusTone) -> String {
        switch tone {
        case .waiting: "cable.connector.slash"
        case .ready: "guitars"
        case .active: "guitars.fill"
        case .paused: "pause.circle"
        case .error: "exclamationmark.triangle.fill"
        }
    }
}
