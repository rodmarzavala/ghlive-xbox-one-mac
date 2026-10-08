import GHLiveCore

/// Prints each event with the description the system log uses, so `--verbose` and the log never disagree.
struct TextEventLog: EventLog {
    let write: @Sendable (String) -> Void

    func record(_ event: LogEvent) {
        write(event.message)
    }
}

/// The system log always; the terminal as well when asked to be verbose.
func makeEventLog(
    verbose: Bool, system: any EventLog = OSLogEventLog(), write: @escaping @Sendable (String) -> Void
) -> any EventLog {
    guard verbose else { return system }
    return CompositeEventLog([system, TextEventLog(write: write)])
}
