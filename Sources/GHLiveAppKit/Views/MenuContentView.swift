import SwiftUI

/// The actions behind the menu rows. Screenshots pass no-ops.
public struct MenuActions {
    public var grantAccessibility: () -> Void
    public var togglePause: () -> Void
    public var openSettings: () -> Void
    public var openMonitor: () -> Void
    public var setLaunchAtLogin: (Bool) -> Void
    public var openKeymapFolder: () -> Void
    public var showAbout: () -> Void
    public var quit: () -> Void

    public init(
        grantAccessibility: @escaping () -> Void = {},
        togglePause: @escaping () -> Void = {},
        openSettings: @escaping () -> Void = {},
        openMonitor: @escaping () -> Void = {},
        setLaunchAtLogin: @escaping (Bool) -> Void = { _ in },
        openKeymapFolder: @escaping () -> Void = {},
        showAbout: @escaping () -> Void = {},
        quit: @escaping () -> Void = {}
    ) {
        self.grantAccessibility = grantAccessibility
        self.togglePause = togglePause
        self.openSettings = openSettings
        self.openMonitor = openMonitor
        self.setLaunchAtLogin = setLaunchAtLogin
        self.openKeymapFolder = openKeymapFolder
        self.showAbout = showAbout
        self.quit = quit
    }
}

public struct MenuContentView: View {
    public static let width: CGFloat = 320

    private let menu: MenuPresentation
    private let actions: MenuActions

    public init(menu: MenuPresentation, actions: MenuActions) {
        self.menu = menu
        self.actions = actions
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusHeader
            if menu.needsAccessibility { accessibilityCard }
            if let problem = menu.keymapProblem { warning(problem) }
            VStack(alignment: .leading, spacing: 0) {
                MenuRow(title: menu.pauseTitle, symbol: menu.isPaused ? "play.fill" : "pause.fill") {
                    actions.togglePause()
                }
                Divider().padding(.vertical, 4)
                MenuRow(title: "Settings\u{2026}", symbol: "slider.horizontal.3", action: actions.openSettings)
                MenuRow(title: "Input Monitor\u{2026}", symbol: "waveform.path.ecg", action: actions.openMonitor)
                MenuRow(
                    title: "Launch at Login",
                    symbol: menu.launchesAtLogin ? "checkmark.square.fill" : "square",
                    isSelected: menu.launchesAtLogin
                ) { actions.setLaunchAtLogin(!menu.launchesAtLogin) }
                if let problem = menu.launchAtLoginProblem { warning(problem) }
                MenuRow(title: "Open keymap folder", symbol: "folder", action: actions.openKeymapFolder)
                Divider().padding(.vertical, 4)
                MenuRow(title: "About GHLive", symbol: "info.circle", action: actions.showAbout)
                MenuRow(title: "Quit GHLive", symbol: "power", action: actions.quit)
            }
        }
        .padding(12)
        .frame(width: Self.width)
    }

    private var statusHeader: some View {
        HStack(spacing: 10) {
            StatusBadge(status: menu.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(menu.status.headline)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = menu.status.detail {
                    Text(detail).font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [menu.status.headline, menu.status.detail].compactMap { $0 }.joined(separator: ". ")
        )
    }

    private var accessibilityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("Allow GHLive to press keys", systemImage: "hand.raised.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.orange)
                Text(
                    "GHLive sends key presses to Clone Hero, and macOS only allows that after you grant "
                        + "Accessibility access."
                )
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Button("Grant Accessibility access\u{2026}", action: actions.grantAccessibility)
                    .buttonStyle(PillButtonStyle())
                    .accessibilityHint("Opens System Settings, Privacy and Security, Accessibility")
            }
        }
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundColor(.red)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
    }
}

private struct MenuRow: View {
    let title: String
    let symbol: String
    var isSelected = false
    let action: () -> Void

    // A StateObject rather than @State: `@State` is a macro in the newest SDK and the Command Line Tools
    // ship no SwiftUI macro plugin, so it would not compile there.
    @StateObject private var hover = HoverState()

    private static let hoverOpacity = 0.1
    private static let symbolWidth: CGFloat = 20

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .frame(width: Self.symbolWidth)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                Text(title)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(hover.isHovering ? Self.hoverOpacity : 0))
            )
        }
        .buttonStyle(.plain)
        .onHover { hover.isHovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

@MainActor
private final class HoverState: ObservableObject {
    @Published var isHovering = false
}
