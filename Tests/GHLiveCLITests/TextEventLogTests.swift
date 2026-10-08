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
        let system = RecordingEventLog()
        makeEventLog(verbose: true, system: system, reportError: { _ in }) { lines.all.append($0) }.record(
            .dongleArrived)
        makeEventLog(verbose: false, system: system, reportError: { _ in }) { lines.all.append($0) }.record(
            .dongleRemoved)
        #expect(lines.all == ["dongle arrived"])
        #expect(system.events == [.dongleArrived, .dongleRemoved])
    }
}
