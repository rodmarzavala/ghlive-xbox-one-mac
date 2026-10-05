import Foundation
import Testing

@testable import ChartConversion

@Suite("Chart (.chart) conversion")
struct ChartTextConverterTests {
    private typealias C = SyntheticChart
    private let converter = ChartTextConverter()

    /// 5-fret numbers: G R Y B O = 0...4, flip 5, tap 6, open 7.
    private let fiveFretNotes: [(tick: Int, note: Int)] = [
        (0, 0), (192, 1), (384, 2), (576, 3), (768, 4), (960, 7), (1152, 5), (1152, 0), (1344, 6), (1344, 2),
    ]

    private func convert(_ text: String) throws -> (text: String, added: [String])? {
        let outcome = try converter.convert(Data(text.utf8))
        guard case .converted(let data, let added) = outcome else { return nil }
        return (String(decoding: data, as: UTF8.self), added)
    }

    @Test(
        "each lane follows Clone Hero's control pairing",
        arguments: [
            (0, 3, "Green to Black 1"), (1, 4, "Red to Black 2"), (2, 8, "Yellow to Black 3"),
            (3, 0, "Blue to White 1"), (4, 1, "Orange to White 2"), (7, 7, "open"), (5, 5, "flip"), (6, 6, "tap"),
        ])
    func laneMapping(five: Int, six: Int, label: String) throws {
        let result = try #require(try convert(C.text(lines: C.notes([(0, five)]))))
        #expect(C.noteNumbers(of: "ExpertGHLGuitar", in: result.text) == [six], Comment(rawValue: label))
    }

