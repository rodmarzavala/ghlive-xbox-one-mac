import GuitarInput
import Testing

@testable import KeyMapping

private let fretControls: Set<Control> = [.black1, .black2, .black3, .white1, .white2, .white3]

private func key(_ name: String) -> KeyCode { KeyCode.named(name)! }

@Suite("Keymap presets")
struct KeymapPresetTests {
    @Test("the six-fret preset is the default keymap")
    func sixFretIsDefault() {
        #expect(KeymapPreset.sixFret.keymap == Keymap.default)
    }

    @Test("every preset survives the file validation", arguments: KeymapPreset.allCases)
    func validates(preset: KeymapPreset) throws {
        let parsed = try Keymap.parse(json: preset.keymap.jsonData())
        #expect(parsed == preset.keymap)
        #expect(Set(preset.keymap.bindings.keys) == Set(Control.allCases))
    }

    @Test("every preset has a name and a description", arguments: KeymapPreset.allCases)
    func hasCopy(preset: KeymapPreset) {
        #expect(!preset.shortName.isEmpty)
        #expect(preset.displayName.hasPrefix(preset.shortName))
        #expect(!preset.displayName.isEmpty)
        #expect(!preset.summary.isEmpty)
    }

    @Test("raw values are the CLI names")
    func rawValues() {
        #expect(KeymapPreset.sixFret.rawValue == "six-fret")
        #expect(KeymapPreset.fiveFret.rawValue == "five-fret")
    }

    @Test("the five-fret preset sends exactly the lane keys 1 to 5")
    func fiveFretLaneKeys() {
        let laneKeys = Set(fretControls.compactMap { KeymapPreset.fiveFret.keymap.bindings[$0] })
        #expect(laneKeys == Set(["1", "2", "3", "4", "5"].map(key)))
    }

    @Test("the five-fret preset maps the lanes as documented")
    func fiveFretLanes() {
        let bindings = KeymapPreset.fiveFret.keymap.bindings
        #expect(bindings[.white1] == key("1"))
        #expect(bindings[.white2] == key("2"))
        #expect(bindings[.white3] == key("3"))
        #expect(bindings[.black2] == key("4"))
        #expect(bindings[.black3] == key("5"))
    }

    @Test("black 1 and white 1 both send Green")
    func firstColumnSharesGreen() {
        let bindings = KeymapPreset.fiveFret.keymap.bindings
        #expect(bindings[.black1] == bindings[.white1])
    }

    @Test("the non-fret controls and thresholds match the six-fret default")
    func nonFretControlsAreShared() {
        let others = Set(Control.allCases).subtracting(fretControls)
        for control in others {
            #expect(KeymapPreset.fiveFret.keymap.bindings[control] == Keymap.default.bindings[control])
        }
        #expect(KeymapPreset.fiveFret.keymap.thresholds == Keymap.default.thresholds)
    }

    @Test("a keymap is matched to its preset by keys alone")
    func matching() {
        #expect(KeymapPreset.matching(Keymap.default.bindings) == .sixFret)
        #expect(KeymapPreset.matching(KeymapPreset.fiveFret.keymap.bindings) == .fiveFret)
        var edited = KeymapPreset.fiveFret.keymap.bindings
        edited[.whammy] = key("z")
        #expect(KeymapPreset.matching(edited) == nil)
    }
}
