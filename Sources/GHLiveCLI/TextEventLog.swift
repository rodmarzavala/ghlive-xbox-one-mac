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
struct StderrFailureLog: EventLog {
    let write: @Sendable (String) -> Void

    func record(_ event: LogEvent) {
        guard case .driverStatus(let status) = event, let line = StatusReporter.line(for: status) else { return }
        write(line)
    }
}

/// The system log and the failure lines always; the terminal as well when asked to be verbose.
func makeEventLog(
    verbose: Bool, system: any EventLog = OSLogEventLog(), reportError: @escaping @Sendable (String) -> Void,
    write: @escaping @Sendable (String) -> Void
) -> any EventLog {
    var logs: [any EventLog] = [system, StderrFailureLog(write: reportError)]
    if verbose { logs.append(TextEventLog(write: write)) }
    return CompositeEventLog(logs)
}
