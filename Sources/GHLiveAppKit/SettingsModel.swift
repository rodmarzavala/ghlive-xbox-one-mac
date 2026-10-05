import AppKit
import Combine
import Foundation
import GuitarInput
import KeyMapping

/// The part of `KeymapStore` the app uses, so tests do not touch the disk.
public protocol KeymapPersisting {
    func save(_ keymap: Keymap) throws
}

extension KeymapStore: KeymapPersisting {}

public enum SettingsMessage: Equatable, Sendable {
    case saved
    case problem(String)
    /// The keymap file on disk could not be read at launch; `detail` is the raw reason.
    case unreadableKeymap(detail: String)
}

/// Edits a draft keymap and saves it as soon as a change is complete (a key recorded, a slider released).
@MainActor
public final class SettingsModel: ObservableObject {
    public static let tiltRange = 1...Thresholds.tiltMaximum
    public static let whammyRange = 0.05...1.0

    static let hysteresisNoteText =
        "The release points were lowered so tilt and whammy can switch off again."

    @Published public private(set) var bindings: [Control: KeyCode]
    @Published public private(set) var recordingControl: Control?
    @Published public private(set) var message: SettingsMessage?
    @Published public private(set) var recorderWarning: String?
    @Published public private(set) var hysteresisNote: String?
    @Published public private(set) var isConfirmingRestore = false
    @Published public private(set) var pendingPreset: KeymapPreset?
    @Published public var tilt: Double
    @Published public var whammy: Double

    private var thresholds: Thresholds
    private let store: any KeymapPersisting

    /// Called with every keymap that was validated and saved.
    public var onSaved: (Keymap) -> Void = { _ in }
    public var onOpenKeymapFolder: () -> Void = {}

    /// - Parameter loadProblem: the reason the keymap file on disk could not be read, if it could not.
    public init(keymap: Keymap, store: any KeymapPersisting, loadProblem: String? = nil) {
        bindings = keymap.bindings
        thresholds = keymap.thresholds
        tilt = Double(keymap.thresholds.tilt)
        whammy = keymap.thresholds.whammy
        self.store = store
        message = loadProblem.map { .unreadableKeymap(detail: $0) }
    }

    public func key(for control: Control) -> KeyCode? { bindings[control] }

    // MARK: Recording

    /// Clicking the row being recorded again cancels the recording.
    public func toggleRecording(_ control: Control) {
        recorderWarning = nil
        recordingControl = recordingControl == control ? nil : control
    }

    public func cancelRecording() {
        recorderWarning = nil
        recordingControl = nil
    }

    /// Returns whether the key press was consumed by the recorder. Shortcuts are never consumed.
    @discardableResult
    public func handleKeyDown(keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) -> Bool {
        guard let control = recordingControl, !KeyRecorder.isShortcut(modifiers) else { return false }
        switch KeyRecorder.outcome(forKeyCode: keyCode) {
        case .accepted(let key):
            bindings[control] = key
            cancelRecording()
            commit()
        case .rejected(let reason):
            recorderWarning = reason
        }
        return true
    }

    // MARK: Restoring

    public func requestRestoreDefaults() {
        isConfirmingRestore = true
    }

    public func cancelRestoreDefaults() {
        isConfirmingRestore = false
    }

    public func confirmRestoreDefaults() {
        isConfirmingRestore = false
        cancelRecording()
        bindings = Keymap.default.bindings
        thresholds = Keymap.default.thresholds
        tilt = Double(thresholds.tilt)
        whammy = thresholds.whammy
        commit()
    }

    // MARK: Presets

    /// The preset the keys match exactly, or nil when the player changed any of them.
    public var currentPreset: KeymapPreset? { KeymapPreset.matching(bindings) }

    public func requestPreset(_ preset: KeymapPreset) {
        guard preset != currentPreset else { return }
        pendingPreset = preset
    }

    public func cancelPreset() {
        pendingPreset = nil
    }

    /// Replaces the keys only; the player's sensitivity settings stay.
    public func confirmPreset() {
        guard let preset = pendingPreset else { return }
        pendingPreset = nil
        cancelRecording()
        bindings = preset.keymap.bindings
        commit()
    }

    // MARK: Saving

    /// Validates with the same rules as a keymap file, then saves and hands the keymap to the driver.
    public func commit() {
        thresholds.tilt = Int(tilt.rounded())
        thresholds.whammy = whammy
        let keymap = currentKeymap()
        hysteresisNote = keymap.thresholds == thresholds ? nil : Self.hysteresisNoteText
        do {
            _ = try Keymap.parse(json: keymap.jsonData())
            try store.save(keymap)
        } catch {
            message = .problem(error.localizedDescription)
            return
        }
        message = .saved
        onSaved(keymap)
    }

    /// A release band must stay below its threshold. The draft keeps the user's band, so moving the slider
    /// back restores it; only the saved keymap is lowered, and only when it has to be.
    private func currentKeymap() -> Keymap {
        var effective = thresholds
        if effective.tiltHysteresis >= effective.tilt {
            effective.tiltHysteresis = max(effective.tilt - 1, 0)
        }
        if effective.whammyHysteresis >= effective.whammy {
            effective.whammyHysteresis = effective.whammy / 2
        }
        return Keymap(bindings: bindings, thresholds: effective)
    }
}
