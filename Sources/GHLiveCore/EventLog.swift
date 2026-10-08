import Foundation
import USBTransport
import os

public enum LogCategory: String, CaseIterable, Sendable {
    case driver
    case usb
    case output
    case app
}

public enum LogLevel: Sendable {
    case debug
    case info
    /// Persisted on disk by the unified log, unlike `debug` and `info`.
    case notice
    case error
    case fault
}

public enum ReleaseReason: String, Sendable {
    case pause
    case stop
    case disconnect
    case silence
    case reconfigure
    case quit
}

public enum TerminationTrigger: String, Sendable {
    case quit
    case signal
}

/// Why something failed, in a form that is safe to publish: a `DongleError` has fixed texts, any other
/// error is named by its type only, because its description could carry anything. The only way to make
/// one is from an `Error`, so no free-form text can get in.
public struct FailureReason: Hashable, Sendable, CustomStringConvertible {
    public let description: String

    public init(_ error: Error) {
        if let dongleError = error as? DongleError {
            description = dongleError.localizedDescription
        } else {
            description = "unexpected error (\(String(describing: type(of: error))))"
        }
    }
}

/// Everything GHLive reports to the system log. It deliberately has no payload that names a key, a control
/// or a report value, so the log can never become a keystroke record: only events, counts and failure texts.
public enum LogEvent: Hashable, Sendable {
    case driverStatus(DriverStatus)
    case dongleArrived
    case dongleRemoved
    case dongleBusy
    case connectFailed(FailureReason)
    case readFailed(FailureReason)
    case writeFailed(FailureReason)
    case keepAliveFailed(FailureReason)
    case guitarSilent
    case inputReleased(count: Int, reason: ReleaseReason)
    case paused
    case resumed
    case launched(version: String)
    case accessibility(isTrusted: Bool)
    case keymapLoadFailed
    case terminationRequested(TerminationTrigger)
    case terminationFinished
    case terminationTimedOut

    /// A failure of the open connection, as opposed to one while connecting.
    var isConnectionFailure: Bool {
        switch self {
        case .readFailed, .writeFailed, .keepAliveFailed: true
        default: false
        }
    }

    public var category: LogCategory {
        switch self {
        case .driverStatus, .guitarSilent, .paused, .resumed:
            .driver
        case .dongleArrived, .dongleRemoved, .dongleBusy, .connectFailed, .readFailed, .writeFailed,
            .keepAliveFailed:
            .usb
        case .inputReleased:
            .output
        case .launched, .accessibility, .keymapLoadFailed, .terminationRequested, .terminationFinished,
            .terminationTimedOut:
            .app
        }
    }

    public var level: LogLevel {
        switch self {
        case .driverStatus(.error), .dongleBusy, .connectFailed, .readFailed, .writeFailed, .keepAliveFailed,
            .keymapLoadFailed:
            .error
        case .terminationTimedOut:
            .fault
        case .inputReleased(let count, _) where count == 0:
            .debug
        default:
            .notice
        }
    }

    /// The one description of the event: the system log, `--verbose` and the tests all read this.
    public var message: String {
        switch self {
        case .driverStatus(let status): "status: \(status.description)"
        case .dongleArrived: "dongle arrived"
        case .dongleRemoved: "dongle removed"
        case .dongleBusy: "dongle is busy: \(DongleError.exclusiveAccess.localizedDescription)"
        case .connectFailed(let reason): "cannot connect to the dongle: \(reason.description)"
        case .readFailed(let reason): "dongle read failed: \(reason.description)"
        case .writeFailed(let reason): "dongle write failed: \(reason.description)"
        case .keepAliveFailed(let reason): "keep-alive failed: \(reason.description)"
        case .guitarSilent: "guitar went silent"
        case .inputReleased(let count, let reason): "released \(count) held key(s): \(reason.rawValue)"
        case .paused: "input paused"
        case .resumed: "input resumed"
        case .launched(let version): "GHLive \(version) launched"
        case .accessibility(let isTrusted): "Accessibility access: \(isTrusted ? "granted" : "not granted")"
        case .keymapLoadFailed: "the saved keymap could not be read, using the defaults"
        case .terminationRequested(let trigger): "quit requested (\(trigger.rawValue))"
        case .terminationFinished: "shutdown finished, keys released"
        case .terminationTimedOut: "shutdown timed out, quitting anyway"
        }
    }
}

/// Where GHLive reports events. The system log is the real one; tests record.
public protocol EventLog: Sendable {
    func record(_ event: LogEvent)
}

public struct NullEventLog: EventLog {
    public init() {}

    public func record(_ event: LogEvent) {}
}

/// Forwards each event to every log, for example the system log plus `--verbose` output.
public struct CompositeEventLog: EventLog {
    private let logs: [any EventLog]

    public init(_ logs: [any EventLog]) {
        self.logs = logs
    }

    public func record(_ event: LogEvent) {
        for log in logs { log.record(event) }
    }
}

/// Writes to the macOS unified log. Messages are built only from `LogEvent`, which carries nothing
/// private, so they are marked public; otherwise the log would show `<private>` for every event.
public struct OSLogEventLog: EventLog {
    private let loggers: [LogCategory: Logger]

    public init(subsystem: String = GHLiveInfo.bundleIdentifier) {
        loggers = Dictionary(
            uniqueKeysWithValues: LogCategory.allCases.map { ($0, Logger(subsystem: subsystem, category: $0.rawValue)) }
        )
    }

    public func record(_ event: LogEvent) {
        loggers[event.category]?.log(level: event.level.osLogType, "\(event.message, privacy: .public)")
    }
}

extension LogLevel {
    var osLogType: OSLogType {
        switch self {
        case .debug: .debug
        case .info: .info
        case .notice: .default
        case .error: .error
        case .fault: .fault
        }
    }
}

/// Keeps what it is given, in order. For tests.
public final class RecordingEventLog: EventLog, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [LogEvent] = []

    public init() {}

    public var events: [LogEvent] { lock.withLock { recorded } }

    public func record(_ event: LogEvent) {
        lock.withLock { recorded.append(event) }
    }
}
