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

/// Busy for the first `busyAttempts` connects, then connects.
private final class BusyThenReady: DongleConnecting, @unchecked Sendable {
    private let lock = NSLock()
    private let busyAttempts: Int
    private var attemptCount = 0

    init(busyAttempts: Int) { self.busyAttempts = busyAttempts }

    var attempts: Int { lock.withLock { attemptCount } }

    func connect() async throws -> any PacketTransport {
        let attempt = lock.withLock {
            attemptCount += 1
            return attemptCount
        }
        if attempt <= busyAttempts { throw DongleError.exclusiveAccess }
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
    @Test("only driver errors are printed, in the retrying form")
    func printsErrorStatusesOnly() {
        let lines = Lines()
        let log = StderrFailureLog { lines.append($0) }
        log.record(.driverStatus(.connecting))
        log.record(.dongleBusy)
        log.record(.driverStatus(.error("boom")))
        #expect(lines.all == ["error: boom (retrying)"])
    }

    @Test("a dongle that stays busy prints one line, however many times the driver retries")
    func busyDongleIsReportedOnce() async {
        let lines = Lines()
        var timing = GuitarDriver.Timing()
        timing.retryDelay = .milliseconds(10)
        let connector = BusyThenReady(busyAttempts: 3)
        let driver = GuitarDriver(
            monitor: OneArrival(), connector: connector, sink: NoOutput(), timing: timing,
            eventLog: StderrFailureLog { lines.append($0) })
        driver.start()
        let deadline = ContinuousClock.now + .seconds(30)
        while connector.attempts < 4, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        await driver.stop()

        #expect(connector.attempts >= 4)
        #expect(lines.all == ["error: \(DongleError.exclusiveAccess.localizedDescription) (retrying)"])
    }
}
