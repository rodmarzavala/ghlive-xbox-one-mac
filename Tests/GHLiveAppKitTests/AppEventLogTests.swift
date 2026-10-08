import Foundation
import GHLiveCore
import Testing

@testable import GHLiveAppKit

private let patience: Duration = .seconds(30)

@MainActor
private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
    let deadline = ContinuousClock.now + patience
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
struct AppEventLogTests {
    @Test func startLogsTheLaunchVersionAndTheAccessibilityState() async {
        let fixture = AppFixture(isTrusted: false)
        fixture.model.start()
        #expect(
            Array(fixture.events.events.prefix(2)) == [
                .launched(version: GHLiveInfo.version), .accessibility(isTrusted: false),
            ])
        await fixture.model.shutdown()
    }

    @Test func anUnreadableKeymapIsLoggedAtLaunchWithoutItsPath() async {
        let fixture = AppFixture(keymapProblem: "/Users/example/keymap.json: broken")
        fixture.model.start()
        #expect(fixture.events.events.contains(.keymapLoadFailed))
        #expect(!fixture.events.events.contains { $0.message.contains("example") })
        await fixture.model.shutdown()
    }

    @Test func aReadableKeymapLogsNoFailure() async {
        let fixture = AppFixture()
        fixture.model.start()
        #expect(!fixture.events.events.contains(.keymapLoadFailed))
        await fixture.model.shutdown()
    }

    @Test func accessibilityChangesAreLoggedOnceEach() {
        let fixture = AppFixture(isTrusted: true)
        fixture.accessibility.isTrusted = false
        fixture.model.refreshAccessibility()
        fixture.model.refreshAccessibility()
        fixture.accessibility.isTrusted = true
        fixture.model.refreshAccessibility()
        #expect(
            fixture.events.events.filter { $0.category == .app } == [
                .accessibility(isTrusted: false), .accessibility(isTrusted: true),
            ])
    }

    @Test func terminateLogsTheRequestTheReleaseAndTheFinish() async throws {
        let fixture = AppFixture()
        let instant: @MainActor () async -> Void = {}
        var replied = false
        fixture.model.terminate(trigger: .signal, shutdown: instant, timeout: .seconds(30)) { replied = true }
        try await waitUntil { replied }
        #expect(
            fixture.events.events.filter { $0.category == .app || $0 == .paused } == [
                .terminationRequested(.signal), .paused, .terminationFinished,
            ])
        #expect(fixture.events.events.contains(.inputReleased(count: 0, reason: .quit)))
    }

    @Test func theOutcomeIsLoggedBeforeTheReplyBecauseTheReplyMayExitTheProcess() async throws {
        let fixture = AppFixture()
        let instant: @MainActor () async -> Void = {}
        var loggedAtReply: [LogEvent] = []
        var replied = false
        fixture.model.terminate(shutdown: instant, timeout: .seconds(30)) {
            loggedAtReply = fixture.events.events
            replied = true
        }
        try await waitUntil { replied }
        #expect(loggedAtReply.contains(.terminationFinished))
    }

    @Test func aHungShutdownLogsTheTimeoutAndNeverTheFinish() async throws {
        let fixture = AppFixture()
        let hungForever: @MainActor () async -> Void = { try? await Task.sleep(for: .seconds(30)) }
        var replied = false
        fixture.model.terminate(shutdown: hungForever, timeout: .milliseconds(50)) { replied = true }
        try await waitUntil { replied }
        #expect(fixture.events.events.contains(.terminationRequested(.quit)))
        #expect(fixture.events.events.contains(.terminationTimedOut))
        #expect(!fixture.events.events.contains(.terminationFinished))
    }

    @Test func aFinishedShutdownDoesNotLogTheTimeoutLater() async throws {
        let fixture = AppFixture()
        let instant: @MainActor () async -> Void = {}
        var replied = false
        fixture.model.terminate(shutdown: instant, timeout: .milliseconds(50)) { replied = true }
        try await waitUntil { replied }
        try await Task.sleep(for: .milliseconds(300))
        #expect(!fixture.events.events.contains(.terminationTimedOut))
    }

    @Test func pauseAndResumeFromTheMenuAreLogged() {
        let fixture = AppFixture()
        fixture.model.togglePause()
        fixture.model.togglePause()
        #expect(fixture.events.events.filter { $0 == .paused || $0 == .resumed } == [.paused, .resumed])
    }
}
