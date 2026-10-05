import AppKit
import GHLiveAppKit
import GHLiveCore
import SwiftUI

private enum WindowID {
    static let settings = "settings"
    static let monitor = "monitor"
}

/// Quitting by any route (menu, Cmd-Q, logout, SIGTERM) waits until every key is released and the dongle is
/// closed, within the model's timeout.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel.live()
    private var signalObserver: TerminationSignalObserver?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        // Not NSApp.terminate: its .terminateLater wait spins a nested run loop inside this main-queue block,
        // and the serial main queue then never runs the shutdown tasks, so the app would hang. terminate(reply:)
        // releases the keys at once and gives up after its timeout, which is the watchdog.
        signalObserver = TerminationSignalObserver { [model] in model.terminate { exit(0) } }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.terminate { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}

struct GHLiveApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            LiveMenu(model: delegate.model)
        } label: {
            LiveMenuIcon(model: delegate.model)
        }
        .menuBarExtraStyle(.window)

        Window("GHLive Settings", id: WindowID.settings) {
            SettingsView(model: delegate.model.settings)
        }
        .windowResizability(.contentSize)

        Window("GHLive Input Monitor", id: WindowID.monitor) {
            LiveMonitor(model: delegate.model, driver: delegate.model.driver)
        }
        .windowResizability(.contentSize)
    }
}

private struct LiveMenuIcon: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let status = model.menu.status
        Image(systemName: status.symbolName)
            .accessibilityLabel("GHLive: \(status.headline)")
    }
}

/// Observes the driver as well as the model: guitar reports redraw the monitor but never the menu.
private struct LiveMonitor: View {
    @ObservedObject var model: AppModel
    @ObservedObject var driver: GuitarDriver

    var body: some View {
        MonitorView(monitor: model.monitor)
    }
}

private struct LiveMenu: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuContentView(menu: model.menu, actions: actions)
            .fitsMenuWindowToContent()
    }

    private var actions: MenuActions {
        MenuActions(
            grantAccessibility: model.requestAccessibility,
            togglePause: model.togglePause,
            openSettings: { show(WindowID.settings) },
            openMonitor: { show(WindowID.monitor) },
            setLaunchAtLogin: model.setLaunchAtLogin,
            openLoginItems: model.openLoginItemsSettings,
            openKeymapFolder: model.openKeymapFolder,
            showAbout: showAbout,
            quit: { NSApp.terminate(nil) }
        )
    }

    // An accessory app is never frontmost on its own, so its windows would open behind other apps.
    private func show(_ id: String) {
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "GHLive",
            .applicationVersion: GHLiveInfo.version,
            .version: GHLiveInfo.version,
        ])
    }
}
