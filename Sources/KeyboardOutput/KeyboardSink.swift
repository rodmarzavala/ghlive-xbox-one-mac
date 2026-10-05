import GuitarInput
import KeyMapping

/// Where guitar input goes. `KeyboardSink` is the keyboard implementation; a virtual-gamepad or DriverKit
/// sink can sit next to it and use `state` for the analog whammy and tilt that keys cannot carry.
@MainActor
public protocol OutputSink: AnyObject {
    func apply(state: GuitarState, controls: Set<Control>)
    /// Must leave nothing held. Called on stop, disconnect and pause.
    func releaseAll()
}

/// Posts one keyboard event. The seam that keeps `KeyboardSink` testable without a window server.
@MainActor
public protocol KeyEmitter: AnyObject {
    func keyDown(_ key: KeyCode)
    func keyUp(_ key: KeyCode)
}

/// Turns the set of active controls into key down/up events, emitting only the difference. Controls that
/// share a key keep it down while either is active.
@MainActor
public final class KeyboardSink: OutputSink {
    private let bindings: [Control: KeyCode]
    private let emitter: KeyEmitter
    public private(set) var pressedKeys: Set<KeyCode> = []

    public init(keymap: Keymap, emitter: KeyEmitter) {
        bindings = keymap.bindings
        self.emitter = emitter
    }

    public func apply(state: GuitarState, controls: Set<Control>) {
        move(to: Set(controls.compactMap { bindings[$0] }))
    }

    public func releaseAll() {
        move(to: [])
    }

    // A key is recorded as pressed before its key down is posted and forgotten only after its key up, so
    // a release that lands in between still lifts it: the worst case is a spurious up, never a stuck key.
    private func move(to target: Set<KeyCode>) {
        for key in pressedKeys.subtracting(target).sorted(by: { $0.rawValue < $1.rawValue }) {
            emitter.keyUp(key)
            pressedKeys.remove(key)
        }
        for key in target.subtracting(pressedKeys).sorted(by: { $0.rawValue < $1.rawValue }) {
            pressedKeys.insert(key)
            emitter.keyDown(key)
        }
    }
}
