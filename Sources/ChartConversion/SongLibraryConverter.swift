import Foundation

/// Walks a songs folder and adds the 6-fret tracks to every song that has a 5-fret guitar track.
///
/// Nothing is changed before the original is copied to a backup folder next to the songs folder (never
/// inside it: Clone Hero would scan the copies). The converted file is written beside the original, read
/// back and verified, and only then swapped in atomically. Any failure leaves the original as it was.
public struct SongLibraryConverter: Sendable {
    public static let defaultConverters: [ChartFileFormat: any ChartFormatConverter] = [
        .chart: ChartTextConverter(), .midi: MIDIChartConverter(),
    ]

    private static let chartFileName = "notes.chart"
    private static let midiFileName = "notes.mid"
    private static let songPackageExtension = "sng"
    private static let iniFileName = "song.ini"
    private static let backupInfix = " - backup "
    private static let timestampFormat = "yyyy-MM-dd HHmmss"

    private let store: any ChartFileStore
    private let converters: [ChartFileFormat: any ChartFormatConverter]
    private let iniPatcher: SongIniPatcher
    private let now: @Sendable () -> Date
    private let timeZone: TimeZone

    public init(
        store: any ChartFileStore = DiskChartFileStore(),
        converters: [ChartFileFormat: any ChartFormatConverter] = SongLibraryConverter.defaultConverters,
        iniPatcher: SongIniPatcher = SongIniPatcher(),
        now: @escaping @Sendable () -> Date = { Date() },
        timeZone: TimeZone = .current
    ) {
        self.store = store
        self.converters = converters
        self.iniPatcher = iniPatcher
        self.now = now
        self.timeZone = timeZone
    }

    /// Where the originals of a run over `folder` go.
    public func backupFolder(for folder: URL) -> URL {
        let root = folder.standardizedFileURL
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = Self.timestampFormat
        let name = root.lastPathComponent + Self.backupInfix + formatter.string(from: now())
        return root.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true)
    }

    /// `onResult` is called for each song as soon as it is done.
    public func convert(
        folder: URL, dryRun: Bool, onResult: (SongResult) -> Void = { _ in }
    ) throws -> ConversionReport {
        let root = folder.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue
        else { throw LibraryError.notAFolder(folder.path) }
        let run = Run(dryRun: dryRun, backupFolder: backupFolder(for: root))
        var results: [SongResult] = []
        walk(root, relativePath: "", run: run) { result in
            results.append(result)
            onResult(result)
        }
        return ConversionReport(
            root: root, isDryRun: dryRun, results: results, backupFolder: run.backupWasUsed ? run.backupFolder : nil)
    }

    private final class Run {
        let dryRun: Bool
        let backupFolder: URL
        var backupWasUsed = false

        init(dryRun: Bool, backupFolder: URL) {
            self.dryRun = dryRun
            self.backupFolder = backupFolder
        }
    }

    // MARK: Walking

    private struct Entry {
        let url: URL
        let isDirectory: Bool
        var name: String { url.lastPathComponent }
    }

    private func walk(_ directory: URL, relativePath: String, run: Run, report: (SongResult) -> Void) {
        let entries: [Entry]
        do {
            entries = try listing(of: directory)
        } catch {
            report(SongResult(path: relativePath, outcome: .failed("cannot read the folder: \(Self.describe(error))")))
            return
        }
        let iniURL = entries.first { !$0.isDirectory && $0.name.lowercased() == Self.iniFileName }?.url
        for file in entries where !file.isDirectory {
            guard let format = Self.format(ofFile: file.name) else { continue }
            let path = Self.join(relativePath, file.name)
            report(SongResult(path: path, outcome: process(file.url, format, path: path, iniURL: iniURL, run: run)))
        }
        for subfolder in entries where subfolder.isDirectory {
            walk(subfolder.url, relativePath: Self.join(relativePath, subfolder.name), run: run, report: report)
        }
    }

    private func listing(of directory: URL) throws -> [Entry] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        return urls.map {
            Entry(url: $0, isDirectory: (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true)
        }
        .sorted { $0.name < $1.name }
    }

    /// `.sng` files are recognised only to be reported; they have no converter.
    private enum FileKind {
        case convertible(ChartFileFormat)
        case unsupported
    }

    private static func format(ofFile name: String) -> FileKind? {
        switch name.lowercased() {
        case chartFileName: .convertible(.chart)
        case midiFileName: .convertible(.midi)
        case let other where URL(fileURLWithPath: other).pathExtension == songPackageExtension: .unsupported
        default: nil
        }
    }

    private static func join(_ parent: String, _ name: String) -> String {
        parent.isEmpty ? name : "\(parent)/\(name)"
    }

    // MARK: One file

    private func process(_ url: URL, _ kind: FileKind, path: String, iniURL: URL?, run: Run) -> SongOutcome {
        guard case .convertible(let format) = kind else { return .unsupportedFormat }
        guard let converter = converters[format] else { return .failed("no converter for this format") }
        do {
            let original = try store.read(url)
            switch try converter.convert(original) {
            case .alreadyHasSixFret: return .alreadyHasSixFret
            case .noFiveFretTrack: return .noFiveFretTrack
            case .converted(let data, let added):
                let notes = try apply(data, over: url, original: original, path: path, converter: converter, run: run)
                let ini = patchIni(iniURL, besides: path, run: run)
                return .converted(addedTracks: added, notes: notes, songIni: ini)
            }
        } catch {
            return .failed(Self.describe(error))
        }
    }

    /// Verifies the conversion and, unless this is a dry run, backs the original up and replaces it.
    private func apply(
        _ data: Data, over url: URL, original: Data, path: String, converter: any ChartFormatConverter, run: Run
    ) throws -> Int {
        guard !run.dryRun else { return try converter.verify(converted: data, original: original) }
        try backUp(url, path: path, run: run)
        return try writeVerified(data, over: url) { try converter.verify(converted: $0, original: original) }
    }

    private func backUp(_ url: URL, path: String, run: Run) throws {
        try store.backUp(url, to: run.backupFolder.appendingPathComponent(path))
        run.backupWasUsed = true
    }

    private func writeVerified<Result>(_ data: Data, over url: URL, verify: (Data) throws -> Result) throws -> Result {
        let temporary = try store.writeTemporary(data, besides: url)
        do {
            let result = try verify(try store.read(temporary))
            try store.replace(url, withTemporary: temporary)
            return result
        } catch {
            store.remove(temporary)
            throw error
        }
    }

    // MARK: song.ini

    private func patchIni(_ iniURL: URL?, besides chartPath: String, run: Run) -> SongIniChange {
        guard let iniURL else { return .missing }
        do {
            let original = try store.read(iniURL)
            switch try iniPatcher.patch(original) {
            case .alreadyPresent: return .alreadyPresent
            case .noSongSection: return .missing
            case .updated(let data, let value):
                if !run.dryRun { try writeIni(data, over: iniURL, original: original, chartPath: chartPath, run: run) }
                return .added(value: value)
            }
        } catch {
            return .failed(Self.describe(error))
        }
    }

    private func writeIni(_ data: Data, over url: URL, original: Data, chartPath: String, run: Run) throws {
        let folder = (chartPath as NSString).deletingLastPathComponent
        let path = Self.join(folder, url.lastPathComponent)
        if !store.exists(run.backupFolder.appendingPathComponent(path)) { try backUp(url, path: path, run: run) }
        _ = try writeVerified(data, over: url) { try iniPatcher.verify(patched: $0, original: original) }
    }

    private static func describe(_ error: Error) -> String {
        (error as? CustomStringConvertible)?.description ?? error.localizedDescription
    }
}
