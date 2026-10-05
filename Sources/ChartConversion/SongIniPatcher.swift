import Foundation

public enum SongIniPatch: Equatable, Sendable {
    case alreadyPresent
    case noSongSection
    case updated(Data, value: String)
}

/// Adds `diff_guitarghl` to the `[song]` section of a `song.ini`. Clone Hero may hide the 6-fret part of a
/// song whose ini lacks it. The value copies `diff_guitar` (0 when that is absent); an existing
/// `diff_guitarghl` is never touched.
///
/// The text is handled as ISO Latin-1, which maps every byte to one character, so whatever the encoding,
/// a BOM, line endings and unrelated lines come back byte for byte.
public struct SongIniPatcher: Sendable {
    static let sectionName = "song"
    static let sixFretKey = "diff_guitarghl"
    static let fiveFretKey = "diff_guitar"
    static let defaultValue = "0"
    private static let byteOrderMark = "\u{EF}\u{BB}\u{BF}"

    public init() {}

    public func patch(_ data: Data) throws -> SongIniPatch {
        let lines = Self.lines(of: Self.text(data))
        guard let section = Self.songSection(in: lines) else { return .noSongSection }
        let entries = section.map { ($0, Self.keyValue(of: lines[$0])) }
        if entries.contains(where: { $0.1?.key == Self.sixFretKey }) { return .alreadyPresent }
        let fiveFret = entries.first { $0.1?.key == Self.fiveFretKey }
        let value = fiveFret?.1?.value ?? Self.defaultValue
        let insertAfter = fiveFret?.0 ?? Self.lastContentLine(in: section, of: lines)
        let lineBreak = Self.text(data).contains("\r\n") ? "\r\n" : "\n"
        var patched = lines
        let anchor = lines[insertAfter]
        let newLine = "\(Self.sixFretKey) = \(value)"
        if Self.terminator(of: anchor).isEmpty {
            patched[insertAfter] = anchor + lineBreak
            patched.insert(newLine, at: insertAfter + 1)
        } else {
            patched.insert(newLine + lineBreak, at: insertAfter + 1)
        }
        return .updated(Self.data(patched.joined()), value: value)
    }

    /// Checks that `patched` is `original` plus one `diff_guitarghl` line and returns that line's value.
    public func verify(patched: Data, original: Data) throws -> String {
        let patchedLines = Self.lines(of: Self.text(patched))
        guard let section = Self.songSection(in: patchedLines),
            let index = section.first(where: { Self.keyValue(of: patchedLines[$0])?.key == Self.sixFretKey }),
            let value = Self.keyValue(of: patchedLines[index])?.value
        else { throw ConversionError.verificationFailed("song.ini has no diff_guitarghl in [song]") }
        var rest = patchedLines
        rest.remove(at: index)
        let originalLines = Self.lines(of: Self.text(original))
        guard rest.map(Self.content) == originalLines.map(Self.content) else {
            throw ConversionError.verificationFailed("song.ini changed more than the diff_guitarghl line")
        }
        let expected = Self.songSection(in: originalLines).flatMap { Self.fiveFretValue(in: $0, of: originalLines) }
        guard value == (expected ?? Self.defaultValue) else {
            throw ConversionError.verificationFailed(
                "diff_guitarghl is \(value), diff_guitar is \(expected ?? "absent")")
        }
        return value
    }

    // MARK: Parsing

    private static func text(_ data: Data) -> String {
        String(data: data, encoding: .isoLatin1) ?? ""
    }

    private static func data(_ text: String) -> Data {
        text.data(using: .isoLatin1) ?? Data()
    }

    /// Lines with their terminators attached.
    private static func lines(of text: String) -> [String] {
        var lines: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            current.append(scalar)
            if scalar == "\n" {
                lines.append(String(current))
                current = String.UnicodeScalarView()
            }
        }
        if !current.isEmpty { lines.append(String(current)) }
        return lines
    }

    private static func terminator(of line: String) -> String {
        line.hasSuffix("\r\n") ? "\r\n" : line.hasSuffix("\n") ? "\n" : ""
    }

    private static func content(_ line: String) -> String {
        String(line.dropLast(terminator(of: line).count))
    }

    private static func sectionHeader(_ line: String) -> String? {
        var trimmed = content(line)
        if trimmed.hasPrefix(byteOrderMark) { trimmed.removeFirst(byteOrderMark.unicodeScalars.count) }
        trimmed = trimmed.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return nil }
        return trimmed.dropFirst().dropLast().trimmingCharacters(in: .whitespaces).lowercased()
    }

    private static func songSection(in lines: [String]) -> Range<Int>? {
        guard let header = lines.firstIndex(where: { sectionHeader($0) == sectionName }) else { return nil }
        let end = lines[(header + 1)...].firstIndex { sectionHeader($0) != nil } ?? lines.count
        return (header + 1)..<end
    }

    private static func keyValue(of line: String) -> (key: String, value: String)? {
        let parts = content(line).split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
        return (key, parts[1].trimmingCharacters(in: .whitespaces))
    }

    private static func fiveFretValue(in section: Range<Int>, of lines: [String]) -> String? {
        section.lazy.compactMap { keyValue(of: lines[$0]) }.first { $0.key == fiveFretKey }?.value
    }

    private static func lastContentLine(in section: Range<Int>, of lines: [String]) -> Int {
        section.last { !content(lines[$0]).trimmingCharacters(in: .whitespaces).isEmpty } ?? section.lowerBound - 1
    }
}
