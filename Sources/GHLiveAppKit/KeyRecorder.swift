import AppKit
import KeyMapping

/// Turns the virtual key code of a recorded key press into a `KeyCode` GHLive can send.
public enum KeyRecorder {
    public enum Outcome: Equatable, Sendable {
        case accepted(KeyCode)
        case rejected(String)
    }

    static let unsupportedKeyMessage =
        "That key isn't supported. Try a letter, digit, arrow, Space, Tab, Return, Escape or F1\u{2013}F12. "
        + "Modifier keys such as Shift or Option can't be used on their own."

    private static let shortcutModifiers: NSEvent.ModifierFlags = [.command, .control, .option]

    /// Cmd, Ctrl and Opt combinations are shortcuts (Cmd-Q, Cmd-W): they must keep working while recording.
    public static func isShortcut(_ modifiers: NSEvent.ModifierFlags) -> Bool {
        !modifiers.intersection(shortcutModifiers).isEmpty
    }

    /// `keyCode` is `NSEvent.keyCode`, which uses the same virtual key codes as `KeyCode`.
    public static func outcome(forKeyCode keyCode: UInt16) -> Outcome {
        let key = KeyCode(rawValue: keyCode)
        guard key.name != nil else { return .rejected(unsupportedKeyMessage) }
        return .accepted(key)
    }
}
