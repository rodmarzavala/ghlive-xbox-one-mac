import Foundation
import GHLiveCore
import Testing

@testable import GHLiveAppKit

struct LaunchOptionsTests {
    @Test func noArgumentsRunsTheApp() {
        #expect(LaunchOptions.parse([]) == .runApp)
    }

    @Test func exportFlagTakesADirectory() {
        #expect(
            LaunchOptions.parse(["--export-screenshots", "/tmp/out"])
                == .exportScreenshots(directory: URL(fileURLWithPath: "/tmp/out", isDirectory: true)))
    }

    @Test func exportFlagWithoutADirectoryIsInvalid() {
        guard case .invalid = LaunchOptions.parse(["--export-screenshots"]) else {
            Issue.record("expected invalid")
            return
        }
    }
}

@MainActor
struct InitialWindowTests {
    private let dryRun = [AppModel.dryRunVariable: "1"]

    @Test func opensTheNamedWindowInDryRun() {
        for window in AppWindow.allCases {
            let opened = LaunchOptions.initialWindow(
                arguments: ["--open-window", window.rawValue], environment: dryRun)
            #expect(opened == window)
        }
    }

    @Test func isIgnoredOutsideDryRun() {
        #expect(LaunchOptions.initialWindow(arguments: ["--open-window", "settings"], environment: [:]) == nil)
        #expect(
            LaunchOptions.initialWindow(
                arguments: ["--open-window", "settings"], environment: [AppModel.dryRunVariable: "0"]) == nil)
    }

    @Test func ignoresMissingOrUnknownValues() {
        #expect(LaunchOptions.initialWindow(arguments: [], environment: dryRun) == nil)
        #expect(LaunchOptions.initialWindow(arguments: ["--open-window"], environment: dryRun) == nil)
        #expect(LaunchOptions.initialWindow(arguments: ["--open-window", "about"], environment: dryRun) == nil)
    }
}

struct VersionTests {
    @Test func versionFileMatchesTheCode() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("VERSION"), encoding: .utf8)
        #expect(text.trimmingCharacters(in: .whitespacesAndNewlines) == GHLiveInfo.version)
    }
}

@MainActor
struct ScreenshotExporterTests {
    @Test func writesLightAndDarkPNGsForEveryScreen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghlive-screenshots-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = try ScreenshotExporter.export(to: directory)
        #expect(files.count == SampleStates.screens().count * 2)
        #expect(files.contains { $0.lastPathComponent == "monitor-active-dark.png" })
        #expect(files.contains { $0.lastPathComponent == "settings-light.png" })
        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        for file in files {
            let data = try Data(contentsOf: file)
            #expect(data.count > 1000)
            #expect([UInt8](data.prefix(4)) == pngSignature)
        }
    }
}
