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

    private func hostedHeight(contentHeight: CGFloat) async throws -> CGFloat {
        let root = ScrollsWithinScreen(reservedHeight: reserved, screenHeight: screen) {
            Color.orange.frame(width: 200, height: contentHeight)
        }
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.contentView = hosting
        for _ in 0..<settleRounds {
            try await Task.sleep(for: settleStep)
            hosting.layoutSubtreeIfNeeded()
        }
        return hosting.fittingSize.height
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
