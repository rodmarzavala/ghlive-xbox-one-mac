import GHLiveCore
import Testing

@testable import GHLiveCLI

private final class Lines: @unchecked Sendable {
    var all: [String] = []
}

@Suite("Text event log")
struct TextEventLogTests {
    @Test("prints exactly the description the system log gets")
    func printsTheSharedDescription() {
        let lines = Lines()
        let log = TextEventLog { lines.all.append($0) }
        log.record(.driverStatus(.dongleReady))
        log.record(.inputReleased(count: 2, reason: .silence))
        #expect(lines.all == [LogEvent.driverStatus(.dongleReady).message, "released 2 held key(s): silence"])
    }

    @Test("verbose adds the terminal to the system log")
    func verboseWritesToTheTerminal() {
        let lines = Lines()
        let errors = Lines()
        let system = RecordingEventLog()
        let failures = StderrFailureLog(latestStatus: LatestStatus()) { errors.all.append($0) }
        let verbose = makeEventLog(verbose: true, system: system, failures: failures) { lines.all.append($0) }
        let quiet = makeEventLog(verbose: false, system: system, failures: failures) { lines.all.append($0) }
        verbose.record(.dongleArrived)
        quiet.record(.dongleRemoved)
        verbose.record(.driverStatus(.error("x")))
        quiet.record(.driverStatus(.error("x")))
        #expect(lines.all == ["dongle arrived", "status: error: x"])
        #expect(system.events.count == 4)
        #expect(errors.all == ["error: x (retrying)", "error: x (retrying)"])
    }
}
