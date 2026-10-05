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
    func convert(folder: URL, dryRun: Bool) throws -> ConversionReport
}

public struct LibraryChartConverter: ChartConverting {
    public init() {}

    public func convert(folder: URL, dryRun: Bool) throws -> ConversionReport {
        try SongLibraryConverter().convert(folder: folder, dryRun: dryRun)
    }
}

public enum ChartConversionState: Equatable, Sendable {
    case idle
    case confirming(folder: URL)
    case converting(folder: URL)
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
        state = .converting(folder: folder)
        let converter = converter
        let outcome = await Task.detached(priority: .userInitiated) {
            Result { try converter.convert(folder: folder, dryRun: false) }
        }.value
        switch outcome {
        case .success(let report): state = .finished(report)
        case .failure(let error): state = .failed(error.localizedDescription)
        }
    }

    public func revealBackup() {
        guard case .finished(let report) = state, let backup = report.backupFolder else { return }
        reveal(backup)
    }
}
