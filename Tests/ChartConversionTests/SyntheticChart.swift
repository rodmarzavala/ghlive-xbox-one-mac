import Foundation

/// Synthetic `.chart` text. No real song: every title and tick is invented.
enum SyntheticChart {
    /// Rows of one note section: `(tick, note number)` pairs become `<tick> = N <note> 0` lines.
    static func notes(_ notes: [(tick: Int, note: Int)]) -> [String] {
        notes.map { "  \($0.tick) = N \($0.note) 0" }
    }

    static func section(_ name: String, _ lines: [String]) -> String {
        (["[\(name)]", "{"] + lines + ["}"]).joined(separator: "\n")
    }

    static let preamble: [String] = [
        section("Song", ["  Name = \"Synthetic Song\"", "  Resolution = 192"]),
        section("SyncTrack", ["  0 = TS 4", "  0 = B 120000"]),
        section("Events", ["  0 = E \"section Intro\""]),
    ]

    /// A chart with one 5-fret section per difficulty given, each holding `lines`.
    static func text(
        difficulties: [String] = ["Expert"], lines: [String], extraSections: [String] = [], lineBreak: String = "\n"
    ) -> String {
        let singles = difficulties.map { section("\($0)Single", lines) }
        return (preamble + singles + extraSections).joined(separator: "\n")
            .replacingOccurrences(of: "\n", with: lineBreak) + lineBreak
    }

    /// The lines between the braces of the named section; nil when the section is absent.
    static func body(of name: String, in text: String) -> [String]? {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard let header = lines.firstIndex(of: "[\(name)]") else { return nil }
        let rest = lines[(header + 2)...]
        return Array(rest.prefix { $0 != "}" })
    }

    /// The note numbers of the `N` lines of a section, in file order.
    static func noteNumbers(of name: String, in text: String) -> [Int]? {
        body(of: name, in: text)?.compactMap { line in
            let parts = line.split(separator: " ")
            guard parts.count >= 4, parts[1] == "=", parts[2] == "N" else { return nil }
            return Int(parts[3])
        }
    }
}
