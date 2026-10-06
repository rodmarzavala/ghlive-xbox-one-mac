import AppKit
import ChartConversion
import Foundation

/// Seam over the open panel, so choosing a folder is testable.
@MainActor
public protocol FolderPicking {
    /// The folder the user chose; nil when they cancelled.
    func pickSongsFolder() -> URL?
}

@MainActor
public struct OpenPanelFolderPicker: FolderPicking {
    public init() {}

    public func pickSongsFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose your Clone Hero songs folder"
        panel.message = "GHLive adds 6-fret tracks to the songs in this folder, and in the folders inside it."
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Seam over the conversion, so the model can be tested without touching disk. Implementations run on
/// whatever thread calls them.
public protocol ChartConverting: Sendable {
    /// `onResult` is called from the converting thread as each song is done.
    func convert(folder: URL, dryRun: Bool, onResult: @Sendable (SongResult) -> Void) throws -> ConversionReport
}

public struct LibraryChartConverter: ChartConverting {
    public init() {}

    public func convert(folder: URL, dryRun: Bool, onResult: @Sendable (SongResult) -> Void) throws -> ConversionReport
    {
        try SongLibraryConverter().convert(folder: folder, dryRun: dryRun, onResult: onResult)
    }
}

/// How far a running conversion is.
public struct ConversionProgress: Equatable, Sendable {
    public var songsDone = 0
    /// The path of the song that finished last.
    public var latest: String?

    public init(songsDone: Int = 0, latest: String? = nil) {
        self.songsDone = songsDone
        self.latest = latest
    }
}

public enum ChartConversionState: Equatable, Sendable {
    case idle
    case confirming(folder: URL)
    case converting(folder: URL, progress: ConversionProgress)
    case finished(ConversionReport)
    case failed(String)
}

enum ChartConversionCopy {
    /// Where the backup goes, as the confirmation words it: the real name carries the time of the run.
    static func backupLocation(for folder: URL) -> String {
        let parent = folder.deletingLastPathComponent().path
        return "\(parent)/\(folder.lastPathComponent) - backup <date and time>"
    }
}

/// The "Add 6-fret tracks to songs" flow: choose a folder, confirm, convert, read the result.
/// The conversion runs off the main actor; the model only moves between states.
@MainActor
public final class ChartConversionModel: ObservableObject {
    @Published public private(set) var state: ChartConversionState

    private let picker: any FolderPicking
    private let converter: any ChartConverting
    private let reveal: (URL) -> Void

    public init(
        picker: any FolderPicking = OpenPanelFolderPicker(),
        converter: any ChartConverting = LibraryChartConverter(),
        reveal: @escaping (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
        state: ChartConversionState = .idle
    ) {
        self.picker = picker
        self.converter = converter
        self.reveal = reveal
        self.state = state
    }

    /// Whether the conversion window has something to show.
    public var isPresenting: Bool { state != .idle }

    /// What the menu item does: bring back a job that is waiting, running or done, or else ask for a folder.
    /// Returns whether the window should be shown.
    @discardableResult
    public func begin() -> Bool {
        if state == .idle { return chooseFolder() }
        return true
    }

    /// Asks for a folder. Returns whether one was chosen; a cancelled panel changes nothing.
    @discardableResult
    public func chooseFolder() -> Bool {
        if case .converting = state { return false }
        guard let folder = picker.pickSongsFolder() else { return false }
        state = .confirming(folder: folder)
        return true
    }

    public func cancel() {
        guard case .confirming = state else { return }
        state = .idle
    }

    public func dismiss() {
        if case .converting = state { return }
        state = .idle
    }

    /// Converts the chosen folder. Does nothing unless a folder is waiting for confirmation.
    public func confirm() async {
        guard case .confirming(let folder) = state else { return }
        state = .converting(folder: folder, progress: ConversionProgress())
        let converter = converter
        let outcome = await Task.detached(priority: .userInitiated) { [weak self] in
            Result {
                try converter.convert(folder: folder, dryRun: false) { result in
                    Task { @MainActor in self?.record(result) }
                }
            }
        }.value
        switch outcome {
        case .success(let report): state = .finished(report)
        case .failure(let error): state = .failed(error.localizedDescription)
        }
    }

    private func record(_ result: SongResult) {
        guard case .converting(let folder, var progress) = state else { return }
        progress.songsDone += 1
        progress.latest = result.path
        state = .converting(folder: folder, progress: progress)
    }

    public func revealBackup() {
        guard case .finished(let report) = state, let backup = report.backupFolder else { return }
        reveal(backup)
    }
}
