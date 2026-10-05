import AppKit
import GHLiveAppKit
import GHLiveCore
import SwiftUI

private enum WindowID {
    static let settings = "settings"
    static let monitor = "monitor"
}

/// Quitting by any route (menu, Cmd-Q, logout) waits until every key is released and the dongle is closed.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel.live()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await model.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
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
            LiveMonitor(model: delegate.model)
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

private struct LiveMonitor: View {
    @ObservedObject var model: AppModel

    var body: some View {
        MonitorView(monitor: model.monitor)
    }
}

private struct LiveMenu: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuContentView(menu: model.menu, actions: actions)
    }

    private var actions: MenuActions {
        MenuActions(
            grantAccessibility: model.requestAccessibility,
            togglePause: model.togglePause,
            openSettings: { show(WindowID.settings) },
            openMonitor: { show(WindowID.monitor) },
            setLaunchAtLogin: model.setLaunchAtLogin,
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
