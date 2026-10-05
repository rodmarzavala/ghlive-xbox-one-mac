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
    public let launchAtLogin: LaunchAtLoginState
    public let launchAtLoginProblem: String?
    public let keymapProblem: String?

    public init(
        status: StatusPresentation,
        isPaused: Bool,
        needsAccessibility: Bool,
        launchAtLogin: LaunchAtLoginState,
        launchAtLoginProblem: String? = nil,
        keymapProblem: String? = nil
    ) {
        self.status = status
        self.isPaused = isPaused
        self.needsAccessibility = needsAccessibility
        self.launchAtLogin = launchAtLogin
        self.launchAtLoginProblem = launchAtLoginProblem
        self.keymapProblem = keymapProblem
    }

    public var pauseTitle: String { isPaused ? "Resume" : "Pause" }
    public var launchesAtLogin: Bool { launchAtLogin == .enabled }
    public var launchAtLoginNeedsApproval: Bool { launchAtLogin == .requiresApproval }
}

/// Owns the driver and everything the windows share: the keymap, the Accessibility permission and the
/// launch-at-login switch.
///
/// Only `menu` and `keymap` publish. Guitar reports arrive many times a second and must not redraw the
/// menu, so the Input Monitor observes the driver itself.
@MainActor
public final class AppModel: ObservableObject {
    public static let defaultPollInterval: Duration = .seconds(1)
    public static let terminationTimeout: Duration = .seconds(3)

    public let driver: GuitarDriver
    public let settings: SettingsModel
    public let guitarTest: GuitarTestModel

    @Published public private(set) var keymap: Keymap
    @Published public private(set) var menu: MenuPresentation

    private let emitter: any KeyEmitter
    private let keymapFolder: URL
    private let accessibility: any AccessibilityChecking
    private let launchAtLogin: any LaunchAtLoginControlling
    private let openURL: (URL) -> Void
    private let pollInterval: Duration
    private var pollTask: Task<Void, Never>?
    private var pendingTermination: PendingTermination?
    private var subscriptions: Set<AnyCancellable> = []

    private var statusPresentation: StatusPresentation
    private var isTrusted: Bool
    private var launchState: LaunchAtLoginState
    private var launchProblem: String?
    private var keymapProblem: String?

    public init(
        driver: GuitarDriver,
        emitter: any KeyEmitter,
        keymap: Keymap,
        store: any KeymapPersisting,
        keymapFolder: URL,
        keymapProblem: String? = nil,
        accessibility: any AccessibilityChecking,
        launchAtLogin: any LaunchAtLoginControlling,
        openURL: @escaping (URL) -> Void,
        pollInterval: Duration = AppModel.defaultPollInterval
    ) {
        self.driver = driver
        self.emitter = emitter
        self.keymap = keymap
        self.keymapFolder = keymapFolder
        self.accessibility = accessibility
        self.launchAtLogin = launchAtLogin
        self.openURL = openURL
        self.pollInterval = pollInterval
        let settings = SettingsModel(keymap: keymap, store: store, loadProblem: keymapProblem)
        let status = StatusPresentation(status: driver.status, isPaused: driver.isPaused)
        let problem = Self.problemText(settings.message)
        let launchState = launchAtLogin.state
        self.settings = settings
        guitarTest = GuitarTestModel(thresholds: keymap.thresholds)
        statusPresentation = status
        isTrusted = accessibility.isTrusted
        self.launchState = launchState
        self.keymapProblem = problem
        menu = Self.menu(
            status: status, isPaused: driver.isPaused, isTrusted: accessibility.isTrusted, launch: launchState,
            launchProblem: nil, keymapProblem: problem)
        settings.onSaved = { [weak self] saved in self?.apply(saved) }
        settings.onOpenKeymapFolder = { [weak self] in self?.openKeymapFolder() }
        guitarTest.follow(driver.$snapshot)
        observeDriverAndSettings()
    }

    // MARK: Presentation

    /// Not published: it changes with every guitar report. Views that show it observe `driver`.
    public var monitor: MonitorPresentation {
        MonitorPresentation(
            status: statusPresentation,
            snapshot: driver.snapshot,
            thresholds: keymap.thresholds,
            bindings: keymap.bindings,
            isPaused: driver.isPaused
        )
    }

    private func observeDriverAndSettings() {
        driver.$status.combineLatest(driver.$isPaused)
            .sink { [weak self] status, isPaused in
                guard let self else { return }
                statusPresentation = StatusPresentation(status: status, isPaused: isPaused)
                publishMenu(isPaused: isPaused)
            }
            .store(in: &subscriptions)
        settings.$message
            .sink { [weak self] message in
                guard let self else { return }
                keymapProblem = Self.problemText(message)
                publishMenu()
            }
            .store(in: &subscriptions)
    }

