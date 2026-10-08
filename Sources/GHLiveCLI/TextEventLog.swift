import Foundation
import GHLiveCore

/// Prints each event with the description the system log uses, so `--verbose` and the log never disagree.
struct TextEventLog: EventLog {
    let write: @Sendable (String) -> Void

    func record(_ event: LogEvent) {
        write(event.message)
    }
}

/// What `ghlive run` always says about the driver, with or without `--verbose`: a failure must never be silent.
/// The driver reports each failure once per episode, so a retry loop prints one line, not one per retry.
///
/// The events decide when to print; the text is the driver's own status, which is what the menu shows. The
/// terminal is not a persisted public log, so it may carry the full error message the log withholds.
struct StderrFailureLog: EventLog {
    let latestStatus: LatestStatus
    let write: @Sendable (String) -> Void

    func record(_ event: LogEvent) {
        guard case .driverStatus(let logged) = event, case .error = logged else { return }
        let line = latestStatus.value.flatMap(StatusReporter.line(for:)) ?? StatusReporter.line(for: logged)
        if let line { write(line) }
    }
}

/// The driver's current status, kept where an `EventLog` can read it from any thread.
final class LatestStatus: @unchecked Sendable {
    private let lock = NSLock()
    private var current: DriverStatus?

    var value: DriverStatus? {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

/// The system log and the failure lines always; the terminal as well when asked to be verbose.
func makeEventLog(
    verbose: Bool, system: any EventLog = OSLogEventLog(), failures: StderrFailureLog?,
    write: @escaping @Sendable (String) -> Void
) -> any EventLog {
    var logs: [any EventLog] = [system]
    if let failures { logs.append(failures) }
    if verbose { logs.append(TextEventLog(write: write)) }
    return CompositeEventLog(logs)
}
