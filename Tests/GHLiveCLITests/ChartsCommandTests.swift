import ChartConversion
import Foundation
import Testing

@testable import GHLiveCLI

@Suite("charts add-ghl")
struct ChartsCommandTests {
    private static let chart = """
        [Song]
        {
          Resolution = 192
        }
        [ExpertSingle]
        {
          0 = N 0 0
          192 = N 3 0
        }
        """

    private final class Output: @unchecked Sendable {
        private(set) var lines: [String] = []
        func add(_ line: String) { lines.append(line) }
    }

    private func makeFolder(files: [String: Data]) throws -> URL {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("ghlive-cli-\(UUID().uuidString)")
        let root = parent.appendingPathComponent("Songs")
        for (path, data) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func run(_ folder: URL, dryRun: Bool, output: Output, errors: Output) -> Int32 {
        addGHLTracks(
            AddGHLOptions(folder: folder.path, dryRun: dryRun), output: output.add, errorOutput: errors.add)
    }

    @Test("prints a line per song and a summary, and exits 0")
    func convertsAndSummarises() throws {
        let folder = try makeFolder(files: ["A/notes.chart": Data(Self.chart.utf8), "B/song.sng": Data("x".utf8)])
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let output = Output()
        let code = run(folder, dryRun: false, output: output, errors: Output())
        #expect(code == ExitCode.success)
        #expect(output.lines.contains { $0.hasPrefix("converted: A/notes.chart") })
        #expect(output.lines.contains("skipped: B/song.sng (.sng is not supported yet)"))
        #expect(output.lines.contains("1 converted, 1 skipped, 0 failed"))
        #expect(output.lines.contains { $0.contains("backup") && $0.contains("Songs - backup ") })
        #expect(output.lines.contains { $0.localizedCaseInsensitiveContains("rescan") })
        let converted = try String(contentsOf: folder.appendingPathComponent("A/notes.chart"), encoding: .utf8)
        #expect(converted.contains("[ExpertGHLGuitar]"))
    }

    @Test("a dry run says so, changes nothing and creates no backup")
    func dryRun() throws {
        let folder = try makeFolder(files: ["A/notes.chart": Data(Self.chart.utf8)])
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let output = Output()
        #expect(run(folder, dryRun: true, output: output, errors: Output()) == ExitCode.success)
        #expect(output.lines.contains { $0.hasPrefix("would convert: A/notes.chart") })
        #expect(output.lines.contains("1 would be converted, 0 skipped, 0 failed"))
        #expect(!output.lines.contains { $0.contains("backup") })
        let after = try String(contentsOf: folder.appendingPathComponent("A/notes.chart"), encoding: .utf8)
        #expect(after == Self.chart)
        let siblings = try FileManager.default.contentsOfDirectory(atPath: folder.deletingLastPathComponent().path)
        #expect(siblings == ["Songs"])
    }

    @Test("exits non-zero when a song fails")
    func failureExitCode() throws {
        let folder = try makeFolder(files: ["A/notes.mid": Data("garbage".utf8)])
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let output = Output()
        #expect(run(folder, dryRun: false, output: output, errors: Output()) == ExitCode.failure)
        #expect(output.lines.contains { $0.hasPrefix("failed: A/notes.mid") })
        #expect(output.lines.contains("0 converted, 0 skipped, 1 failed"))
    }

    @Test("a folder that does not exist is an error on stderr and a non-zero exit")
    func missingFolder() {
        let errors = Output()
        let missing = URL(fileURLWithPath: "/nonexistent/ghlive-songs")
        #expect(run(missing, dryRun: false, output: Output(), errors: errors) == ExitCode.failure)
        #expect(errors.lines == ["ghlive: '/nonexistent/ghlive-songs' is not a folder"])
    }
}
