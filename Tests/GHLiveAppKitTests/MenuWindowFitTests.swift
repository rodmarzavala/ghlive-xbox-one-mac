import CoreGraphics
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
    }

    @Test func anEmptyMeasurementIsIgnored() {
        #expect(MenuWindowFit.frame(fitting: 0, in: tallPanel) == nil)
    }
}
