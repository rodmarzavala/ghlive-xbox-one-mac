import Foundation
import Testing

@testable import ChartConversion

/// A throwaway songs folder under the system temp directory, removed when the value goes away.
final class SyntheticLibrary: @unchecked Sendable {
    let parent: URL
    let root: URL
    static let folderName = "Synthetic Songs"

    init() throws {
        parent = FileManager.default.temporaryDirectory.appendingPathComponent("ghlive-tests-\(UUID().uuidString)")
        root = parent.appendingPathComponent(Self.folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: parent) }

    @discardableResult
    func write(_ data: Data, _ relativePath: String) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    func read(_ relativePath: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(relativePath))
    }

    func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(relativePath).path)
    }

    /// Every file under the root, relative path to bytes.
    func snapshot() throws -> [String: Data] { try Self.snapshot(of: root) }

    static func snapshot(of folder: URL) throws -> [String: Data] {
        var files: [String: Data] = [:]
        let keys: [URLResourceKey] = [.isRegularFileKey]
        let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys)
        while let url = walker?.nextObject() as? URL {
            guard try url.resourceValues(forKeys: Set(keys)).isRegularFile == true else { continue }
            files[String(url.path.dropFirst(folder.path.count + 1))] = try Data(contentsOf: url)
        }
        return files
    }

    /// The folders next to the root whose name starts with the root's name and " - backup ".
    func backupFolders() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("\(Self.folderName) - backup ") }
    }
}

enum SyntheticSongs {
    static let fiveFretChart = Data(SyntheticChart.text(lines: SyntheticChart.notes([(0, 0), (192, 3)])).utf8)

    static let fiveFretMIDI: Data = {
        typealias M = SyntheticMIDI
        return M.file([
            M.track(M.meta(M.tempoType, [7, 0xA1, 0x20]), M.endOfTrack()),
            M.track(M.name("PART GUITAR"), M.note(96, delta: 10), M.note(40, delta: 5), M.endOfTrack()),
        ])
    }()

    static let ini = Data("[song]\nname = Synthetic\ndiff_guitar = 4\n".utf8)
}

@Suite("Song library conversion")
struct SongLibraryConverterTests {
    private static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeConverter(
        store: any ChartFileStore = DiskChartFileStore(),
        converters: [ChartFileFormat: any ChartFormatConverter]? = nil
    ) -> SongLibraryConverter {
        SongLibraryConverter(
            store: store, converters: converters ?? SongLibraryConverter.defaultConverters,
            now: { Self.fixedDate }, timeZone: TimeZone(identifier: "UTC")!)
    }

    private func outcomes(_ report: ConversionReport) -> [String: SongOutcome] {
        Dictionary(uniqueKeysWithValues: report.results.map { ($0.path, $0.outcome) })
    }

    private func isConverted(_ outcome: SongOutcome?) -> Bool {
        if case .converted = outcome { return true }
        return false
    }

