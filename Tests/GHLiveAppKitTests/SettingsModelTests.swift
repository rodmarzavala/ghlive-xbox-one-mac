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

    @Test func shortcutsPassThroughWhileRecording() {
        let (model, store) = make()
        model.toggleRecording(.black1)
        let consumed = model.handleKeyDown(keyCode: Self.keyA, modifiers: .command)
        #expect(!consumed)
        #expect(model.recordingControl == .black1)
        #expect(store.saved.isEmpty)
    }

    @Test func switchingOrCancellingClearsTheWarning() {
        let (model, _) = make()
        model.toggleRecording(.black1)
        model.handleKeyDown(keyCode: Self.unsupported)
        #expect(model.recorderWarning != nil)
        model.toggleRecording(.white1)
        #expect(model.recorderWarning == nil)
        model.handleKeyDown(keyCode: Self.unsupported)
        model.cancelRecording()
        #expect(model.recorderWarning == nil)
        #expect(model.recordingControl == nil)
    }

    @Test func restoringDefaultsNeedsConfirmation() {
        let (model, store) = make()
        model.toggleRecording(.black1)
        model.handleKeyDown(keyCode: Self.keyA)
        let savedBefore = store.saved.count
        model.requestRestoreDefaults()
        #expect(model.isConfirmingRestore)
        #expect(model.bindings[.black1] == KeyCode.named("a"))
        model.cancelRestoreDefaults()
        #expect(!model.isConfirmingRestore)
        #expect(model.bindings[.black1] == KeyCode.named("a"))
        #expect(store.saved.count == savedBefore)
    }

    @Test func confirmingRestoreDefaultsResetsKeysAndThresholds() {
        let (model, store) = make()
        model.toggleRecording(.black1)
        model.handleKeyDown(keyCode: Self.keyA)
        model.tilt = 40
        model.whammy = 0.9
        model.requestRestoreDefaults()
        model.confirmRestoreDefaults()
        #expect(!model.isConfirmingRestore)
        #expect(model.bindings == Keymap.default.bindings)
        #expect(model.tilt == Double(Thresholds.defaultTilt))
        #expect(model.whammy == Thresholds.defaultWhammy)
        #expect(store.saved.last == .default)
    }

    @Test func theCurrentPresetFollowsTheKeys() {
        let (model, _) = make()
        #expect(model.currentPreset == .sixFret)
        model.toggleRecording(.black1)
        model.handleKeyDown(keyCode: Self.keyA)
        #expect(model.currentPreset == nil)
    }

    @Test func applyingAPresetNeedsConfirmation() {
        let (model, store) = make()
        model.requestPreset(.fiveFret)
        #expect(model.pendingPreset == .fiveFret)
        #expect(model.bindings == Keymap.default.bindings)
        #expect(store.saved.isEmpty)
    }

    @Test func cancellingThePresetKeepsTheKeys() {
        let (model, store) = make()
        model.requestPreset(.fiveFret)
        model.cancelPreset()
        #expect(model.pendingPreset == nil)
        #expect(model.bindings == Keymap.default.bindings)
        #expect(store.saved.isEmpty)
    }

    @Test func confirmingAPresetSavesItsKeysAndKeepsTheThresholds() {
        let (model, store) = make()
        var notified: [Keymap] = []
        model.onSaved = { notified.append($0) }
        model.tilt = 40
        model.whammy = 0.9
        model.requestPreset(.fiveFret)
        model.confirmPreset()
        #expect(model.pendingPreset == nil)
        #expect(model.bindings == KeymapPreset.fiveFret.keymap.bindings)
        #expect(model.currentPreset == .fiveFret)
        let saved = store.saved.last
        #expect(saved?.bindings == KeymapPreset.fiveFret.keymap.bindings)
        #expect(saved?.thresholds.tilt == 40)
        #expect(saved?.thresholds.whammy == 0.9)
        #expect(notified == store.saved)
    }

    @Test func confirmingWithoutARequestChangesNothing() {
        let (model, store) = make()
        model.confirmPreset()
        #expect(model.bindings == Keymap.default.bindings)
        #expect(store.saved.isEmpty)
    }

    @Test func requestingThePresetInUseDoesNotAsk() {
        let (model, _) = make()
        model.requestPreset(.sixFret)
        #expect(model.pendingPreset == nil)
    }

    @Test func sliderValuesAreSavedAsThresholds() {
        let (model, store) = make()
        model.tilt = 133
        model.whammy = 0.35
        model.commit()
        #expect(store.saved.last?.thresholds.tilt == 133)
        #expect(store.saved.last?.thresholds.whammy == 0.35)
    }

    @Test func aBandThatFitsIsSavedAsTheUserHasIt() throws {
        let (model, store) = make()
        model.tilt = 100
        model.commit()
        let saved = try #require(store.saved.last)
        #expect(saved.thresholds.tiltHysteresis == Thresholds.defaultTiltHysteresis)
        #expect(saved.thresholds.whammyHysteresis == Thresholds.defaultWhammyHysteresis)
        #expect(model.hysteresisNote == nil)
    }

    @Test func aBandThatDoesNotFitIsLoweredAndTheUserIsTold() throws {
        let (model, store) = make()
        model.tilt = 5
        model.whammy = SettingsModel.whammyRange.lowerBound
        model.commit()
        let saved = try #require(store.saved.last)
        #expect(saved.thresholds.tiltHysteresis < saved.thresholds.tilt)
        #expect(saved.thresholds.whammyHysteresis < saved.thresholds.whammy)
        #expect(model.message == .saved)
        #expect(model.hysteresisNote == SettingsModel.hysteresisNoteText)
    }

    @Test func aBandEqualToItsThresholdIsLoweredBelowIt() throws {
        let (model, store) = make()
        model.tilt = Double(Thresholds.defaultTiltHysteresis)
        model.whammy = Thresholds.defaultWhammyHysteresis
        model.commit()
        #expect(model.message == .saved)
        let saved = try #require(store.saved.last)
        #expect(saved.thresholds.tiltHysteresis < saved.thresholds.tilt)
        #expect(saved.thresholds.whammyHysteresis < saved.thresholds.whammy)
        #expect(model.hysteresisNote == SettingsModel.hysteresisNoteText)
    }

    @Test func movingBackRestoresTheOriginalBandAndDropsTheNote() throws {
        let (model, store) = make()
        model.tilt = 5
        model.commit()
        model.tilt = 150
        model.commit()
        let saved = try #require(store.saved.last)
        #expect(saved.thresholds.tiltHysteresis == Thresholds.defaultTiltHysteresis)
        #expect(model.hysteresisNote == nil)
    }

    @Test func theTiltRangeEndsAtTheSharedMaximum() {
        #expect(SettingsModel.tiltRange.upperBound == Thresholds.tiltMaximum)
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
        #expect(model.message == .unreadableKeymap(detail: "keymap.json is broken"))
        model.commit()
        #expect(model.message == .saved)
    }
}
