import Foundation

/// Adds `[<Difficulty>GHLGuitar]` sections to a `.chart` file, one per `[<Difficulty>Single]` section that
/// has no 6-fret counterpart. The 5-fret sections are never touched.
public struct ChartTextConverter: ChartFormatConverter {
    private static let byteOrderMark = "\u{FEFF}"
    private static let lineFeed: Character = "\n"
    private static let carriageReturn: Character = "\r"

    public init() {}

    public func convert(_ data: Data) throws -> ConversionAttempt {
        let text = try Self.decode(data)
        let sections = ChartText.lookup(ChartText.sections(of: text))
        let missing = GuitarDifficulty.allCases.filter {
            sections[$0.fiveFretSection] != nil && sections[$0.sixFretSection] == nil
        }
        guard !missing.isEmpty else {
            let hasFiveFret = GuitarDifficulty.allCases.contains { sections[$0.fiveFretSection] != nil }
            let hasSixFret = GuitarDifficulty.allCases.contains { sections[$0.sixFretSection] != nil }
            return hasFiveFret || hasSixFret ? .alreadyHasSixFret : .noFiveFretTrack
        }
        let lineBreak = text.contains("\r\n") ? "\r\n" : "\n"
        var converted = text
        for difficulty in missing {
            guard let source = sections[difficulty.fiveFretSection] else { continue }
            converted = Self.appending(
                section: difficulty.sixFretSection, lines: Self.sixFretLines(from: source.lines), to: converted,
                lineBreak: lineBreak)
        }
        return .converted(Data(converted.utf8), addedTracks: missing.map(\.sixFretSection))
    }

    public func verify(converted: Data, original: Data) throws -> Int {
        let text = try Self.decode(converted)
        guard Self.trimmingTrailingLineFeeds(text).hasPrefix(Self.trimmingTrailingLineFeeds(try Self.decode(original)))
        else { throw ConversionError.verificationFailed("the original chart content changed") }
        let sections = ChartText.lookup(ChartText.sections(of: text))
        var total = 0
        for difficulty in GuitarDifficulty.allCases {
            guard let five = sections[difficulty.fiveFretSection] else { continue }
            guard let six = sections[difficulty.sixFretSection] else {
                throw ConversionError.verificationFailed(
                    "\(difficulty.fiveFretSection) has no \(difficulty.sixFretSection)")
            }
            total += try Self.verifyNotes(five: five, six: six, difficulty: difficulty)
        }
        return total
    }

    // MARK: Conversion

    private static func decode(_ data: Data) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else { throw ConversionError.notUTF8 }
        return text.hasPrefix(byteOrderMark) ? String(text.dropFirst()) : text
    }

    /// Note lines are mapped (unknown numbers dropped); star power, events and the braces are copied.
    static func sixFretLines(from lines: [String]) -> [String] {
        lines.compactMap { line in
            guard let note = ChartNoteLine(line) else { return line }
            return ChartLaneMap.sixFretNote(forFiveFret: note.lane).map { "\(note.prefix)\($0)\(note.suffix)" }
        }
    }

    private static func appending(section: String, lines: [String], to text: String, lineBreak: String) -> String {
        var head = trimmingTrailingLineFeeds(text)
        // A CRLF file keeps its carriage return after the trim, so only the line feed is missing.
        head += head.unicodeScalars.last == "\r" ? "\n" : lineBreak
        return head + ([["[\(section)]"], lines].joined()).joined(separator: lineBreak) + lineBreak
    }

    /// Drops only line feeds, so the carriage return of a final CRLF stays and keeps the line structure.
    private static func trimmingTrailingLineFeeds(_ text: String) -> String {
        var scalars = text.unicodeScalars
        while scalars.last == "\n" { scalars.removeLast() }
        return String(scalars)
    }

    // MARK: Verification

    private static func verifyNotes(five: ChartSection, six: ChartSection, difficulty: GuitarDifficulty) throws -> Int {
        let expected = laneCounts(
            five.lines.compactMap(ChartNoteLine.init).compactMap {
                ChartLaneMap.sixFretNote(forFiveFret: $0.lane)
            })
        let actual = laneCounts(six.lines.compactMap(ChartNoteLine.init).map(\.lane))
        guard expected == actual else {
            throw ConversionError.verificationFailed(
                "\(difficulty.rawValue): note counts differ (expected \(expected.sorted { $0.key < $1.key }), found \(actual.sorted { $0.key < $1.key }))"
            )
        }
        return actual.values.reduce(0, +)
    }

    private static func laneCounts(_ lanes: [Int]) -> [Int: Int] {
        lanes.reduce(into: [:]) { counts, lane in counts[lane, default: 0] += 1 }
    }
}
