import Foundation

/// The wording shared by the command line and the app.
extension SongResult {
    public func line(dryRun: Bool) -> String {
        let detail = detailText.map { " (\($0))" } ?? ""
        return "\(headline(dryRun: dryRun)): \(path)\(detail)"
    }

    public func headline(dryRun: Bool) -> String {
        switch outcome {
        case .converted: dryRun ? "would convert" : "converted"
        case .alreadyHasSixFret, .noFiveFretTrack, .unsupportedFormat, .symbolicLink: "skipped"
        case .failed: "failed"
        }
    }

    public var detailText: String? {
        switch outcome {
        case .converted(let added, let notes, let songIni):
            "added \(added.joined(separator: ", ")); \(notes) notes verified; \(songIni.text)"
        case .alreadyHasSixFret(let songIni):
            ["already has a 6-fret track", songIni.reportedText].compactMap { $0 }.joined(separator: "; ")
        case .symbolicLink: "symbolic link"
        case .noFiveFretTrack: "no 5-fret guitar track"
        case .unsupportedFormat: ".sng is not supported yet"
        case .failed(let reason): reason
        }
    }
}

extension SongIniChange {
    /// Only what changed or went wrong: a skipped song stays quiet about an ini that needed nothing.
    fileprivate var reportedText: String? {
        switch self {
        case .added, .failed: text
        case .alreadyPresent, .missing: nil
        }
    }

    fileprivate var text: String {
        switch self {
        case .added(let value): "song.ini: added diff_guitarghl = \(value)"
        case .alreadyPresent: "song.ini: diff_guitarghl already set"
        case .missing: "song.ini: none to update"
        case .failed(let reason): "song.ini: could not update (\(reason))"
        }
    }
}

extension ConversionReport {
    public static let rescanReminder = "Rescan your songs in Clone Hero so the new 6-fret parts show up."

    public var summary: String {
        let converted = "\(convertedCount) \(isDryRun ? "would be converted" : "converted")"
        return "\(converted), \(skippedCount) skipped, \(failedCount) failed"
    }
}
