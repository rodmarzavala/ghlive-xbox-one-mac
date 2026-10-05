import AppKit
import ChartConversion
import GHLiveCore
import GuitarInput
import KeyMapping
import SwiftUI
import USBTransport

/// Renders the menu, Settings and Input Monitor with sample states to PNG, in light and dark appearance, for
/// design review. Nothing here touches the dongle or posts key events.
@MainActor
public enum ScreenshotExporter {
    public enum ExportError: Error, Equatable {
        case renderFailed(String)
    }

    struct Appearance {
        let name: String
        let scheme: ColorScheme
        let background: Color
    }

    static let appearances = [
        Appearance(name: "light", scheme: .light, background: Color(white: 0.94)),
        Appearance(name: "dark", scheme: .dark, background: Color(white: 0.17)),
    ]

    private static let renderScale: CGFloat = 2

    /// Writes `<name>-light.png` and `<name>-dark.png` for every sample and returns the files.
    @discardableResult
    public static func export(to directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [URL] = []
        for sample in SampleStates.screens() {
            for appearance in appearances {
                let url = directory.appendingPathComponent("\(sample.name)-\(appearance.name).png")
                try writePNG(of: sample.view, appearance: appearance, to: url)
                written.append(url)
            }
        }
        return written
    }

    /// `ImageRenderer` draws Liquid Glass as blank, so screenshots always take the classic look.
    static func styled<Content: View>(_ view: Content, appearance: Appearance) -> some View {
        view
            .background(appearance.background)
            .environment(\.colorScheme, appearance.scheme)
            .environment(\.surfaceStyle, .classic)
    }

    private static func writePNG(of view: AnyView, appearance: Appearance, to url: URL) throws {
        let renderer = ImageRenderer(content: styled(view, appearance: appearance))
        renderer.scale = renderScale
        guard let image = renderer.nsImage,
            let tiff = image.tiffRepresentation,
            let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { throw ExportError.renderFailed(url.lastPathComponent) }
        try png.write(to: url)
    }
}

struct SampleScreen {
    let name: String
    let view: AnyView
}

/// Representative driver states, so every look can be reviewed without hardware.
@MainActor
enum SampleStates {
    private static let nearTilt: UInt8 = 142

    static func screens() -> [SampleScreen] {
        menuScreens() + monitorScreens() + settingsScreens() + chartConversionScreens()
    }

    // MARK: Menu

    private static func menuScreens() -> [SampleScreen] {
        let waiting = StatusPresentation(status: .waitingForDongle, isPaused: false)
        let ready = StatusPresentation(status: .dongleReady, isPaused: false)
        let active = StatusPresentation(status: .guitarActive, isPaused: false)
        let paused = StatusPresentation(status: .guitarActive, isPaused: true)
        let connecting = StatusPresentation(status: .connecting, isPaused: false)
        let busy = StatusPresentation(
            status: .error(DongleError.exclusiveAccess.localizedDescription), isPaused: false)
        let failure = StatusPresentation(
            status: .error(DongleError.ioFailure(operation: "read", code: -1).localizedDescription), isPaused: false)
        return [
            menu("menu-waiting", waiting),
            menu("menu-needs-accessibility", waiting, needsAccessibility: true),
            menu("menu-connecting", connecting),
            menu("menu-ready", ready),
            menu("menu-active", active, launchAtLogin: .enabled),
            menu("menu-login-needs-approval", active, launchAtLogin: .requiresApproval),
            menu("menu-paused", paused),
            menu("menu-dongle-busy", busy),
            menu("menu-error", failure),
        ]
    }

    private static func menu(
        _ name: String, _ status: StatusPresentation, needsAccessibility: Bool = false,
        launchAtLogin: LaunchAtLoginState = .disabled
    ) -> SampleScreen {
        let presentation = MenuPresentation(
            status: status, isPaused: status.tone == .paused, needsAccessibility: needsAccessibility,
            launchAtLogin: launchAtLogin)
        return SampleScreen(name: name, view: AnyView(MenuContentView(menu: presentation, actions: MenuActions())))
    }

