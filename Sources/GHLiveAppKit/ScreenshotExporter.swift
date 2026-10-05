import AppKit
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

    private struct Appearance {
        let name: String
        let scheme: ColorScheme
        let background: Color
    }

    private static let appearances = [
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

    private static func writePNG(of view: AnyView, appearance: Appearance, to url: URL) throws {
        let content =
            view
            .background(appearance.background)
            .environment(\.colorScheme, appearance.scheme)
            .environment(\.surfaceStyle, .classic)
        let renderer = ImageRenderer(content: content)
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
        menuScreens() + monitorScreens() + settingsScreens()
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
        ]
    }

    private static func monitor(_ name: String, status: DriverStatus, snapshot: GuitarSnapshot?) -> SampleScreen {
        let presentation = MonitorPresentation(
            status: StatusPresentation(status: status, isPaused: false),
            snapshot: snapshot, thresholds: Keymap.default.thresholds, bindings: Keymap.default.bindings,
            isPaused: false)
        return SampleScreen(name: name, view: AnyView(MonitorView(monitor: presentation)))
    }

    private static func snapshot(
        buttons: Set<GuitarButton>, dpad: Set<DpadDirection>, whammy: Double, tilt: UInt8, thresholds: Thresholds
    ) -> GuitarSnapshot {
        let state = GuitarState(pressedButtons: buttons, dpad: dpad, whammy: whammy, tilt: tilt)
        var detector = ControlDetector(thresholds: thresholds)
        return GuitarSnapshot(state: state, controls: detector.detect(state))
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
        return [
            SampleScreen(name: "settings", view: AnyView(SettingsView(model: saved, capturesKeys: false))),
            SampleScreen(
                name: "settings-recording-rejected-key",
                view: AnyView(SettingsView(model: recording, capturesKeys: false))),
            SampleScreen(
                name: "settings-recording", view: AnyView(SettingsView(model: waiting, capturesKeys: false))),
            SampleScreen(name: "settings-error", view: AnyView(SettingsView(model: broken, capturesKeys: false))),
        ]
    }

    /// kVK_ANSI_Equal, a key GHLive does not offer.
    private static let unsupportedKeyCode: UInt16 = 0x18
}
