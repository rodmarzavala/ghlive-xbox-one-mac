import Combine
import Foundation
import GHLiveCore
import KeyMapping
import Testing

@testable import GHLiveAppKit

private let pollInterval: Duration = .milliseconds(10)
private let patience: Duration = .seconds(3)

@MainActor
private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
    let deadline = ContinuousClock.now + patience
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: pollInterval)
    }
}

@MainActor
struct AppModelTests {
    @Test func menuReflectsTheDriverAndPause() {
        let fixture = AppFixture()
        #expect(fixture.model.menu.status.headline == "Waiting for the dongle")
        #expect(fixture.model.menu.pauseTitle == "Pause")
        fixture.model.togglePause()
        #expect(fixture.model.driver.isPaused)
        #expect(fixture.model.menu.pauseTitle == "Resume")
        #expect(fixture.model.menu.status.tone == .paused)
        fixture.model.togglePause()
        #expect(!fixture.model.driver.isPaused)
        #expect(fixture.model.menu.status.tone == .waiting)
    }

    @Test func menuAndMonitorShareOneStatusPresentation() {
        let fixture = AppFixture()
        fixture.model.togglePause()
        #expect(fixture.model.monitor.status == fixture.model.menu.status)
    }

    @Test func anUnchangedMenuIsNotRepublished() {
        let fixture = AppFixture()
        fixture.model.setLaunchAtLogin(true)
        var changes = 0
        let subscription = fixture.model.objectWillChange.sink { changes += 1 }
        fixture.model.setLaunchAtLogin(true)
        #expect(changes == 0)
        subscription.cancel()
    }

    @Test func theMenuOnlyPublishesWhenItChanges() {
        let fixture = AppFixture()
        var changes = 0
        let subscription = fixture.model.objectWillChange.sink { changes += 1 }
        fixture.model.refreshAccessibility()
        fixture.model.refreshLaunchAtLogin()
        #expect(changes == 0)
        fixture.model.togglePause()
        #expect(changes == 1)
        subscription.cancel()
    }

    // MARK: Accessibility

