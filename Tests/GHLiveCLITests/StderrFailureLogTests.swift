import Combine
import Foundation
import GHLiveCore
import GuitarInput
import KeyboardOutput
import Testing
import USBTransport

@testable import GHLiveCLI

private final class Lines: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    var all: [String] { lock.withLock { stored } }
    func append(_ line: String) { lock.withLock { stored.append(line) } }
}

private struct OneArrival: DongleEventSource {
    func events() -> AsyncStream<DongleEvent> {
        AsyncStream { continuation in continuation.yield(.arrived) }
    }
}

private struct IdleTransport: PacketTransport {
    func incomingPackets() -> AsyncThrowingStream<Data, Error> { AsyncThrowingStream { _ in } }
    func write(_ data: Data) async throws {}
    func close() {}
}

private struct Leaky: LocalizedError {
    static let text = "text the public log must not carry"
    var errorDescription: String? { Self.text }
}

/// Throws `error` for the first `failingAttempts` connects, then connects.
private final class FailingThenReady: DongleConnecting, @unchecked Sendable {
    private let lock = NSLock()
    private let failingAttempts: Int
    private let error: Error
    private var attemptCount = 0

    init(failingAttempts: Int, error: Error) {
        self.failingAttempts = failingAttempts
        self.error = error
    }

    var attempts: Int { lock.withLock { attemptCount } }

    func connect() async throws -> any PacketTransport {
        let attempt = lock.withLock {
            attemptCount += 1
            return attemptCount
        }
        if attempt <= failingAttempts { throw error }
        return IdleTransport()
    }
}

@MainActor
private final class NoOutput: OutputSink {
    func apply(state: GuitarState, controls: Set<Control>) {}
    func releaseAll() -> Int { 0 }
}

@MainActor
@Suite("Stderr failure log")
struct StderrFailureLogTests {
    @Test("only driver errors are printed, in the retrying form, with the status text the user sees")
    func printsErrorStatusesOnly() {
        let lines = Lines()
        let latest = LatestStatus()
        let log = StderrFailureLog(latestStatus: latest) { lines.append($0) }
        log.record(.driverStatus(.connecting))
        log.record(.dongleBusy)
        log.record(.driverStatus(.error("boom")))
        latest.value = .error("the full message")
        log.record(.driverStatus(.error("boom")))
        #expect(lines.all == ["error: boom (retrying)", "error: the full message (retrying)"])
    }

    @Test("a dongle that stays busy prints one line, however many times the driver retries")
    func busyDongleIsReportedOnce() async {
        let lines = await run(failingWith: DongleError.exclusiveAccess)
        #expect(lines == ["error: \(DongleError.exclusiveAccess.localizedDescription) (retrying)"])
    }

    @Test("the terminal shows the error's own text although the public log only names its type")
    func terminalKeepsTheFullMessage() async {
        let lines = await run(failingWith: Leaky())
        #expect(lines == ["error: \(Leaky.text) (retrying)"])
    }

    private func run(failingWith error: Error) async -> [String] {
        let lines = Lines()
        let latest = LatestStatus()
        var timing = GuitarDriver.Timing()
        timing.retryDelay = .milliseconds(10)
        let connector = FailingThenReady(failingAttempts: 3, error: error)
        let driver = GuitarDriver(
            monitor: OneArrival(), connector: connector, sink: NoOutput(), timing: timing,
            eventLog: StderrFailureLog(latestStatus: latest) { lines.append($0) })
        let follower = driver.$status.sink { latest.value = $0 }
        driver.start()
        let deadline = ContinuousClock.now + .seconds(30)
        while connector.attempts < 4, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        await driver.stop()
        follower.cancel()
        return lines.all
    }
}
