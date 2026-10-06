import AppKit
import SwiftUI
import Testing

@testable import GHLiveAppKit

struct ScreenFitTests {
    private let screen: CGFloat = 900
    private let reserved: CGFloat = 90

    @Test func contentThatFitsIsNotCapped() {
        #expect(ScreenFit.scrollHeight(content: 300, screen: screen, reserved: reserved) == 300)
    }

    @Test func tallContentIsCappedBelowTheScreenMinusChromeAndFooter() {
        let height = ScreenFit.scrollHeight(content: 2000, screen: screen, reserved: reserved)
        #expect(height == screen - ScreenFit.windowChrome - reserved)
    }

    @Test func aTinyScreenStillLeavesARoomToScroll() {
        let height = ScreenFit.scrollHeight(content: 2000, screen: 100, reserved: reserved)
        #expect(height == ScreenFit.minimumScrollHeight)
    }
}

@MainActor
struct ScrollsWithinScreenHostingTests {
    private let screen: CGFloat = 700
    private let reserved: CGFloat = 100
    private let settleRounds = 20
    private let settleStep: Duration = .milliseconds(20)

    private let contentWidth: CGFloat = 200

    private func hosted(contentHeight: CGFloat) async throws -> NSHostingView<ScrollsWithinScreen<some View>> {
        let root = ScrollsWithinScreen(reservedHeight: reserved, screenHeight: screen) {
            Color.orange.frame(width: contentWidth, height: contentHeight)
        }
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: contentWidth, height: 100), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.contentView = hosting
        for _ in 0..<settleRounds {
            try await Task.sleep(for: settleStep)
            hosting.layoutSubtreeIfNeeded()
        }
        return hosting
    }

    private func hostedHeight(contentHeight: CGFloat) async throws -> CGFloat {
        try await hosted(contentHeight: contentHeight).fittingSize.height
    }

    private func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
    }

    @Test func theScrollAreaLeavesRoomForShadowsWithoutChangingTheLayout() async throws {
        let hosting = try await hosted(contentHeight: 3000)
        let scroll = try #require(scrollView(in: hosting))
        let footprint = hosting.fittingSize
        #expect(scroll.frame.width - footprint.width == 2 * ScreenFit.shadowAllowance)
        #expect(scroll.frame.height - footprint.height == 2 * ScreenFit.shadowAllowance)
        #expect(footprint.height == screen - ScreenFit.windowChrome - reserved)
    }

    @Test func aTallViewIsCappedToTheScreen() async throws {
        let height = try await hostedHeight(contentHeight: 3000)
        #expect(height == screen - ScreenFit.windowChrome - reserved)
    }

    @Test func aShortViewKeepsItsOwnHeight() async throws {
        let height = try await hostedHeight(contentHeight: 150)
        #expect(height == 150)
    }
}
