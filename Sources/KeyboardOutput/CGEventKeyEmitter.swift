import ApplicationServices
import CoreGraphics
import KeyMapping

/// Posts real key events at the HID level. Needs the Accessibility permission (see `AccessibilityPermission`).
@MainActor
public final class CGEventKeyEmitter: KeyEmitter {
    private let source = CGEventSource(stateID: .hidSystemState)

    public init() {}

    public func keyDown(_ key: KeyCode) {
        post(key, isDown: true)
    }

    public func keyUp(_ key: KeyCode) {
        post(key, isDown: false)
    }

    private func post(_ key: KeyCode, isDown: Bool) {
        CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key.rawValue), keyDown: isDown)?
            .post(tap: .cghidEventTap)
    }
}

public enum AccessibilityPermission {
    // The literal behind kAXTrustedCheckOptionPrompt, which Swift 6 rejects as non-Sendable global state.
    private static let promptOptionKey = "AXTrustedCheckOptionPrompt"

    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Returns the current trust and, when it is not granted yet, shows the system prompt that leads to
    /// System Settings > Privacy & Security > Accessibility.
    @discardableResult
    public static func request() -> Bool {
        let options = [promptOptionKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
