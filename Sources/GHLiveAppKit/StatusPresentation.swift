import GHLiveCore
import USBTransport

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
            self = Self.failure(message)
        case (_, true):
            self.init(tone: .paused, headline: "Paused", detail: "No keys are sent until you resume.")
        case (.waitingForDongle, false):
            self = Self.noDongle
        case (.connecting, false):
            self.init(tone: .waiting, headline: "Connecting to the dongle", detail: "This takes a few seconds.")
        case (.dongleReady, false):
            self.init(
                tone: .ready, headline: "Dongle ready, turn on your guitar",
                detail: "If it doesn't connect, turn the guitar off and on again.")
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

    /// One wording for "no dongle", whether the driver is waiting for it or failed to find it.
    private static let noDongle = StatusPresentation(
        tone: .waiting, headline: "Waiting for the dongle", detail: "Plug in the Xbox One wireless adapter.")

    private static let retryHint = "GHLive retries every few seconds."

    private static func failure(_ message: String) -> StatusPresentation {
        switch message {
        case DongleError.notFound.localizedDescription:
            return noDongle
        case DongleError.exclusiveAccess.localizedDescription:
            return StatusPresentation(
                tone: .error, headline: "The dongle is in use by another app",
                detail: "Quit Steam or any other app that reads Xbox controllers. \(retryHint)")
        default:
            return StatusPresentation(tone: .error, headline: message, detail: retryHint)
        }
    }

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
