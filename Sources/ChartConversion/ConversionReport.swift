import Foundation

/// What happened to the `song.ini` next to a converted chart.
public enum SongIniChange: Equatable, Sendable {
    /// `diff_guitarghl` was added (or, in a dry run, would be) with this value.
    case added(value: String)
    case alreadyPresent
    /// No `song.ini`, or one without a `[song]` section: nothing to patch.
    case missing
    case failed(String)
}

public enum SongOutcome: Equatable, Sendable {
    case converted(addedTracks: [String], notes: Int, songIni: SongIniChange)
    case alreadyHasSixFret
    case noFiveFretTrack
    case unsupportedFormat
    case failed(String)
}

public struct SongResult: Equatable, Sendable {
    /// Path of the chart file relative to the folder that was converted.
    public let path: String
    public let outcome: SongOutcome

    public init(path: String, outcome: SongOutcome) {
        self.path = path
        self.outcome = outcome
    }

    public var isFailure: Bool {
        switch outcome {
        case .failed: true
        case .converted(_, _, .failed): true
        default: false
        }
    }
}

public struct ConversionReport: Equatable, Sendable {
    public let root: URL
    public let isDryRun: Bool
    public let results: [SongResult]
    /// The folder the originals were copied to; nil when nothing was backed up.
    public let backupFolder: URL?

    public var convertedCount: Int {
        results.filter {
            if case .converted = $0.outcome { return true }
            return false
        }.count
    }

    public var failedCount: Int { results.filter(\.isFailure).count }
    public var hasFailures: Bool { failedCount > 0 }
    public var skippedCount: Int {
        results.filter {
            switch $0.outcome {
            case .alreadyHasSixFret, .noFiveFretTrack, .unsupportedFormat: true
            case .converted, .failed: false
            }
        }.count
    }
}

public enum LibraryError: Error, Equatable, Sendable, LocalizedError {
    case notAFolder(String)

    public var errorDescription: String? {
        switch self {
        case .notAFolder(let path): "'\(path)' is not a folder"
        }
    }
}