    @Test("a folder of songs and nested packs is walked; both formats are converted")
    func walksPacks() throws {
        let library = try SyntheticLibrary()
        try library.write(SyntheticSongs.fiveFretChart, "Song A/notes.chart")
        try library.write(SyntheticSongs.fiveFretMIDI, "Pack/Song B/notes.mid")
        try library.write(SyntheticSongs.fiveFretChart, "Pack/Sub Pack/Song C/notes.chart")
        let report = try makeConverter().convert(folder: library.root, dryRun: false)
        let found = outcomes(report)
        #expect(
            found.keys.sorted() == ["Pack/Song B/notes.mid", "Pack/Sub Pack/Song C/notes.chart", "Song A/notes.chart"])
        #expect(found.values.allSatisfy(isConverted))
        #expect(String(decoding: try library.read("Song A/notes.chart"), as: UTF8.self).contains("[ExpertGHLGuitar]"))
        #expect(report.convertedCount == 3)
        #expect(!report.hasFailures)
    }

    @Test("a .sng song is reported as unsupported and left alone")
    func sngSkipped() throws {
        let library = try SyntheticLibrary()
        let bytes = Data("SNGPKG".utf8)
        try library.write(bytes, "Song/song.sng")
        let report = try makeConverter().convert(folder: library.root, dryRun: false)
        #expect(outcomes(report) == ["Song/song.sng": .unsupportedFormat])
        #expect(try library.read("Song/song.sng") == bytes)
        #expect(try library.backupFolders().isEmpty)
    }

    @Test("a backup of every changed file is made outside the songs folder, with the same structure")
    func backupOutsideRoot() throws {
        let library = try SyntheticLibrary()
        try library.write(SyntheticSongs.fiveFretChart, "Pack/Song A/notes.chart")
        try library.write(SyntheticSongs.ini, "Pack/Song A/song.ini")
        try library.write(SyntheticSongs.fiveFretMIDI, "Song B/notes.mid")
        let report = try makeConverter().convert(folder: library.root, dryRun: false)
        let backup = try #require(try library.backupFolders().first)
        #expect(backup.lastPathComponent == "Synthetic Songs - backup 2023-11-14 221320")
        #expect(report.backupFolder?.standardizedFileURL == backup.standardizedFileURL)
        let saved = try SyntheticLibrary.snapshot(of: backup)
        #expect(
            saved == [
                "Pack/Song A/notes.chart": SyntheticSongs.fiveFretChart, "Pack/Song A/song.ini": SyntheticSongs.ini,
                "Song B/notes.mid": SyntheticSongs.fiveFretMIDI,
            ])
        #expect(try library.snapshot().keys.allSatisfy { !$0.contains("backup") })
    }

    @Test("a dry run reports the changes and writes nothing, not even a backup")
    func dryRun() throws {
        let library = try SyntheticLibrary()
        try library.write(SyntheticSongs.fiveFretChart, "A/notes.chart")
        try library.write(SyntheticSongs.fiveFretMIDI, "B/notes.mid")
        try library.write(SyntheticSongs.ini, "B/song.ini")
        let before = try library.snapshot()
        let report = try makeConverter().convert(folder: library.root, dryRun: true)
        #expect(report.isDryRun)
        #expect(report.convertedCount == 2)
        #expect(try library.snapshot() == before)
        #expect(try library.backupFolders().isEmpty)
        #expect(report.backupFolder == nil)
        #expect(
            outcomes(report)["B/notes.mid"]
                == .converted(addedTracks: ["PART GUITAR GHL"], notes: 1, songIni: .added(value: "4")))
    }

    @Test("a second run adds nothing and makes no backup")
    func idempotent() throws {
        let library = try SyntheticLibrary()
        try library.write(SyntheticSongs.fiveFretChart, "A/notes.chart")
        try library.write(SyntheticSongs.fiveFretMIDI, "B/notes.mid")
        _ = try makeConverter().convert(folder: library.root, dryRun: false)
        let afterFirst = try library.snapshot()
        let backups = try library.backupFolders().count
        let report = try makeConverter().convert(folder: library.root, dryRun: false)
        #expect(outcomes(report).values.allSatisfy { $0 == .alreadyHasSixFret })
        #expect(try library.snapshot() == afterFirst)
        #expect(try library.backupFolders().count == backups)
    }

    @Test("a song with no 5-fret guitar is reported as such")
    func noFiveFret() throws {
        let library = try SyntheticLibrary()
        let drumsOnly = Data(
            (SyntheticChart.preamble + [SyntheticChart.section("ExpertDrums", [])]).joined(separator: "\n").utf8)
        try library.write(drumsOnly, "A/notes.chart")
        #expect(
            outcomes(try makeConverter().convert(folder: library.root, dryRun: false)) == [
                "A/notes.chart": .noFiveFretTrack
            ])
    }

    @Test("an unreadable file fails that song and the others are still converted")
    func failureIsolated() throws {
        let library = try SyntheticLibrary()
        try library.write(Data("not a midi".utf8), "A/notes.mid")
        try library.write(SyntheticSongs.fiveFretChart, "B/notes.chart")
        let report = try makeConverter().convert(folder: library.root, dryRun: false)
        guard case .failed = outcomes(report)["A/notes.mid"] else {
            Issue.record("expected a failure")
            return
        }
        #expect(isConverted(outcomes(report)["B/notes.chart"]))
        #expect(report.hasFailures)
        #expect(report.failedCount == 1)
        #expect(try library.read("A/notes.mid") == Data("not a midi".utf8))
    }

    @Test("results are delivered one by one, in a stable order")
    func progress() throws {
        let library = try SyntheticLibrary()
        try library.write(SyntheticSongs.fiveFretChart, "B/notes.chart")
        try library.write(SyntheticSongs.fiveFretChart, "A/notes.chart")
        let seen = Seen()
        let report = try makeConverter().convert(folder: library.root, dryRun: true) { seen.add($0.path) }
        #expect(seen.paths == ["A/notes.chart", "B/notes.chart"])
        #expect(report.results.map(\.path) == seen.paths)
    }

    @Test("something that is not a folder is an error")
    func notAFolder() throws {
        let library = try SyntheticLibrary()
        let file = try library.write(Data(), "plain.txt")
        #expect(throws: LibraryError.notAFolder(file.path)) { try makeConverter().convert(folder: file, dryRun: false) }
        let missing = library.root.appendingPathComponent("nope")
        #expect(throws: LibraryError.notAFolder(missing.path)) {
            try makeConverter().convert(folder: missing, dryRun: false)
        }
    }

    // MARK: Safety

    /// Passes conversion through but reports a verification failure, as a damaged write would.
    private struct FailingVerifier: ChartFormatConverter {
        let inner: any ChartFormatConverter
        func convert(_ data: Data) throws -> ConversionAttempt { try inner.convert(data) }
        func verify(converted: Data, original: Data) throws -> Int {
            throw ConversionError.verificationFailed("injected")
        }
    }

    struct FailingStore: ChartFileStore {
        enum Step { case backup, write, replace }
        let failing: Step
        let inner = DiskChartFileStore()
        struct Injected: Error {}
        func read(_ url: URL) throws -> Data { try inner.read(url) }
        func exists(_ url: URL) -> Bool { inner.exists(url) }
        func backUp(_ url: URL, to destination: URL) throws {
            if failing == .backup { throw Injected() }
            try inner.backUp(url, to: destination)
        }
        func writeTemporary(_ data: Data, besides url: URL) throws -> URL {
            if failing == .write { throw Injected() }
            return try inner.writeTemporary(data, besides: url)
        }
        func replace(_ url: URL, withTemporary temporary: URL) throws {
            if failing == .replace { throw Injected() }
            try inner.replace(url, withTemporary: temporary)
        }
        func remove(_ url: URL) { inner.remove(url) }
    }

    @Test("when verification fails the original stays untouched and no temporary file is left")
    func verificationFailureKeepsOriginal() throws {
        let library = try SyntheticLibrary()
        try library.write(SyntheticSongs.fiveFretChart, "A/notes.chart")
        try library.write(SyntheticSongs.fiveFretMIDI, "B/notes.mid")
        try library.write(SyntheticSongs.ini, "A/song.ini")
        let before = try library.snapshot()
        let failing: [ChartFileFormat: any ChartFormatConverter] = [
            .chart: FailingVerifier(inner: ChartTextConverter()), .midi: FailingVerifier(inner: MIDIChartConverter()),
        ]
        let report = try makeConverter(converters: failing).convert(folder: library.root, dryRun: false)
        #expect(report.failedCount == 2)
        #expect(try library.snapshot() == before)
        #expect(
            outcomes(report)["A/notes.chart"] == .failed("verification failed: injected"))
    }

    @Test(
        "a failure at any write step leaves the original untouched",
        arguments: [FailingStore.Step.backup, .write, .replace])
    func storeFailures(step: FailingStore.Step) throws {
        let library = try SyntheticLibrary()
        try library.write(SyntheticSongs.fiveFretChart, "A/notes.chart")
        let before = try library.snapshot()
        let report = try makeConverter(store: FailingStore(failing: step)).convert(folder: library.root, dryRun: false)
        #expect(report.failedCount == 1)
        #expect(try library.snapshot() == before)
    }

    @Test("a damaged dry-run conversion is reported as failed too")
    func dryRunVerifies() throws {
        let library = try SyntheticLibrary()
        try library.write(SyntheticSongs.fiveFretChart, "A/notes.chart")
        let failing: [ChartFileFormat: any ChartFormatConverter] = [
            .chart: FailingVerifier(inner: ChartTextConverter()), .midi: MIDIChartConverter(),
        ]
        let report = try makeConverter(converters: failing).convert(folder: library.root, dryRun: true)
        #expect(report.failedCount == 1)
    }

    // MARK: song.ini

    @Test("song.ini gets diff_guitarghl, and is backed up with the chart")
    func iniPatched() throws {
        let library = try SyntheticLibrary()
        try library.write(SyntheticSongs.fiveFretChart, "A/notes.chart")
        try library.write(SyntheticSongs.ini, "A/song.ini")
        let report = try makeConverter().convert(folder: library.root, dryRun: false)
        #expect(String(decoding: try library.read("A/song.ini"), as: UTF8.self).contains("diff_guitarghl = 4\n"))
        guard case .converted(_, _, let ini) = outcomes(report)["A/notes.chart"] else {
            Issue.record("not converted")
            return
        }
        #expect(ini == .added(value: "4"))
        let backup = try #require(report.backupFolder)
        #expect(try Data(contentsOf: backup.appendingPathComponent("A/song.ini")) == SyntheticSongs.ini)
    }

    @Test("an existing diff_guitarghl stays and the ini is not backed up")
    func iniKept() throws {
        let library = try SyntheticLibrary()
        let ini = Data("[song]\ndiff_guitar = 4\ndiff_guitarghl = 1\n".utf8)
        try library.write(SyntheticSongs.fiveFretChart, "A/notes.chart")
        try library.write(ini, "A/song.ini")
        let report = try makeConverter().convert(folder: library.root, dryRun: false)
        #expect(try library.read("A/song.ini") == ini)
        let backup = try #require(report.backupFolder)
        #expect(!FileManager.default.fileExists(atPath: backup.appendingPathComponent("A/song.ini").path))
        guard case .converted(_, _, let change) = outcomes(report)["A/notes.chart"] else { return }
        #expect(change == .alreadyPresent)
    }

    @Test("a song folder without song.ini is converted and says so")
    func iniMissing() throws {
        let library = try SyntheticLibrary()
        try library.write(SyntheticSongs.fiveFretChart, "A/notes.chart")
        let report = try makeConverter().convert(folder: library.root, dryRun: false)
        guard case .converted(_, _, let change) = outcomes(report)["A/notes.chart"] else { return }
        #expect(change == .missing)
        #expect(!library.exists("A/song.ini"))
    }

    @Test("a chart and a mid in one folder patch the ini once and back it up once")
    func iniOncePerFolder() throws {
        let library = try SyntheticLibrary()
        try library.write(SyntheticSongs.fiveFretChart, "A/notes.chart")
        try library.write(SyntheticSongs.fiveFretMIDI, "A/notes.mid")
        try library.write(SyntheticSongs.ini, "A/song.ini")
        let report = try makeConverter().convert(folder: library.root, dryRun: false)
        let ini = String(decoding: try library.read("A/song.ini"), as: UTF8.self)
        #expect(ini.components(separatedBy: "diff_guitarghl").count == 2)
        let backup = try #require(report.backupFolder)
        #expect(try Data(contentsOf: backup.appendingPathComponent("A/song.ini")) == SyntheticSongs.ini)
    }

    @Test("a song.ini that cannot be written is reported, and the converted chart stays converted")
    func iniFailure() throws {
        let library = try SyntheticLibrary()
        try library.write(SyntheticSongs.fiveFretChart, "A/notes.chart")
        try library.write(SyntheticSongs.ini, "A/song.ini")
        let store = IniFailingStore()
        let report = try makeConverter(store: store).convert(folder: library.root, dryRun: false)
        guard case .converted(_, _, let change) = outcomes(report)["A/notes.chart"] else {
            Issue.record("chart not converted")
            return
        }
        guard case .failed = change else {
            Issue.record("expected an ini failure")
            return
        }
        #expect(report.hasFailures)
        #expect(try library.read("A/song.ini") == SyntheticSongs.ini)
    }

    private struct IniFailingStore: ChartFileStore {
        let inner = DiskChartFileStore()
        struct Injected: Error {}
        func read(_ url: URL) throws -> Data { try inner.read(url) }
        func exists(_ url: URL) -> Bool { inner.exists(url) }
        func backUp(_ url: URL, to destination: URL) throws { try inner.backUp(url, to: destination) }
        func writeTemporary(_ data: Data, besides url: URL) throws -> URL {
            if url.lastPathComponent == "song.ini" { throw Injected() }
            return try inner.writeTemporary(data, besides: url)
        }
        func replace(_ url: URL, withTemporary temporary: URL) throws {
            try inner.replace(url, withTemporary: temporary)
        }
        func remove(_ url: URL) { inner.remove(url) }
    }
}

private final class Seen: @unchecked Sendable {
    private(set) var paths: [String] = []
    func add(_ path: String) { paths.append(path) }
}
