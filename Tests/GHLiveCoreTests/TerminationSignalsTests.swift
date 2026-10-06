import Foundation
import Testing

@testable import GHLiveCore

@MainActor
private final class SignalProbe {
    var received = 0
    var observer: TerminationSignalObserver?
}

@MainActor
struct TerminationSignalsTests {
    // Generous on purpose, like the other polling waits: CI runners can stall the main actor for seconds.
    private static let giveUp: Duration = .seconds(30)
    private static let poll: Duration = .milliseconds(20)

    @Test func theCliAndTheAppWatchTheSameSignals() {
        #expect(Set(TerminationSignals.all) == [SIGINT, SIGTERM, SIGHUP])
    }

    @Test func aSignalReachesTheHandlerInsteadOfKillingTheProcess() async throws {
        let probe = SignalProbe()
        probe.observer = TerminationSignalObserver(signals: [SIGUSR1]) { probe.received += 1 }
        defer { probe.observer?.cancel() }
        // kill, not raise: kqueue sees process-directed signals only. The dispatch source registers asynchronously, so keep signalling until it is listening.
        let deadline = ContinuousClock.now + Self.giveUp
        while probe.received == 0, ContinuousClock.now < deadline {
            kill(getpid(), SIGUSR1)
            try await Task.sleep(for: Self.poll)
        }
        #expect(probe.received >= 1)
    }
}