    // MARK: Monitor

    private static func monitorScreens() -> [SampleScreen] {
        let thresholds = Keymap.default.thresholds
        return [
            monitor("monitor-waiting", status: .waitingForDongle, snapshot: nil),
            monitor("monitor-ready", status: .dongleReady, snapshot: nil),
            monitor(
                "monitor-active", status: .guitarActive,
                snapshot: snapshot(
                    buttons: [.black1, .white2, .strumDown], dpad: [], whammy: 0.4, tilt: nearTilt,
                    thresholds: thresholds)),
            monitor(
                "monitor-active-engaged", status: .guitarActive,
                snapshot: snapshot(
                    buttons: [.black2, .black3, .white1, .strumUp, .heroPower], dpad: [.left], whammy: 0.9,
                    tilt: 171, thresholds: thresholds)),
            monitor("monitor-error", status: .error(DongleError.exclusiveAccess.localizedDescription), snapshot: nil),
            monitor(
                "monitor-guitar-test", status: .guitarActive, snapshot: halfwayThroughTest.snapshot,
                test: halfwayThroughTest.model),
            monitor(
                "monitor-guitar-test-complete", status: .guitarActive, snapshot: finishedTest.snapshot,
                test: finishedTest.model),
        ]
    }

    // MARK: Guitar test

    private static let sweepTilt: UInt8 = 171
    private static let restingTilt: UInt8 = 100

    /// A test model that has seen `presses` one after another, then `analog` states.
    private static func guitarTest(pressing presses: [Control], analog: [GuitarState]) -> GuitarTestModel {
        let model = GuitarTestModel()
        model.isActive = true
        var detector = ControlDetector(thresholds: Keymap.default.thresholds)
        let idle = analogState(whammy: 0, tilt: restingTilt)
        for control in presses {
            model.receive(GuitarSnapshot(state: idle, controls: detector.detect(idle).union([control])))
        }
        for state in analog { model.receive(GuitarSnapshot(state: state, controls: detector.detect(state))) }
        return model
    }

    private static func analogState(whammy: Double, tilt: UInt8) -> GuitarState {
        GuitarState(pressedButtons: [], dpad: [], whammy: whammy, tilt: tilt)
    }

    /// Some frets and buttons verified, the whammy bar pressed but not yet released, tilt not tried.
    static var halfwayThroughTest: (model: GuitarTestModel, snapshot: GuitarSnapshot) {
        let pressed: [Control] = [.black1, .black2, .white1, .white2, .strumUp, .strumDown, .heroPower]
        let model = guitarTest(
            pressing: pressed,
            analog: [
                analogState(whammy: 0.03, tilt: restingTilt), analogState(whammy: 0.95, tilt: restingTilt),
            ])
        let snapshot = snapshot(
            buttons: [.black3], dpad: [], whammy: 0.95, tilt: restingTilt, thresholds: Keymap.default.thresholds)
        return (model, snapshot)
    }

    static var finishedTest: (model: GuitarTestModel, snapshot: GuitarSnapshot) {
        let model = guitarTest(
            pressing: GuitarTestSession.digitalControls,
            analog: [
                analogState(whammy: 0, tilt: restingTilt), analogState(whammy: 1, tilt: sweepTilt),
                analogState(whammy: 0, tilt: restingTilt),
            ])
        let snapshot = snapshot(
            buttons: [], dpad: [], whammy: 0, tilt: restingTilt, thresholds: Keymap.default.thresholds)
        return (model, snapshot)
    }

    private static func monitor(
        _ name: String, status: DriverStatus, snapshot: GuitarSnapshot?, test: GuitarTestModel? = nil
    ) -> SampleScreen {
        let presentation = MonitorPresentation(
            status: StatusPresentation(status: status, isPaused: false),
            snapshot: snapshot, thresholds: Keymap.default.thresholds, bindings: Keymap.default.bindings,
            isPaused: false)
        return SampleScreen(
            name: name,
            view: AnyView(
                MonitorView(
                    monitor: presentation, guitarTest: test ?? GuitarTestModel(),
                    limitsHeight: false)))
    }

