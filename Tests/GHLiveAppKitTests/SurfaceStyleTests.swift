import SwiftUI
import Testing

@testable import GHLiveAppKit

struct SurfaceStyleTests {
    @Test(arguments: [26, 27, 30])
    func glassFromMacOS26OnAGlassSDK(major: Int) {
        #expect(SurfaceStyle.resolve(osMajorVersion: major, sdkHasGlass: true) == .glass)
    }

    @Test(arguments: [13, 14, 15])
    func classicBeforeMacOS26(major: Int) {
        #expect(SurfaceStyle.resolve(osMajorVersion: major, sdkHasGlass: true) == .classic)
    }

    @Test(arguments: [13, 15, 26, 27])
    func classicWhenBuiltWithoutTheGlassSDK(major: Int) {
        #expect(SurfaceStyle.resolve(osMajorVersion: major, sdkHasGlass: false) == .classic)
    }

    @Test func glassStartsAtMacOS26() {
        #expect(SurfaceStyle.firstGlassMajorVersion == 26)
    }
}

@MainActor
struct ScreenshotStyleTests {
    private final class Seen {
        var style: SurfaceStyle?
        var scheme: ColorScheme?
    }

    private struct Probe: View {
        let seen: Seen
        @Environment(\.surfaceStyle) private var style
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            seen.style = style
            seen.scheme = scheme
            return Color.clear.frame(width: 1, height: 1)
        }
    }

    @Test func screenshotsAreRenderedWithTheClassicLook() {
        for appearance in ScreenshotExporter.appearances {
            let seen = Seen()
            let renderer = ImageRenderer(content: ScreenshotExporter.styled(Probe(seen: seen), appearance: appearance))
            _ = renderer.nsImage
            #expect(seen.style == .classic)
            #expect(seen.scheme == appearance.scheme)
        }
    }
}
