import Foundation
import KeyMapping

/// Reports key events as text instead of posting them: safe to run anywhere.
@MainActor
public final class DryRunKeyEmitter: KeyEmitter {
    private let write: (String) -> Void

    public init(write: @escaping (String) -> Void) {
        self.write = write
    }

    public func keyDown(_ key: KeyCode) {
        write("key down \(label(for: key))")
    }

    public func keyUp(_ key: KeyCode) {
        write("key up \(label(for: key))")
    }

    private func label(for key: KeyCode) -> String {
        key.name ?? String(format: "0x%02X", key.rawValue)
    }
}