    @Test func missingPermissionShowsTheGrantItemAndOpensSystemSettings() {
        let fixture = AppFixture(isTrusted: false)
        #expect(fixture.model.menu.needsAccessibility)
        fixture.model.requestAccessibility()
        #expect(fixture.accessibility.requestCount == 1)
        #expect(
            fixture.opened.urls.map(\.absoluteString)
                == ["x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"])
    }

    @Test func grantingThePermissionRebuildsTheOutputOnce() {
        let fixture = AppFixture(isTrusted: false)
        fixture.model.refreshAccessibility()
        #expect(fixture.sink.releaseCount == 0)
        fixture.accessibility.isTrusted = true
        fixture.model.refreshAccessibility()
        #expect(!fixture.model.menu.needsAccessibility)
        #expect(fixture.sink.releaseCount == 1)
        fixture.model.refreshAccessibility()
        #expect(fixture.sink.releaseCount == 1)
    }

    @Test func revokingThePermissionDoesNotRebuildTheOutput() {
        let fixture = AppFixture(isTrusted: true)
        fixture.accessibility.isTrusted = false
        fixture.model.refreshAccessibility()
        #expect(fixture.model.menu.needsAccessibility)
        #expect(fixture.sink.releaseCount == 0)
    }

    @Test func thePollNoticesAPermissionGrantByItself() async throws {
        let fixture = AppFixture(isTrusted: false, pollInterval: pollInterval)
        fixture.model.start()
        fixture.accessibility.isTrusted = true
        try await waitUntil { fixture.sink.releaseCount >= 1 }
        #expect(fixture.sink.releaseCount == 1)
        #expect(!fixture.model.menu.needsAccessibility)
        await fixture.model.shutdown()
    }

    @Test func thePollNoticesTheLoginItemBeingApproved() async throws {
        let fixture = AppFixture(pollInterval: pollInterval)
        fixture.model.start()
        fixture.launchAtLogin.state = .requiresApproval
        try await waitUntil { fixture.model.menu.launchAtLoginNeedsApproval }
        #expect(fixture.model.menu.launchAtLoginNeedsApproval)
        fixture.launchAtLogin.state = .enabled
        try await waitUntil { fixture.model.menu.launchesAtLogin }
        #expect(fixture.model.menu.launchesAtLogin)
        await fixture.model.shutdown()
    }

    // MARK: Settings

    @Test func savedSettingsReconfigureTheDriver() {
        let fixture = AppFixture()
        fixture.model.settings.toggleRecording(.black1)
        fixture.model.settings.handleKeyDown(keyCode: 0x00)
        #expect(fixture.sink.releaseCount == 1)
        #expect(fixture.model.keymap.bindings[.black1] == KeyCode.named("a"))
        #expect(fixture.model.monitor.keyLabel(for: .black1) == "A")
    }

    @Test func aSaveFailureAppearsInTheMenuAndClearsOnTheNextSave() {
        let fixture = AppFixture()
        fixture.store.failure = StoreFailure()
        fixture.model.settings.commit()
        #expect(fixture.model.menu.keymapProblem == "disk is full")
        fixture.store.failure = nil
        fixture.model.settings.commit()
        #expect(fixture.model.menu.keymapProblem == nil)
    }

    @Test func openingTheKeymapFolderCreatesItAndOpensIt() {
        let fixture = AppFixture()
        defer { try? FileManager.default.removeItem(at: fixture.keymapFolder) }
        fixture.model.openKeymapFolder()
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: fixture.keymapFolder.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(fixture.opened.urls == [fixture.keymapFolder])
    }

    @Test func theSettingsButtonOpensTheSameFolder() {
        let fixture = AppFixture()
        defer { try? FileManager.default.removeItem(at: fixture.keymapFolder) }
        fixture.model.settings.onOpenKeymapFolder()
        #expect(fixture.opened.urls == [fixture.keymapFolder])
    }

    // MARK: Launch at login

    @Test func launchAtLoginIsToggled() {
        let fixture = AppFixture()
        fixture.model.setLaunchAtLogin(true)
        #expect(fixture.model.menu.launchesAtLogin)
        fixture.model.setLaunchAtLogin(false)
        #expect(!fixture.model.menu.launchesAtLogin)
    }

    @Test func aFailedToggleKeepsTheStateAndShowsTheWarning() {
        let fixture = AppFixture()
        fixture.model.setLaunchAtLogin(true)
        fixture.launchAtLogin.failure = StoreFailure()
        fixture.model.setLaunchAtLogin(false)
        #expect(fixture.model.menu.launchesAtLogin)
        #expect(fixture.model.menu.launchAtLoginProblem?.contains("disk is full") == true)
    }

    @Test func theWarningClearsAfterASuccessfulToggle() {
        let fixture = AppFixture()
        fixture.launchAtLogin.failure = StoreFailure()
        fixture.model.setLaunchAtLogin(true)
        #expect(fixture.model.menu.launchAtLoginProblem != nil)
        fixture.launchAtLogin.failure = nil
        fixture.model.setLaunchAtLogin(true)
        #expect(fixture.model.menu.launchAtLoginProblem == nil)
        #expect(fixture.model.menu.launchesAtLogin)
    }

    @Test func aLoginItemThatNeedsApprovalIsReportedAndCanOpenSystemSettings() {
        let fixture = AppFixture()
        fixture.launchAtLogin.state = .requiresApproval
        fixture.model.refreshLaunchAtLogin()
        #expect(fixture.model.menu.launchAtLoginNeedsApproval)
        #expect(!fixture.model.menu.launchesAtLogin)
        fixture.model.openLoginItemsSettings()
        #expect(fixture.launchAtLogin.openedSettingsCount == 1)
    }

    // MARK: Quitting

    @Test func shutdownReleasesTheKeys() async {
        let fixture = AppFixture()
        fixture.model.start()
        await fixture.model.shutdown()
        #expect(fixture.sink.releaseCount >= 1)
    }

    @Test func terminateRepliesOnlyAfterTheKeysAreReleased() async throws {
        let fixture = AppFixture()
        fixture.model.start()
        var releasesAtReply: Int?
        fixture.model.terminate { releasesAtReply = fixture.sink.releaseCount }
        #expect(releasesAtReply == nil)
        try await waitUntil { releasesAtReply != nil }
        #expect((releasesAtReply ?? 0) >= 1)
    }

    @Test func terminateGivesUpWhenStoppingHangsButKeysAreAlreadyReleased() async throws {
        let fixture = AppFixture()
        var replies = 0
        var releasesAtReply = 0
        let hungForever: @MainActor () async -> Void = { try? await Task.sleep(for: .seconds(30)) }
        fixture.model.terminate(shutdown: hungForever, timeout: .milliseconds(50)) {
            replies += 1
            releasesAtReply = fixture.sink.releaseCount
        }
        #expect(replies == 0)
        try await waitUntil { replies > 0 }
        #expect(replies == 1)
        #expect(releasesAtReply >= 1)
    }

    @Test func concurrentTerminatesJoinOneShutdown() async throws {
        let fixture = AppFixture()
        var shutdowns = 0
        var releasesAtReply: [Int] = []
        let counting: @MainActor () async -> Void = {
            shutdowns += 1
            try? await Task.sleep(for: .milliseconds(50))
        }
        for _ in 0..<2 {
            fixture.model.terminate(shutdown: counting, timeout: .seconds(30)) {
                releasesAtReply.append(fixture.sink.releaseCount)
            }
        }
        #expect(releasesAtReply.isEmpty)
        try await waitUntil { releasesAtReply.count == 2 }
        #expect(shutdowns == 1)
        #expect(releasesAtReply.count == 2)
        #expect(releasesAtReply.allSatisfy { $0 >= 1 })
    }

    @Test func aTerminateAfterTheLastOneRepliesAtOnce() async throws {
        let fixture = AppFixture()
        let instant: @MainActor () async -> Void = {}
        var replies = 0
        fixture.model.terminate(shutdown: instant, timeout: .seconds(30)) { replies += 1 }
        try await waitUntil { replies == 1 }
        fixture.model.terminate(shutdown: instant, timeout: .seconds(30)) { replies += 1 }
        #expect(replies == 2)
    }

    @Test func terminateRepliesOnlyOnce() async throws {
        let fixture = AppFixture()
        var replies = 0
        let instant: @MainActor () async -> Void = {}
        fixture.model.terminate(shutdown: instant, timeout: .milliseconds(50)) { replies += 1 }
        try await Task.sleep(for: .milliseconds(300))
        #expect(replies == 1)
    }
}

@MainActor
struct DryRunEnvironmentTests {
    @Test func onlyTheExactValueOneEnablesDryRun() {
        let variable = AppModel.dryRunVariable
        #expect(AppModel.isDryRun(environment: [variable: "1"]))
        for other in ["0", "", "true", "yes", "11", " 1"] {
            #expect(!AppModel.isDryRun(environment: [variable: other]))
        }
        #expect(!AppModel.isDryRun(environment: [:]))
    }
}
