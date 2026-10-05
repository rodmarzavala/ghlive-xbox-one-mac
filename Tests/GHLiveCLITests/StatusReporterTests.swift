import GHLiveCore
import Testing

@testable import GHLiveCLI

struct StatusReporterTests {
    @Test func errorsAreAlwaysReported() {
        let line = StatusReporter.line(for: .error("Another program has the dongle open."))
        #expect(line == "error: Another program has the dongle open. (retrying)")
    }

    @Test func ordinaryStatusChangesStayQuiet() {
        let quiet: [DriverStatus] = [.waitingForDongle, .connecting, .dongleReady, .guitarActive]
        for status in quiet {
            #expect(StatusReporter.line(for: status) == nil)
        }
    }
}
