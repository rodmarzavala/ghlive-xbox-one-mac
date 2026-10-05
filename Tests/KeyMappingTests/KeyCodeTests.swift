import Testing

@testable import KeyMapping

/// Carbon HIToolbox Events.h values, asserted as literals so a typo in the table cannot hide behind itself.
private let knownKeyCodes: [String: UInt16] = [
    "a": 0x00, "q": 0x0C, "1": 0x12, "0": 0x1D, "space": 0x31, "escape": 0x35, "up": 0x7E, "f12": 0x6F,
    "x": 0x07, "tab": 0x30, "return": 0x24, "left": 0x7B, "right": 0x7C, "down": 0x7D, "f1": 0x7A, "m": 0x2E,
]

@Suite("Key codes")
struct KeyCodeTests {
    @Test("the table matches HIToolbox", arguments: knownKeyCodes.sorted(by: { $0.key < $1.key }))
    func matchesHIToolbox(entry: (key: String, value: UInt16)) {
        #expect(KeyCode.named(entry.key)?.rawValue == entry.value)
    }

    @Test("the table covers every required name")
    func coversRequiredNames() {
        var required = "abcdefghijklmnopqrstuvwxyz0123456789".map(String.init)
        required += ["up", "down", "left", "right", "space", "return", "escape", "tab"]
        required += (1...12).map { "f\($0)" }
        #expect(required.filter { KeyCode.named($0) == nil }.isEmpty)
    }

    @Test("two names never share a key code")
    func codesAreUnique() {
        let codes = KeyCode.allNames.compactMap { KeyCode.named($0)?.rawValue }
        #expect(Set(codes).count == KeyCode.allNames.count)
        #expect(codes.count == KeyCode.allNames.count)
    }

    @Test("names are case-insensitive and round-trip")
    func caseInsensitiveRoundTrip() {
        #expect(KeyCode.named("SPACE") == KeyCode.named("space"))
        for name in KeyCode.allNames {
            #expect(KeyCode.named(name)?.name == name)
        }
    }

    @Test("an unknown name is nil")
    func unknown() {
        #expect(KeyCode.named("hyper") == nil)
    }
}
