import GuitarInput
import KeyMapping
import Testing

@testable import GHLiveAppKit

@MainActor
struct SettingsModelTests {
    private static let keyA: UInt16 = 0x00
    private static let unsupported: UInt16 = 0x18

    private func make(store: MemoryStore = MemoryStore()) -> (SettingsModel, MemoryStore) {
        (SettingsModel(keymap: .default, store: store), store)
    }

    @Test func recordingBindsTheNextKeyAndSaves() {
        let (model, store) = make()
        var notified: [Keymap] = []
        model.onSaved = { notified.append($0) }
        model.toggleRecording(.black1)
        let consumed = model.handleKeyDown(keyCode: Self.keyA)
        #expect(consumed)
        #expect(model.key(for: .black1) == KeyCode.named("a"))
        #expect(model.recordingControl == nil)
        #expect(store.saved.last?.bindings[.black1] == KeyCode.named("a"))
        #expect(notified == store.saved)
        #expect(model.message == .saved)
    }

    @Test func unsupportedKeyKeepsRecordingAndWarns() {
        let (model, store) = make()
        model.toggleRecording(.black1)
        model.handleKeyDown(keyCode: Self.unsupported)
        #expect(model.recordingControl == .black1)
        #expect(model.recorderWarning == KeyRecorder.unsupportedKeyMessage)
        #expect(model.key(for: .black1) == Keymap.default.bindings[.black1])
        #expect(store.saved.isEmpty)
    }

    @Test func keyPressesAreIgnoredWhenNotRecording() {
        let (model, store) = make()
        let consumed = model.handleKeyDown(keyCode: Self.keyA)
        #expect(!consumed)
        #expect(store.saved.isEmpty)
    }

    @Test func clickingTheRecordingRowAgainCancels() {
        let (model, _) = make()
        model.toggleRecording(.tilt)
        model.toggleRecording(.tilt)
        #expect(model.recordingControl == nil)
    }

    @Test func restoreDefaultsResetsKeysAndThresholds() {
        let (model, store) = make()
        model.toggleRecording(.black1)
        model.handleKeyDown(keyCode: Self.keyA)
        model.tilt = 40
        model.whammy = 0.9
        model.restoreDefaults()
        #expect(model.bindings == Keymap.default.bindings)
        #expect(model.tilt == Double(Thresholds.defaultTilt))
        #expect(model.whammy == Thresholds.defaultWhammy)
        #expect(store.saved.last == .default)
    }

    @Test func sliderValuesAreSavedAsThresholds() {
        let (model, store) = make()
        model.tilt = 133
        model.whammy = 0.35
        model.commit()
        #expect(store.saved.last?.thresholds.tilt == 133)
        #expect(store.saved.last?.thresholds.whammy == 0.35)
    }

    @Test func lowThresholdsKeepAHysteresisBandThatFits() throws {
        let (model, store) = make()
        model.tilt = 5
        model.whammy = SettingsModel.whammyRange.lowerBound
        model.commit()
        let saved = try #require(store.saved.last)
        #expect(saved.thresholds.tiltHysteresis <= saved.thresholds.tilt / 2)
        #expect(saved.thresholds.whammyHysteresis <= saved.thresholds.whammy / 2)
        #expect(model.message == .saved)
    }

    @Test func invalidThresholdsAreReportedInlineAndNotSaved() {
        let (model, store) = make()
        var notified = 0
        model.onSaved = { _ in notified += 1 }
        model.tilt = 0
        model.commit()
        guard case .problem(let text) = model.message else {
            Issue.record("expected a problem, got \(String(describing: model.message))")
            return
        }
        #expect(text.contains("tilt"))
        #expect(store.saved.isEmpty)
        #expect(notified == 0)
    }

    @Test func aFailingStoreIsReportedInline() {
        let store = MemoryStore()
        store.failure = StoreFailure()
        let (model, _) = make(store: store)
        var notified = 0
        model.onSaved = { _ in notified += 1 }
        model.commit()
        #expect(model.message == .problem("disk is full"))
        #expect(notified == 0)
    }

    @Test func aLoadProblemIsShownUntilTheNextSave() {
        let model = SettingsModel(keymap: .default, store: MemoryStore(), loadProblem: "keymap.json is broken")
        #expect(model.message == .problem("keymap.json is broken"))
        model.commit()
        #expect(model.message == .saved)
    }
}
