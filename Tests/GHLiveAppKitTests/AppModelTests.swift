import GHLiveCore
import KeyMapping
import Testing

@testable import GHLiveAppKit

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
    }

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

    @Test func savedSettingsReconfigureTheDriver() {
        let fixture = AppFixture()
        fixture.model.settings.toggleRecording(.black1)
        fixture.model.settings.handleKeyDown(keyCode: 0x00)
        #expect(fixture.sink.releaseCount == 1)
        #expect(fixture.model.keymap.bindings[.black1] == KeyCode.named("a"))
        #expect(fixture.model.monitor.keyLabel(for: .black1) == "A")
    }

    @Test func launchAtLoginIsToggledAndFailuresAreShown() {
        let fixture = AppFixture()
        fixture.model.setLaunchAtLogin(true)
        #expect(fixture.model.menu.launchesAtLogin)
        fixture.launchAtLogin.failure = StoreFailure()
        fixture.model.setLaunchAtLogin(false)
        #expect(fixture.model.menu.launchesAtLogin)
        #expect(fixture.model.menu.launchAtLoginProblem?.contains("disk is full") == true)
    }

    @Test func shutdownReleasesTheKeys() async {
        let fixture = AppFixture()
        fixture.model.start()
        await fixture.model.shutdown()
        #expect(fixture.sink.releaseCount >= 1)
    }

    @Test func aKeymapProblemAppearsInTheMenu() {
        let fixture = AppFixture()
        fixture.store.failure = StoreFailure()
        fixture.model.settings.commit()
        #expect(fixture.model.menu.keymapProblem == "disk is full")
    }
}
