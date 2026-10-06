import AppKit
import SwiftUI

/// Windows that size themselves to their content would run off a small display, hiding the controls at the
/// bottom. The scrolling part is capped to the screen; what follows it stays in view.
enum ScreenFit {
    /// What the window adds around the scroll view and the reserved part: the title bar and the 20 pt padding
    /// above and below. `visibleFrame` already excludes the menu bar and the Dock.
    static let titleBarHeight: CGFloat = 28
    static let contentPadding: CGFloat = 20
    static let windowChrome: CGFloat = titleBarHeight + 2 * contentPadding
    static let minimumScrollHeight: CGFloat = 240
    /// A scroll view clips what it holds, including the shadows cards cast past their edges, so the scrolled
    /// content gets this much room inside it, given back outside so the layout does not move.
    static let shadowAllowance: CGFloat = 16
    /// Used when no screen is known, such as in a headless render.
    static let fallbackScreenHeight: CGFloat = 800

    /// `reserved` is the height of what stays outside the scroll view, such as a footer.
    static func scrollHeight(content: CGFloat, screen: CGFloat, reserved: CGFloat) -> CGFloat {
        min(content, max(minimumScrollHeight, screen - windowChrome - reserved))
    }

    @MainActor
    static var screenHeight: CGFloat {
        NSScreen.main?.visibleFrame.height ?? fallbackScreenHeight
    }
}

@MainActor
private final class MeasuredHeight: ObservableObject {
    @Published var value: CGFloat = 0
}

/// Scrolls its content once it is taller than the screen allows, and is exactly as tall as the content otherwise.
struct ScrollsWithinScreen<Content: View>: View {
    private let isEnabled: Bool
    private let reservedHeight: CGFloat
    private let screenHeight: CGFloat
    private let content: Content

    // @StateObject rather than @State: the Command Line Tools ship without the SwiftUI macros plugin.
    @StateObject private var measured = MeasuredHeight()

    /// `isEnabled` is off for screenshots, where `ImageRenderer` cannot draw a scroll view.
    init(
        isEnabled: Bool = true, reservedHeight: CGFloat, screenHeight: CGFloat = ScreenFit.screenHeight,
        @ViewBuilder content: () -> Content
    ) {
        self.isEnabled = isEnabled
        self.reservedHeight = reservedHeight
        self.screenHeight = screenHeight
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if isEnabled {
            ScrollView(.vertical) {
                content
                    .padding(ScreenFit.shadowAllowance)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                        })
            }
            // Its own background would show as a slightly lighter box against the window.
            .scrollContentBackground(.hidden)
            .frame(height: scrollHeight)
            .padding(-ScreenFit.shadowAllowance)
            .onPreferenceChange(ContentHeightKey.self) { height in
                MainActor.assumeIsolated { measured.value = height }
            }
        } else {
            content
        }
    }

    private var scrollHeight: CGFloat? {
        guard measured.value > 0 else { return nil }
        // The allowance sits outside the window's footprint (negative padding), so the cap may grow by it.
        let allowance = 2 * ScreenFit.shadowAllowance
        return ScreenFit.scrollHeight(
            content: measured.value, screen: screenHeight + allowance, reserved: reservedHeight)
    }
}
