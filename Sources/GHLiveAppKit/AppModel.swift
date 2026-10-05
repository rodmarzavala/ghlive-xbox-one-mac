import Combine
import Foundation
import GHLiveCore
import GuitarInput
import KeyMapping
import KeyboardOutput

/// What the menu shows, as plain values so it can be rendered for any sample state.
public struct MenuPresentation: Equatable, Sendable {
    public let status: StatusPresentation
    public let isPaused: Bool
    public let needsAccessibility: Bool
    public let launchesAtLogin: Bool
    public let launchAtLoginProblem: String?
    public let keymapProblem: String?

    public init(
        status: StatusPresentation,
        isPaused: Bool,
        needsAccessibility: Bool,
        launchesAtLogin: Bool,
        launchAtLoginProblem: String? = nil,
        keymapProblem: String? = nil
    ) {
        self.status = status
        self.isPaused = isPaused
        self.needsAccessibility = needsAccessibility
        self.launchesAtLogin = launchesAtLogin
        self.launchAtLoginProblem = launchAtLoginProblem
        self.keymapProblem = keymapProblem
    }

    public var pauseTitle: String { isPaused ? "Resume" : "Pause" }
}

/// Owns the driver and everything the windows share: the keymap, the Accessibility permission and the
/// launch-at-login switch.
@MainActor
public final class AppModel: ObservableObject {
    public static let defaultPollInterval: Duration = .seconds(1)

    public let driver: GuitarDriver
    public let settings: SettingsModel

    @Published public private(set) var keymap: Keymap
    @Published public private(set) var isAccessibilityTrusted: Bool
    @Published public private(set) var launchesAtLogin: Bool
    @Published public private(set) var launchAtLoginProblem: String?

    private let emitter: any KeyEmitter
    private let accessibility: any AccessibilityChecking
    private let launchAtLogin: any LaunchAtLoginControlling
    private let openURL: (URL) -> Void
    private let pollInterval: Duration
    private var pollTask: Task<Void, Never>?
    private var driverChanges: AnyCancellable?
    private var settingsChanges: AnyCancellable?

    public init(
        driver: GuitarDriver,
        emitter: any KeyEmitter,
        keymap: Keymap,
        store: any KeymapPersisting,
        keymapProblem: String? = nil,
        accessibility: any AccessibilityChecking,
        launchAtLogin: any LaunchAtLoginControlling,
        openURL: @escaping (URL) -> Void,
        pollInterval: Duration = AppModel.defaultPollInterval
    ) {
        self.driver = driver
        self.emitter = emitter
        self.keymap = keymap
        self.accessibility = accessibility
        self.launchAtLogin = launchAtLogin
        self.openURL = openURL
        self.pollInterval = pollInterval
        isAccessibilityTrusted = accessibility.isTrusted
        launchesAtLogin = launchAtLogin.isEnabled
        settings = SettingsModel(keymap: keymap, store: store, loadProblem: keymapProblem)
        settings.onSaved = { [weak self] saved in self?.apply(saved) }
        driverChanges = driver.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        settingsChanges = settings.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }

    // MARK: Presentation

    public var menu: MenuPresentation {
        MenuPresentation(
            status: StatusPresentation(status: driver.status, isPaused: driver.isPaused),
            isPaused: driver.isPaused,
            needsAccessibility: !isAccessibilityTrusted,
            launchesAtLogin: launchesAtLogin,
            launchAtLoginProblem: launchAtLoginProblem,
            keymapProblem: settings.message.flatMap(Self.problemText)
        )
    }

    public var monitor: MonitorPresentation {
        MonitorPresentation(
            status: StatusPresentation(status: driver.status, isPaused: driver.isPaused),
            snapshot: driver.snapshot,
            thresholds: keymap.thresholds,
            bindings: keymap.bindings,
            isPaused: driver.isPaused
        )
    }

    private static func problemText(_ message: SettingsMessage) -> String? {
        guard case .problem(let text) = message else { return nil }
        return text
    }

    // MARK: Lifecycle

    public func start() {
        driver.start()
        startPollingAccessibility()
    }

    /// Releases every key and closes the dongle. Quitting waits for this.
    public func shutdown() async {
        pollTask?.cancel()
        pollTask = nil
        await driver.stop()
    }

    public func togglePause() {
        if driver.isPaused {
            driver.resume()
        } else {
            driver.pause()
        }
    }

    // MARK: Accessibility

    public func requestAccessibility() {
        accessibility.request()
        openURL(SystemLinks.accessibilitySettings)
    }

    /// Once the permission arrives, the output is rebuilt so it starts from a clean slate.
    public func refreshAccessibility() {
        let trusted = accessibility.isTrusted
        guard trusted != isAccessibilityTrusted else { return }
        isAccessibilityTrusted = trusted
        if trusted { apply(keymap) }
    }

    private func startPollingAccessibility() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self, pollInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: pollInterval)
                self?.refreshAccessibility()
            }
        }
    }

    // MARK: Launch at login

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLogin.setEnabled(enabled)
            launchAtLoginProblem = nil
        } catch {
            launchAtLoginProblem = "Could not change Launch at Login: \(error.localizedDescription)"
        }
        launchesAtLogin = launchAtLogin.isEnabled
    }

    // MARK: Keymap

    private func apply(_ newKeymap: Keymap) {
        keymap = newKeymap
        driver.reconfigure(sink: KeyboardSink(keymap: newKeymap, emitter: emitter), thresholds: newKeymap.thresholds)
    }
}
