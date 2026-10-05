import KeyMapping

/// Turns the virtual key code of a recorded key press into a `KeyCode` GHLive can send.
public enum KeyRecorder {
    public enum Outcome: Equatable, Sendable {
        case accepted(KeyCode)
        case rejected(String)
    }

    static let unsupportedKeyMessage =
        "That key can't be used. Pick a letter, a digit, an arrow, Space, Tab, Return, Escape or F1 to F12."

    /// `keyCode` is `NSEvent.keyCode`, which uses the same virtual key codes as `KeyCode`.
    public static func outcome(forKeyCode keyCode: UInt16) -> Outcome {
        let key = KeyCode(rawValue: keyCode)
        guard key.name != nil else { return .rejected(unsupportedKeyMessage) }
        return .accepted(key)
    }
}
