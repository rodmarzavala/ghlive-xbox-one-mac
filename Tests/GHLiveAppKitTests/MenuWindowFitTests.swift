import AppKit
import SwiftUI
import Testing

@testable import GHLiveAppKit

struct MenuWindowFitTests {
    private let tallPanel = CGRect(x: 100, y: 400, width: 320, height: 500)

    @Test func shrinkingKeepsTheTopEdgeUnderTheMenuBarIcon() {
        let fitted = MenuWindowFit.frame(fitting: 380, in: tallPanel)
        #expect(fitted?.height == 380)
        #expect(fitted?.maxY == tallPanel.maxY)
        #expect(fitted?.minX == tallPanel.minX)
        #expect(fitted?.width == tallPanel.width)
    }

    @Test func growingAlsoKeepsTheTopEdge() {
        let fitted = MenuWindowFit.frame(fitting: 560, in: tallPanel)
        #expect(fitted?.height == 560)
        #expect(fitted?.maxY == tallPanel.maxY)
    }

    @Test func aMatchingHeightNeedsNoResize() {
        #expect(MenuWindowFit.frame(fitting: 500, in: tallPanel) == nil)
        #expect(MenuWindowFit.frame(fitting: 500.4, in: tallPanel) == nil)
        #expect(MenuWindowFit.frame(fitting: 501, in: tallPanel) != nil)
    }

    @Test func anEmptyMeasurementIsIgnored() {
        #expect(MenuWindowFit.frame(fitting: 0, in: tallPanel) == nil)
    }
}

@MainActor
private final class CardToggle: ObservableObject {
    @Published var showsCard = true
}

private struct ProbeMenu: View {
    @ObservedObject var toggle: CardToggle

    var body: some View {
        VStack(spacing: 0) {
            Text("Status")
            if toggle.showsCard { Color.orange.frame(height: 120) }
            Text("Quit")
        }
        .padding(12)
        .frame(width: 300)
        .fitsMenuWindowToContent()
    }
}

@MainActor
struct MenuWindowFitHostingTests {
    private let settleRounds = 20
    private let settleStep: Duration = .milliseconds(20)

    @Test func thePanelShrinksWhenACardDisappears() async throws {
        let toggle = CardToggle()
        let hosting = NSHostingView(rootView: ProbeMenu(toggle: toggle))
        hosting.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 300, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let top = window.frame.maxY

        toggle.showsCard = false
        for _ in 0..<settleRounds {
            try await Task.sleep(for: settleStep)
            hosting.layoutSubtreeIfNeeded()
        }

        #expect(window.frame.height < 100, "frame \(window.frame)")
        #expect(window.frame.maxY == top)
    }
}
