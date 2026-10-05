import Foundation
import GHLiveCore
import GIPProtocol
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
    var state = LaunchAtLoginState.disabled
    var failure: (any Error)?
    private(set) var openedSettingsCount = 0

    func setEnabled(_ enabled: Bool) throws {
        if let failure { throw failure }
        state = enabled ? .enabled : .disabled
    }

    func openLoginItemsSettings() { openedSettingsCount += 1 }
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
    let keymapFolder = FileManager.default.temporaryDirectory
        .appendingPathComponent("ghlive-tests-\(UUID().uuidString)", isDirectory: true)

    init(
        isTrusted: Bool = true, dongle: ScriptedDongle? = nil, pollInterval: Duration = AppModel.defaultPollInterval
    ) {
        accessibility = FakeAccessibility(isTrusted: isTrusted)
        let urls = opened
        let driver = GuitarDriver(
            monitor: dongle.map { $0 as any DongleEventSource } ?? SilentMonitor(),
            connector: dongle.map { $0 as any DongleConnecting } ?? UnreachableConnector(), sink: sink)
        model = AppModel(
            driver: driver, emitter: RecordingEmitter(), keymap: .default, store: store,
            keymapFolder: keymapFolder, accessibility: accessibility, launchAtLogin: launchAtLogin,
            openURL: { urls.urls.append($0) },
            pollInterval: pollInterval)
    }
}

/// A dongle that is plugged in and delivers one guitar report with Black 1 held, then stays quiet.
struct ScriptedDongle: DongleEventSource, DongleConnecting {
    private static let black1Bit: UInt8 = 0x02
    private static let restingWhammy: UInt8 = 0x80

    func events() -> AsyncStream<DongleEvent> {
        AsyncStream { continuation in continuation.yield(.arrived) }
    }

    func connect() async throws -> any PacketTransport {
        ScriptedTransport(incoming: Self.black1Report())
    }

    private static func black1Report() -> Data {
        var payload = [UInt8](repeating: 0, count: GuitarReport.length)
        payload[GuitarReport.fretOffset] = black1Bit
        payload[GuitarReport.whammyOffset] = restingWhammy
        let packet = GipPacket(command: .ghlGuitarInput, flags: [], sequence: 1, payload: Data(payload))
        return packet.encoded()
    }
}

final class ScriptedTransport: PacketTransport, @unchecked Sendable {
    private let stream: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation

    init(incoming: Data) {
        (stream, continuation) = AsyncThrowingStream.makeStream(of: Data.self)
        continuation.yield(incoming)
    }

    func incomingPackets() -> AsyncThrowingStream<Data, Error> { stream }
    func write(_ data: Data) async throws {}
    func close() { continuation.finish() }
}
