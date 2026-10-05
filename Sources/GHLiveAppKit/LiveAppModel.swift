import AppKit
import Foundation
import GHLiveCore
import KeyMapping
import KeyboardOutput

extension AppModel {
    /// Set to `1` to log key events to stderr instead of posting them (development only).
    public static let dryRunVariable = "GHLIVE_DRY_RUN"

    public static func live(environment: [String: String] = ProcessInfo.processInfo.environment) -> AppModel {
        let isDryRun = environment[dryRunVariable] == "1"
        let store = KeymapStore.standard
        let loaded = loadKeymap(from: store)
        let emitter: any KeyEmitter = isDryRun ? DryRunKeyEmitter(write: writeToStandardError) : CGEventKeyEmitter()
        let accessibility: any AccessibilityChecking = isDryRun ? NoAccessibilityNeeded() : SystemAccessibility()
        return AppModel(
            driver: GuitarDriver.live(keymap: loaded.keymap, emitter: emitter),
            emitter: emitter,
            keymap: loaded.keymap,
            store: store,
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
            return (.default, "\(error.localizedDescription) Using the default keys until you change a setting.")
        }
    }

    /// Opens the folder that holds `keymap.json`, creating it first so the Finder window is never empty-handed.
    public func openKeymapFolder() {
        let folder = KeymapStore.standard.fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}

private func writeToStandardError(_ line: String) {
    FileHandle.standardError.write(Data((line + "\n").utf8))
}