    /// `isPaused` is passed in by the Combine sink, which runs before the driver's property has changed.
    private func publishMenu(isPaused: Bool? = nil) {
        let updated = Self.menu(
            status: statusPresentation, isPaused: isPaused ?? driver.isPaused, isTrusted: isTrusted,
            launch: launchState, launchProblem: launchProblem, keymapProblem: keymapProblem)
        if updated != menu { menu = updated }
    }

    private static func menu(
        status: StatusPresentation, isPaused: Bool, isTrusted: Bool, launch: LaunchAtLoginState,
        launchProblem: String?, keymapProblem: String?
    ) -> MenuPresentation {
        MenuPresentation(
            status: status, isPaused: isPaused, needsAccessibility: !isTrusted, launchAtLogin: launch,
            launchAtLoginProblem: launchProblem, keymapProblem: keymapProblem)
    }

    private static func problemText(_ message: SettingsMessage?) -> String? {
        switch message {
        case .problem(let text): text
        case .unreadableKeymap: SettingsCopy.unreadableKeymapHeadline
        case .saved, nil: nil
        }
    }

    // MARK: Lifecycle

    public func start() {
        driver.start()
        startPollingSystemState()
    }

    /// Releases every key and closes the dongle. Quitting waits for this.
    public func shutdown() async {
        pollTask?.cancel()
        pollTask = nil
        await driver.stop()
    }

    /// Answers the system's "may I quit?" question: `reply` runs once the keys are released, or after
    /// `timeout` if stopping hangs, so a stuck dongle can never keep the app from quitting. Asking again
    /// while a termination is pending joins it.
    public func terminate(timeout: Duration = AppModel.terminationTimeout, reply: @escaping @MainActor () -> Void) {
        terminate(shutdown: { await self.shutdown() }, timeout: timeout, reply: reply)
    }

    func terminate(
        shutdown: @escaping @MainActor () async -> Void, timeout: Duration, reply: @escaping @MainActor () -> Void
    ) {
        if let pending = pendingTermination {
            pending.add(reply)
            return
        }
        let pending = PendingTermination()
        pending.add(reply)
        pendingTermination = pending
        // Released before anything can hang, so even a timed-out quit leaves no key held.
        driver.pause()
        Task {
            await shutdown()
            pending.finish()
        }
        Task {
            try? await Task.sleep(for: timeout)
            pending.finish()
        }
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
        guard trusted != isTrusted else { return }
        isTrusted = trusted
        publishMenu()
        if trusted { apply(keymap) }
    }

    private func startPollingSystemState() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self, pollInterval] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: pollInterval) } catch { return }
                guard let self else { return }
                refreshAccessibility()
                refreshLaunchAtLogin()
            }
        }
    }

    // MARK: Launch at login

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLogin.setEnabled(enabled)
            launchProblem = nil
        } catch {
            launchProblem = "Could not change Launch at Login: \(error.localizedDescription)"
        }
        launchState = launchAtLogin.state
        publishMenu()
    }

    /// The user can approve or remove the login item in System Settings at any time.
    public func refreshLaunchAtLogin() {
        let state = launchAtLogin.state
        guard state != launchState else { return }
        launchState = state
        publishMenu()
    }

    public func openLoginItemsSettings() {
        launchAtLogin.openLoginItemsSettings()
    }

    // MARK: Keymap

    /// Opens the folder that holds `keymap.json`, creating it first so Finder never lands on a missing path.
    public func openKeymapFolder() {
        try? FileManager.default.createDirectory(at: keymapFolder, withIntermediateDirectories: true)
        openURL(keymapFolder)
    }

    private func apply(_ newKeymap: Keymap) {
        keymap = newKeymap
        guitarTest.updateThresholds(newKeymap.thresholds)
        driver.reconfigure(sink: KeyboardSink(keymap: newKeymap, emitter: emitter), thresholds: newKeymap.thresholds)
    }
}

/// The replies waiting for a termination to finish; each runs exactly once.
@MainActor
private final class PendingTermination {
    private var replies: [@MainActor () -> Void] = []
    private var isFinished = false

    func add(_ reply: @escaping @MainActor () -> Void) {
        if isFinished {
            reply()
        } else {
            replies.append(reply)
        }
    }

    func finish() {
        guard !isFinished else { return }
        isFinished = true
        let waiting = replies
        replies = []
        for reply in waiting { reply() }
    }
}

enum SettingsCopy {
    static let unreadableKeymapHeadline = "Your saved keys couldn't be read, so GHLive is using the defaults."
}
