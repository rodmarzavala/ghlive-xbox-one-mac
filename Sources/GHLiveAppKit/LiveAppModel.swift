import AppKit
import Foundation
import GHLiveCore
import KeyMapping
import KeyboardOutput

extension AppModel {
    /// Set to `1` to log key events to stderr instead of posting them (development only).
    public static let dryRunVariable = "GHLIVE_DRY_RUN"

    /// Only the exact value `1` enables it, so a stray `0` or empty value can never silence the keyboard
    /// by accident, and nothing else turns real key events off.
    public static func isDryRun(environment: [String: String]) -> Bool {
        environment[dryRunVariable] == "1"
    }

    public static func live(environment: [String: String] = ProcessInfo.processInfo.environment) -> AppModel {
        let isDryRun = isDryRun(environment: environment)
        let store = KeymapStore.standard
        let loaded = loadKeymap(from: store)
        let emitter: any KeyEmitter = isDryRun ? DryRunKeyEmitter(write: writeToStandardError) : CGEventKeyEmitter()
        let accessibility: any AccessibilityChecking = isDryRun ? NoAccessibilityNeeded() : SystemAccessibility()
        return AppModel(
            driver: GuitarDriver.live(keymap: loaded.keymap, emitter: emitter),
            emitter: emitter,
            keymap: loaded.keymap,
            store: store,
            keymapFolder: store.fileURL.deletingLastPathComponent(),
            keymapProblem: loaded.problem,
            accessibility: accessibility,
            launchAtLogin: SystemLaunchAtLogin(),
            openURL: { NSWorkspace.shared.open($0) }
        )
    }

    /// An unreadable keymap file must not stop the app: it runs on the defaults and says why.
    private static func loadKeymap(from store: KeymapStore) -> (keymap: Keymap, problem: String?) {
        do {
            return (try store.load(), nil)
        } catch {
            return (.default, error.localizedDescription)
        }
    }
}

private func writeToStandardError(_ line: String) {
    FileHandle.standardError.write(Data((line + "\n").utf8))
}
