import KeyMapping
import Testing

@testable import KeyboardOutput

@MainActor
@Suite("Dry-run emitter")
struct DryRunKeyEmitterTests {
    @Test("prints key names instead of posting events")
    func printsNames() {
        var lines: [String] = []
        let emitter = DryRunKeyEmitter { lines.append($0) }
        emitter.keyDown(KeyCode.named("space")!)
        emitter.keyUp(KeyCode.named("space")!)
        #expect(lines == ["key down space", "key up space"])
    }

    @Test("falls back to the hex code for keys outside the table")
    func unnamedKey() {
        var lines: [String] = []
        let emitter = DryRunKeyEmitter { lines.append($0) }
        emitter.keyDown(KeyCode(rawValue: 0x2A))
        #expect(lines == ["key down 0x2A"])
    }
}
