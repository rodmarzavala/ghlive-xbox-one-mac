import AppKit
import SwiftUI

/// A `.window`-style MenuBarExtra panel grows with its content but never shrinks back, so a card
/// that disappears while the menu is open (e.g. after granting Accessibility) leaves blank space.
enum MenuWindowFit {
    private static let tolerance: CGFloat = 1

    /// The panel frame for `contentHeight`, keeping the top edge pinned under the menu bar icon,
    /// or nil when no resize is needed.
    static func frame(fitting contentHeight: CGFloat, in current: CGRect) -> CGRect? {
        guard contentHeight > 0, abs(current.height - contentHeight) >= tolerance else { return nil }
        return CGRect(
            x: current.minX,
            y: current.maxY - contentHeight,
            width: current.width,
            height: contentHeight
        )
    }
}

struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    // Last-wins would keep the default 0 from sibling views; the tallest report is the content's.
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Hands back the window hosting this view once it is attached to one.
private struct HostingWindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { WindowReportingView(onWindow: onWindow) }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowReportingView: NSView {
        let onWindow: (NSWindow) -> Void

        init(onWindow: @escaping (NSWindow) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow(window) }
        }
    }
}

@MainActor
private final class WindowBox: ObservableObject {
    weak var window: NSWindow?

    func fit(to contentHeight: CGFloat) {
        guard let window else { return }
        let currentContent = window.contentRect(forFrameRect: window.frame)
        guard let fittedContent = MenuWindowFit.frame(fitting: contentHeight, in: currentContent) else { return }
        window.setFrame(window.frameRect(forContentRect: fittedContent), display: true)
    }
}

private struct FitsMenuWindowToContent: ViewModifier {
    // @StateObject rather than @State: the Command Line Tools ship without the SwiftUI macros plugin.
    @StateObject private var box = WindowBox()

    func body(content: Content) -> some View {
        let box = box
        return
            content
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                }
            )
            .background(HostingWindowReader { box.window = $0 })
            // Older SDKs declare this action @Sendable; it always runs on the main thread.
            .onPreferenceChange(ContentHeightKey.self) { height in
                MainActor.assumeIsolated { box.fit(to: height) }
            }
    }
}

extension View {
    /// Keeps a MenuBarExtra window exactly as tall as this view, shrinking as well as growing.
    public func fitsMenuWindowToContent() -> some View {
        modifier(FitsMenuWindowToContent())
    }
}
