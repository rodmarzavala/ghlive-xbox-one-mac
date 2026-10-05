import Foundation
import GHLiveCore
import GuitarInput
import KeyMapping
import KeyboardOutput
import USBTransport

@testable import GHLiveAppKit

final class MemoryStore: KeymapPersisting, @unchecked Sendable {
    var saved: [Keymap] = []
    var failure: (any Error)?

    func save(_ keymap: Keymap) throws {
        if let failure { throw failure }
        saved.append(keymap)
    }
}

struct StoreFailure: LocalizedError {
    var errorDescription: String? { "disk is full" }
}

@MainActor
final class ProbeSink: OutputSink {
    private(set) var releaseCount = 0

    func apply(state: GuitarState, controls: Set<Control>) {}
    func releaseAll() { releaseCount += 1 }
}

@MainActor
final class RecordingEmitter: KeyEmitter {
    func keyDown(_ key: KeyCode) {}
    func keyUp(_ key: KeyCode) {}
}

struct SilentMonitor: DongleEventSource {
    func events() -> AsyncStream<DongleEvent> { AsyncStream { _ in } }
}

struct UnreachableConnector: DongleConnecting {
    func connect() async throws -> any PacketTransport { throw DongleError.notFound }
}

@MainActor
final class FakeAccessibility: AccessibilityChecking {
    var isTrusted: Bool
    private(set) var requestCount = 0

    init(isTrusted: Bool) { self.isTrusted = isTrusted }

    func request() { requestCount += 1 }
}

@MainActor
final class FakeLaunchAtLogin: LaunchAtLoginControlling {
    var isEnabled = false
    var failure: (any Error)?

    func setEnabled(_ enabled: Bool) throws {
        if let failure { throw failure }
        isEnabled = enabled
    }
}

@MainActor
final class OpenedURLs {
    var urls: [URL] = []
}

@MainActor
struct AppFixture {
    let model: AppModel
    let sink = ProbeSink()
    let store = MemoryStore()
    let accessibility: FakeAccessibility
    let launchAtLogin = FakeLaunchAtLogin()
    let opened = OpenedURLs()

    init(isTrusted: Bool = true) {
        accessibility = FakeAccessibility(isTrusted: isTrusted)
        let urls = opened
        let driver = GuitarDriver(monitor: SilentMonitor(), connector: UnreachableConnector(), sink: sink)
        model = AppModel(
            driver: driver, emitter: RecordingEmitter(), keymap: .default, store: store,
            accessibility: accessibility, launchAtLogin: launchAtLogin, openURL: { urls.urls.append($0) })
    }
}