    @Test("a section is appended after the source; the 5-fret one stays as it was")
    func appendsAndKeeps() throws {
        let source = C.text(lines: C.notes(fiveFretNotes))
        let result = try #require(try convert(source))
        #expect(result.added == ["ExpertGHLGuitar"])
        #expect(result.text.hasPrefix(source))
        #expect(
            C.noteNumbers(of: "ExpertGHLGuitar", in: result.text) == [3, 4, 8, 0, 1, 7, 5, 3, 6, 8])
    }

    @Test("forced and tap notes are kept, lined up with the notes they modify")
    func modifiersKept() throws {
        let result = try #require(try convert(C.text(lines: C.notes(fiveFretNotes))))
        let six = try #require(C.body(of: "ExpertGHLGuitar", in: result.text))
        #expect(six.contains("  1152 = N 5 0"))
        #expect(six.contains("  1344 = N 6 0"))
    }

    @Test("sustain lengths survive")
    func lengthsKept() throws {
        let result = try #require(try convert(C.text(lines: ["  0 = N 2 96"])))
        #expect(C.body(of: "ExpertGHLGuitar", in: result.text) == ["  0 = N 8 96"])
    }

    @Test("star power and event lines are copied, and unknown note numbers are dropped")
    func nonNoteLines() throws {
        let lines = [
            "  0 = N 0 0", "  0 = S 2 384", "  96 = N 9 0", "  96 = N 12 0", "  192 = E solo", "  384 = E soloend",
        ]
        let result = try #require(try convert(C.text(lines: lines)))
        #expect(
            C.body(of: "ExpertGHLGuitar", in: result.text) == [
                "  0 = N 3 0", "  0 = S 2 384", "  192 = E solo", "  384 = E soloend",
            ])
    }

    @Test("every difficulty gets its own section")
    func severalDifficulties() throws {
        let source = C.text(difficulties: ["Expert", "Hard", "Medium", "Easy"], lines: C.notes([(0, 1)]))
        let result = try #require(try convert(source))
        #expect(
            result.added == ["ExpertGHLGuitar", "HardGHLGuitar", "MediumGHLGuitar", "EasyGHLGuitar"])
        for difficulty in ["Expert", "Hard", "Medium", "Easy"] {
            #expect(C.noteNumbers(of: "\(difficulty)GHLGuitar", in: result.text) == [4])
        }
    }

    @Test("a difficulty that already has a 6-fret section is skipped, the others are added")
    func existingSectionSkipped() throws {
        let existing = C.section("HardGHLGuitar", C.notes([(0, 8)]))
        let source = C.text(difficulties: ["Expert", "Hard"], lines: C.notes([(0, 0)]), extraSections: [existing])
        let result = try #require(try convert(source))
        #expect(result.added == ["ExpertGHLGuitar"])
        #expect(C.noteNumbers(of: "HardGHLGuitar", in: result.text) == [8])
    }

    @Test("a chart that has every 6-fret section is already done")
    func alreadyDone() throws {
        let existing = C.section("ExpertGHLGuitar", C.notes([(0, 8)]))
        let source = C.text(lines: C.notes([(0, 0)]), extraSections: [existing])
        #expect(try converter.convert(Data(source.utf8)) == .alreadyHasSixFret)
    }

    @Test("a chart with no lead 5-fret section has nothing to convert")
    func noFiveFret() throws {
        let source = (C.preamble + [C.section("ExpertDoubleBass", C.notes([(0, 0)]))]).joined(separator: "\n")
        #expect(try converter.convert(Data(source.utf8)) == .noFiveFretTrack)
    }

    @Test("running twice adds nothing: the second pass reports already done")
    func idempotent() throws {
        let first = try #require(try convert(C.text(lines: C.notes(fiveFretNotes))))
        #expect(try converter.convert(Data(first.text.utf8)) == .alreadyHasSixFret)
    }

    @Test("a BOM is stripped and the text stays UTF-8, accents included")
    func bomAndEncoding() throws {
        let source =
            "\u{FEFF}" + C.text(lines: C.notes([(0, 0)])).replacingOccurrences(of: "Synthetic", with: "Sintético")
        let outcome = try converter.convert(Data(source.utf8))
        guard case .converted(let data, _) = outcome else {
            Issue.record("not converted")
            return
        }
        #expect(Array(data.prefix(3)) != [0xEF, 0xBB, 0xBF])
        #expect(String(decoding: data, as: UTF8.self).contains("Sintético"))
    }

    @Test("a file that is not UTF-8 is refused, not mangled")
    func notUTF8() {
        #expect(throws: ConversionError.notUTF8) { try converter.convert(Data([0x5B, 0xE9, 0x5D])) }
    }

    @Test("CRLF files keep CRLF, including in the new section")
    func crlf() throws {
        let source = C.text(lines: C.notes([(0, 0)]), lineBreak: "\r\n")
        let result = try #require(try convert(source))
        #expect(result.text.hasPrefix(source))
        let stripped = result.text.replacingOccurrences(of: "\r\n", with: "")
        #expect(!stripped.contains("\n") && !stripped.contains("\r"))
    }

    @Test("a missing final newline and trailing blank lines do not break the append")
    func trailingWhitespace() throws {
        let bare = C.text(lines: C.notes([(0, 0)])).trimmingCharacters(in: .newlines)
        let result = try #require(try convert(bare))
        #expect(C.noteNumbers(of: "ExpertGHLGuitar", in: result.text) == [3])
        #expect(result.text.hasSuffix("}\n"))
    }

    @Test("section headers are matched exactly, so ExpertSingleFoo is not a lead track")
    func exactHeaders() throws {
        let source = C.preamble.joined(separator: "\n") + "\n" + C.section("ExpertSingleFoo", C.notes([(0, 0)]))
        #expect(try converter.convert(Data(source.utf8)) == .noFiveFretTrack)
    }

    // MARK: Verification

    @Test("verification counts the mapped notes of a good conversion")
    func verifiesGoodOutput() throws {
        let source = C.text(difficulties: ["Expert", "Hard"], lines: C.notes(fiveFretNotes))
        let result = try #require(try convert(source))
        let count = try converter.verify(converted: Data(result.text.utf8), original: Data(source.utf8))
        #expect(count == fiveFretNotes.count * 2)
    }

    @Test("verification accepts CRLF files, with and without blank lines at the end")
    func verifiesCRLF() throws {
        for ending in ["\r\n", "\r\n\r\n", ""] {
            let source = C.text(lines: C.notes(fiveFretNotes), lineBreak: "\r\n") + ending
            let result = try #require(try convert(source))
            let count = try converter.verify(converted: Data(result.text.utf8), original: Data(source.utf8))
            #expect(count == fiveFretNotes.count)
        }
    }

    @Test("verification catches a changed lane, a missing note and an extra note")
    func catchesCorruption() throws {
        let source = C.text(lines: C.notes(fiveFretNotes))
        let good = try #require(try convert(source)).text
        let split = try #require(good.range(of: "[ExpertGHLGuitar]"))
        let head = String(good[..<split.lowerBound])
        let tail = String(good[split.lowerBound...])
        let corruptions = [
            head + tail.replacingOccurrences(of: "  0 = N 3 0", with: "  0 = N 4 0"),
            head + tail.replacingOccurrences(of: "  192 = N 4 0\n", with: ""),
            head + tail.replacingOccurrences(of: "}", with: "  1 = N 0 0\n}"),
        ]
        for corrupted in corruptions {
            #expect(throws: ConversionError.self) {
                try converter.verify(converted: Data(corrupted.utf8), original: Data(source.utf8))
            }
        }
    }

    @Test("verification fails when the original content is no longer there")
    func catchesLostOriginal() throws {
        let source = C.text(lines: C.notes(fiveFretNotes))
        let good = try #require(try convert(source)).text
        let damaged = good.replacingOccurrences(of: "Synthetic Song", with: "Other Song")
        #expect(throws: ConversionError.self) {
            try converter.verify(converted: Data(damaged.utf8), original: Data(source.utf8))
        }
    }

    @Test("verification fails when a 5-fret difficulty has no 6-fret counterpart")
    func catchesMissingSection() throws {
        let source = C.text(lines: C.notes(fiveFretNotes))
        #expect(throws: ConversionError.self) {
            try converter.verify(converted: Data(source.utf8), original: Data(source.utf8))
        }
    }
}
