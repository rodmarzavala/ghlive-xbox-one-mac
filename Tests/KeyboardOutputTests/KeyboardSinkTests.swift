import GuitarInput
import KeyMapping
import Testing

@testable import KeyboardOutput

private let keyA = KeyCode(rawValue: 0x10)
private let keyB = KeyCode(rawValue: 0x20)
private let keyShared = KeyCode(rawValue: 0x30)

enum KeyEvent: Hashable {
    case down(KeyCode)
    case up(KeyCode)
}

@MainActor
final class RecordingEmitter: KeyEmitter {
    var events: [KeyEvent] = []
    var onKeyDown: ((KeyCode) -> Void)?
    var onKeyUp: ((KeyCode) -> Void)?

    func keyDown(_ key: KeyCode) {
        events.append(.down(key))
        onKeyDown?(key)
    }

    func keyUp(_ key: KeyCode) {
        events.append(.up(key))
        onKeyUp?(key)
    }
}

private let idleState = GuitarState(pressedButtons: [], dpad: [], whammy: 0, tilt: 100)

@MainActor
@Suite("Keyboard sink")
struct KeyboardSinkTests {
    let emitter = RecordingEmitter()
    let sink: KeyboardSink

    init() {
        let bindings: [Control: KeyCode] = [
            .black1: keyA, .white1: keyB, .heroPower: keyShared, .tilt: keyShared,
        ]
        sink = KeyboardSink(keymap: Keymap(bindings: bindings), emitter: emitter)
    }

    private func apply(_ controls: Set<Control>) {
        sink.apply(state: idleState, controls: controls)
    }

    @Test("press then release")
    func pressThenRelease() {
        apply([.black1])
        apply([])
        #expect(emitter.events == [.down(keyA), .up(keyA)])
    }

    @Test("a held key is not repeated")
    func heldNotRepeated() {
        for _ in 0..<3 { apply([.black1]) }
        #expect(emitter.events == [.down(keyA)])
    }

    @Test("only the difference is emitted")
    func onlyTheDifference() {
        apply([.black1])
        apply([.black1, .white1])
        apply([.white1])
        #expect(emitter.events == [.down(keyA), .down(keyB), .up(keyA)])
    }

    @Test("unbound controls emit nothing")
    func unbound() {
        apply([.black3])
        #expect(emitter.events.isEmpty)
    }

    @Test("a shared key stays down while either control is active")
    func sharedKey() {
        apply([.heroPower])
        apply([.heroPower, .tilt])
        apply([.tilt])
        #expect(emitter.events == [.down(keyShared)])
        apply([])
        #expect(emitter.events == [.down(keyShared), .up(keyShared)])
    }

    @Test("releaseAll lifts every pressed key")
    func releaseAll() {
        apply([.black1, .white1])
        emitter.events.removeAll()
        sink.releaseAll()
        #expect(Set(emitter.events) == [.up(keyA), .up(keyB)])
        #expect(sink.pressedKeys.isEmpty)
    }

    @Test("releaseAll reports how many keys it lifted, and zero when nothing was held")
    func releaseAllCount() {
        apply([.black1, .white1])
        #expect(sink.releaseAll() == 2)
        #expect(sink.releaseAll() == 0)
    }

    @Test("releaseAll counts a key shared by two controls once")
    func releaseAllCountsSharedKeyOnce() {
        apply([.heroPower, .tilt])
        #expect(sink.releaseAll() == 1)
    }

    @Test("releaseAll is idempotent and the next press is emitted again")
    func releaseAllIdempotent() {
        apply([.black1])
        sink.releaseAll()
        sink.releaseAll()
        apply([.black1])
        #expect(emitter.events == [.down(keyA), .up(keyA), .down(keyA)])
    }

    @Test("a key is marked pressed before its key down is posted")
    func markedBeforeDown() {
        var markedDuringDown = false
        emitter.onKeyDown = { [sink] key in markedDuringDown = sink.pressedKeys.contains(key) }
        apply([.black1])
        #expect(markedDuringDown)
    }

    @Test("a key stays marked pressed until its key up has been posted")
    func unmarkedAfterUp() {
        apply([.black1])
        var markedDuringUp = false
        emitter.onKeyUp = { [sink] key in markedDuringUp = sink.pressedKeys.contains(key) }
        apply([])
        #expect(markedDuringUp)
        #expect(sink.pressedKeys.isEmpty)
    }

    @Test("a release arriving while a key down is being posted still lifts that key")
    func interruptedKeyDownIsReleased() {
        emitter.onKeyDown = { [sink] _ in sink.releaseAll() }
        apply([.black1])
        #expect(emitter.events == [.down(keyA), .up(keyA)])
        #expect(sink.pressedKeys.isEmpty)
    }
}

@MainActor
@Suite("Keyboard sink with the 5-fret preset")
struct FiveFretSinkTests {
    @Test("a fret pair sharing Green holds one key until both are released")
    func greenFromTwoFrets() throws {
        let emitter = RecordingEmitter()
        let sink = KeyboardSink(keymap: KeymapPreset.fiveFret.keymap, emitter: emitter)
        let green = try #require(KeyCode.named("1"))
        for controls: Set<Control> in [[.white1], [.white1, .black1], [.black1], []] {
            sink.apply(state: idleState, controls: controls)
        }
        #expect(emitter.events == [.down(green), .up(green)])
    }
}
