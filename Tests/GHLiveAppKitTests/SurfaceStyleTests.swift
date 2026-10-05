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
