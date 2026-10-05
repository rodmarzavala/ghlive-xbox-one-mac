import Foundation

enum GuitarDifficulty: String, CaseIterable, Sendable {
    case expert = "Expert"
    case hard = "Hard"
    case medium = "Medium"
    case easy = "Easy"

    /// `[ExpertSingle]`, the lead 5-fret section.
    var fiveFretSection: String { "\(rawValue)Single" }

    /// `[ExpertGHLGuitar]`, the 6-fret section.
    var sixFretSection: String { "\(rawValue)GHLGuitar" }
}

/// One `[Name]` section of a `.chart` file: its lines between this header and the next, braces included.
struct ChartSection {
    let name: String
    let lines: [String]
}

/// A `<tick> = N <lane> <length>` line, split around the lane number so the rest is kept verbatim.
struct ChartNoteLine {
    let prefix: Substring
    let lane: Int
    let suffix: Substring

    /// Accepts `^\s*\d+\s*=\s*N\s+(\d+)\s+\d+\s*$`, the same shape the prototype matched.
    init?(_ line: String) {
        var rest = line[...]
        rest.trimPrefix(while: \.isWhitespace)
        guard rest.trimPrefix(while: \.isNumber) > 0 else { return nil }
        rest.trimPrefix(while: \.isWhitespace)
        guard rest.popFirst() == "=" else { return nil }
        rest.trimPrefix(while: \.isWhitespace)
        guard rest.popFirst() == "N" else { return nil }
        let afterN = rest
        rest.trimPrefix(while: \.isWhitespace)
        guard rest.startIndex > afterN.startIndex else { return nil }
        let laneStart = rest.startIndex
        guard rest.trimPrefix(while: \.isNumber) > 0, let lane = Int(line[laneStart..<rest.startIndex]) else {
            return nil
        }
        let suffix = rest
        rest.trimPrefix(while: \.isWhitespace)
        guard rest.startIndex > suffix.startIndex, rest.trimPrefix(while: \.isNumber) > 0 else { return nil }
        rest.trimPrefix(while: \.isWhitespace)
        guard rest.isEmpty else { return nil }
        self.prefix = line[..<laneStart]
        self.lane = lane
        self.suffix = suffix
    }
}

extension Substring {
    /// Removes the leading characters that satisfy `predicate`; returns how many went.
    @discardableResult
    fileprivate mutating func trimPrefix(while predicate: (Character) -> Bool) -> Int {
        var count = 0
        while let first = first, predicate(first) {
            removeFirst()
            count += 1
        }
        return count
    }
}

enum ChartText {
    /// Like Python's `splitlines`: a final line break does not start another, empty, line.
    static func lines(of text: String) -> [String] {
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        if let last = lines.last, last.isEmpty, !text.isEmpty { lines.removeLast() }
        return lines
    }

    static func sections(of text: String) -> [ChartSection] {
        var sections: [ChartSection] = []
        var currentName: String?
        var body: [String] = []
        for line in lines(of: text) {
            guard let header = sectionName(of: line) else {
                body.append(line)
                continue
            }
            if let name = currentName { sections.append(ChartSection(name: name, lines: body)) }
            currentName = header
            body = []
        }
        if let name = currentName { sections.append(ChartSection(name: name, lines: body)) }
        return sections
    }

    /// `[Name]` with optional surrounding whitespace; the name is letters, digits and underscores.
    static func sectionName(of line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]"), trimmed.count > 2 else { return nil }
        let name = trimmed.dropFirst().dropLast()
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" } ? String(name) : nil
    }

    /// The last section of that name wins, as in the prototype's dictionary.
    static func lookup(_ sections: [ChartSection]) -> [String: ChartSection] {
        Dictionary(sections.map { ($0.name, $0) }, uniquingKeysWith: { _, later in later })
    }
}
