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
}

/// Edits a draft keymap and saves it as soon as a change is complete (a key recorded, a slider released).
@MainActor
public final class SettingsModel: ObservableObject {
    public static let tiltRange = 1...255
    public static let whammyRange = 0.05...1.0

    @Published public private(set) var bindings: [Control: KeyCode]
    @Published public private(set) var recordingControl: Control?
    @Published public private(set) var message: SettingsMessage?
    @Published public private(set) var recorderWarning: String?
    @Published public var tilt: Double
    @Published public var whammy: Double

    private var thresholds: Thresholds
    private let store: any KeymapPersisting

    /// Called with every keymap that was validated and saved.
    public var onSaved: (Keymap) -> Void = { _ in }

    /// - Parameter loadProblem: shown inline when the keymap file on disk could not be read.
    public init(keymap: Keymap, store: any KeymapPersisting, loadProblem: String? = nil) {
        bindings = keymap.bindings
        thresholds = keymap.thresholds
        tilt = Double(keymap.thresholds.tilt)
        whammy = keymap.thresholds.whammy
        self.store = store
        message = loadProblem.map { .problem($0) }
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

    /// Returns whether the key press was consumed by the recorder.
    @discardableResult
    public func handleKeyDown(keyCode: UInt16) -> Bool {
        guard let control = recordingControl else { return false }
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

    // MARK: Saving

    public func restoreDefaults() {
        cancelRecording()
        bindings = Keymap.default.bindings
        thresholds = Keymap.default.thresholds
        tilt = Double(thresholds.tilt)
        whammy = thresholds.whammy
        commit()
    }

    /// Validates with the same rules as a keymap file, then saves and hands the keymap to the driver.
    public func commit() {
        thresholds.tilt = Int(tilt.rounded())
        thresholds.whammy = whammy
        let keymap = currentKeymap()
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

    /// A band as wide as its threshold would release at zero, which a control can never fall below, so the
    /// key would stick. Capping at half the threshold keeps low slider positions usable.
    private func currentKeymap() -> Keymap {
        var effective = thresholds
        effective.tiltHysteresis = min(effective.tiltHysteresis, effective.tilt / 2)
        effective.whammyHysteresis = min(effective.whammyHysteresis, effective.whammy / 2)
        return Keymap(bindings: bindings, thresholds: effective)
    }
}
