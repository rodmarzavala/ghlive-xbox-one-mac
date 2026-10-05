import Foundation
import GuitarInput
import Testing

@testable import KeyMapping

private func json(_ text: String) -> Data { Data(text.utf8) }

private let whammyRange = "above 0 and at most 1"
private let whammyBand = "0 or more and below the whammy threshold"
private let tiltRange = "between 1 and 255"
private let tiltBand = "0 or more and below the tilt threshold"

// Lower-bound inputs carry a zero band so the band check cannot be what rejects them.
private let outOfRangeCases: [(String, KeymapError)] = [
    (#"{"whammy": 0, "whammy_hysteresis": 0}"#, .thresholdOutOfRange("whammy", value: 0, allowed: whammyRange)),
    (#"{"whammy": 1.5}"#, .thresholdOutOfRange("whammy", value: 1.5, allowed: whammyRange)),
    (#"{"whammy": -0.2, "whammy_hysteresis": 0}"#, .thresholdOutOfRange("whammy", value: -0.2, allowed: whammyRange)),
    (#"{"whammy_hysteresis": -0.1}"#, .thresholdOutOfRange("whammy_hysteresis", value: -0.1, allowed: whammyBand)),
    (
        #"{"whammy": 0.3, "whammy_hysteresis": 0.4}"#,
        .thresholdOutOfRange("whammy_hysteresis", value: 0.4, allowed: whammyBand)
    ),
    (
        #"{"whammy": 0.3, "whammy_hysteresis": 0.3}"#,
        .thresholdOutOfRange("whammy_hysteresis", value: 0.3, allowed: whammyBand)
    ),
    (#"{"tilt": 0, "tilt_hysteresis": 0}"#, .thresholdOutOfRange("tilt", value: 0, allowed: tiltRange)),
    (#"{"tilt": 256, "tilt_hysteresis": 0}"#, .thresholdOutOfRange("tilt", value: 256, allowed: tiltRange)),
    (#"{"tilt_hysteresis": -1}"#, .thresholdOutOfRange("tilt_hysteresis", value: -1, allowed: tiltBand)),
    (
        #"{"tilt": 100, "tilt_hysteresis": 101}"#,
        .thresholdOutOfRange("tilt_hysteresis", value: 101, allowed: tiltBand)
    ),
    (
        #"{"tilt": 100, "tilt_hysteresis": 100}"#,
        .thresholdOutOfRange("tilt_hysteresis", value: 100, allowed: tiltBand)
    ),
]

private func key(_ name: String) -> KeyCode { KeyCode.named(name)! }

@Suite("Default keymap")
struct DefaultKeymapTests {
    @Test("binds the documented keys")
    func documentedBindings() {
        let expected: [Control: String] = [
            .black1: "1", .black2: "2", .black3: "3",
            .white1: "q", .white2: "w", .white3: "e",
            .strumUp: "up", .strumDown: "down",
            .heroPower: "space", .tilt: "space",
            .whammy: "x", .pause: "escape", .ghtv: "tab",
            .dpadUp: "up", .dpadDown: "down", .dpadLeft: "left", .dpadRight: "right",
        ]
        #expect(Keymap.default.bindings == expected.mapValues(key))
    }

    @Test("binds every control")
    func bindsEveryControl() {
        #expect(Set(Keymap.default.bindings.keys) == Set(Control.allCases))
    }

    @Test("uses the default thresholds")
    func defaultThresholds() {
        #expect(Keymap.default.thresholds == Thresholds())
    }

    @Test("survives an encode and decode round trip")
    func roundTrip() throws {
        let encoded = try Keymap.default.jsonData()
        #expect(try Keymap.parse(json: encoded) == Keymap.default)
    }

    @Test("prints stable, human-readable JSON")
    func printsJSON() throws {
        let text = String(decoding: try Keymap.default.jsonData(), as: UTF8.self)
        #expect(text.contains("\"black_1\" : \"1\""))
        #expect(text.contains("\"whammy_hysteresis\" : 0.1"))
    }
}

@Suite("Keymap parsing")
struct KeymapParsingTests {
    @Test("thresholds default when omitted")
    func thresholdsDefault() throws {
        let keymap = try Keymap.parse(json: json(#"{"keys": {"black_1": "a"}}"#))
        #expect(keymap.bindings == [.black1: key("a")])
        #expect(keymap.thresholds == Thresholds())
    }

    @Test("thresholds can be overridden")
    func thresholdsOverridden() throws {
        let text = """
            {"keys": {}, "thresholds": {"whammy": 0.25, "whammy_hysteresis": 0.05, "tilt": 140, "tilt_hysteresis": 4}}
            """
        let thresholds = try Keymap.parse(json: json(text)).thresholds
        #expect(thresholds == Thresholds(whammy: 0.25, whammyHysteresis: 0.05, tilt: 140, tiltHysteresis: 4))
    }

    @Test("several controls may share a key")
    func sharedKey() throws {
        let keymap = try Keymap.parse(json: json(#"{"keys": {"tilt": "space", "hero_power": "space"}}"#))
        #expect(keymap.bindings[.tilt] == keymap.bindings[.heroPower])
    }

    @Test("an unknown control is named in the error")
    func unknownControl() {
        #expect(throws: KeymapError.unknownControl("banjo_1")) {
            try Keymap.parse(json: json(#"{"keys": {"banjo_1": "a"}}"#))
        }
    }

    @Test("an unknown key is named in the error together with its control")
    func unknownKey() {
        #expect(throws: KeymapError.unknownKey("hyper", control: "black_1")) {
            try Keymap.parse(json: json(#"{"keys": {"black_1": "hyper"}}"#))
        }
    }

    @Test("an unknown threshold is named in the error")
    func unknownThreshold() {
        #expect(throws: KeymapError.unknownThreshold("wobble")) {
            try Keymap.parse(json: json(#"{"keys": {}, "thresholds": {"wobble": 1}}"#))
        }
    }

    @Test("a non-numeric threshold is rejected")
    func nonNumericThreshold() {
        #expect(throws: KeymapError.self) {
            try Keymap.parse(json: json(#"{"keys": {}, "thresholds": {"tilt": "high"}}"#))
        }
    }

    @Test("a fractional integer threshold is rejected")
    func fractionalTilt() {
        #expect(throws: KeymapError.thresholdOutOfRange("tilt", value: 150.5, allowed: "a whole number")) {
            try Keymap.parse(json: json(#"{"keys": {}, "thresholds": {"tilt": 150.5}}"#))
        }
    }

    @Test("out-of-range thresholds are rejected with the exact error", arguments: outOfRangeCases)
    func outOfRange(thresholds: String, expected: KeymapError) {
        #expect(throws: expected) {
            try Keymap.parse(json: json(#"{"keys": {}, "thresholds": \#(thresholds)}"#))
        }
    }

    @Test("boundary thresholds are accepted")
    func boundaries() throws {
        let text =
            #"{"keys": {}, "thresholds": {"whammy": 1, "whammy_hysteresis": 0.99, "tilt": 255, "tilt_hysteresis": 254}}"#
        let thresholds = try Keymap.parse(json: json(text)).thresholds
        #expect(thresholds == Thresholds(whammy: 1, whammyHysteresis: 0.99, tilt: 255, tiltHysteresis: 254))
    }

    @Test("invalid JSON is a keymap error")
    func invalidJSON() {
        #expect(throws: KeymapError.self) {
            try Keymap.parse(json: json("{keys"))
        }
    }

    @Test("a missing keys table is a keymap error")
    func missingKeys() {
        #expect(throws: KeymapError.self) {
            try Keymap.parse(json: json("{}"))
        }
    }

    @Test("error messages are readable")
    func readableMessages() {
        #expect(KeymapError.unknownKey("hyper", control: "black_1").description.contains("hyper"))
        #expect(KeymapError.unknownKey("hyper", control: "black_1").description.contains("black_1"))
        #expect(KeymapError.unknownControl("banjo_1").description.contains("banjo_1"))
    }

    @Test("a missing file is a keymap error naming the path")
    func missingFile() {
        let url = URL(fileURLWithPath: "/nonexistent/nope.json")
        do {
            _ = try Keymap.load(from: url)
            Issue.record("expected an error")
        } catch let error as KeymapError {
            #expect(error.description.contains("nope.json"))
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }
}

@Suite("Keymap store")
struct KeymapStoreTests {
    private func makeStore() -> (KeymapStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghlive-tests-\(UUID().uuidString)", isDirectory: true)
        return (KeymapStore(fileURL: directory.appendingPathComponent("GHLive/keymap.json")), directory)
    }

    @Test("a missing file falls back to the default")
    func fallsBack() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(try store.load() == Keymap.default)
    }

    @Test("save creates the directory and load reads it back")
    func saveThenLoad() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        var keymap = Keymap.default
        keymap.bindings[.whammy] = key("z")
        keymap.thresholds.tilt = 140
        try store.save(keymap)
        #expect(try store.load() == keymap)
    }

    @Test("an invalid file is reported, not silently replaced")
    func invalidFileThrows() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: store.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not json".utf8).write(to: store.fileURL)
        #expect(throws: KeymapError.self) { try store.load() }
    }

    @Test("the standard location is under Application Support")
    func standardLocation() {
        let path = KeymapStore.standard.fileURL.path
        #expect(path.hasSuffix("Library/Application Support/GHLive/keymap.json"))
    }
}