    private static func snapshot(
        buttons: Set<GuitarButton>, dpad: Set<DpadDirection>, whammy: Double, tilt: UInt8, thresholds: Thresholds
    ) -> GuitarSnapshot {
        let state = GuitarState(pressedButtons: buttons, dpad: dpad, whammy: whammy, tilt: tilt)
        var detector = ControlDetector(thresholds: thresholds)
        return GuitarSnapshot(state: state, controls: detector.detect(state))
    }

    // MARK: Chart conversion

    private static let sampleSongs = URL(fileURLWithPath: "/Users/you/Clone Hero Songs", isDirectory: true)
    private static let sampleBackup = URL(
        fileURLWithPath: "/Users/you/Clone Hero Songs - backup 2025-01-31 183000", isDirectory: true)

    private static func chartConversion(_ name: String, _ state: ChartConversionState) -> SampleScreen {
        let model = ChartConversionModel(state: state)
        return SampleScreen(
            name: name, view: AnyView(ChartConversionView(model: model, scrollsSongList: false)))
    }

    private static func sampleReport(failing: Bool) -> ConversionReport {
        let converted = SongOutcome.converted(
            addedTracks: ["ExpertGHLGuitar"], notes: 1_204, songIni: .added(value: "3"))
        var results = [
            SongResult(path: "Synthetic Artist - Synthetic Song/notes.chart", outcome: converted),
            SongResult(
                path: "Pack One/Another Artist - Another Song/notes.mid",
                outcome: .converted(addedTracks: ["PART GUITAR GHL"], notes: 3_872, songIni: .alreadyPresent)),
            SongResult(path: "Pack One/Third Artist - Third Song/notes.chart", outcome: .alreadyHasSixFret),
            SongResult(path: "Pack Two/Fourth Artist - Fourth Song/song.sng", outcome: .unsupportedFormat),
        ]
        if failing {
            results.append(
                SongResult(
                    path: "Pack Two/Fifth Artist - Fifth Song/notes.mid",
                    outcome: .failed("the MIDI file ends inside a MTrk chunk")))
        }
        return ConversionReport(root: sampleSongs, isDryRun: false, results: results, backupFolder: sampleBackup)
    }

    private static func chartConversionScreens() -> [SampleScreen] {
        [
            chartConversion("chart-conversion-confirm", .confirming(folder: sampleSongs)),
            chartConversion("chart-conversion-result", .finished(sampleReport(failing: false))),
            chartConversion("chart-conversion-result-problem", .finished(sampleReport(failing: true))),
        ]
    }

    // MARK: Settings

    private struct DiscardingStore: KeymapPersisting {
        func save(_ keymap: Keymap) throws {}
    }

    private static func settingsScreens() -> [SampleScreen] {
        let saved = SettingsModel(keymap: .default, store: DiscardingStore())
        saved.commit()
        let recording = SettingsModel(keymap: .default, store: DiscardingStore())
        recording.toggleRecording(.white2)
        recording.handleKeyDown(keyCode: unsupportedKeyCode)
        let broken = SettingsModel(
            keymap: .default, store: DiscardingStore(),
            loadProblem: "keymap.json: unknown key 'ctrl' for control 'tilt'"
        )
        let waiting = SettingsModel(keymap: .default, store: DiscardingStore())
        waiting.toggleRecording(.black1)
        let fiveFret = SettingsModel(keymap: .default, store: DiscardingStore())
        fiveFret.requestPreset(.fiveFret)
        fiveFret.confirmPreset()
        return [
            settings("settings", saved),
            settings("settings-preset-five-fret", fiveFret),
            settings("settings-recording-rejected-key", recording),
            settings("settings-recording", waiting),
            settings("settings-error", broken),
        ]
    }

    private static func settings(_ name: String, _ model: SettingsModel) -> SampleScreen {
        SampleScreen(
            name: name, view: AnyView(SettingsView(model: model, capturesKeys: false, limitsHeight: false)))
    }

    /// kVK_ANSI_Equal, a key GHLive does not offer.
    private static let unsupportedKeyCode: UInt16 = 0x18
}
