import Foundation
import Testing

@testable import ChartConversion

@Suite("song.ini diff_guitarghl")
struct SongIniPatcherTests {
    private let patcher = SongIniPatcher()

    private func patched(_ text: String) throws -> String? {
        guard case .updated(let data, _) = try patcher.patch(Data(text.utf8)) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    @Test("a missing key is added after diff_guitar with the same value")
    func copiesDifficulty() throws {
        let ini = "[song]\nname = Synthetic\ndiff_guitar = 4\ndiff_bass = 2\n"
        #expect(try patched(ini) == "[song]\nname = Synthetic\ndiff_guitar = 4\ndiff_guitarghl = 4\ndiff_bass = 2\n")
    }

    @Test("the new line uses the same key spacing style as a bare value")
    func valueIsTrimmed() throws {
        #expect(try patched("[song]\ndiff_guitar=  7  \n")?.contains("diff_guitarghl = 7\n") == true)
    }

    @Test("without diff_guitar the value is 0 and the key goes at the end of the section")
    func absentDifficulty() throws {
        let ini = "[Song]\nname = Synthetic\nartist = Nobody\n\n[other]\nx = 1\n"
        #expect(
            try patched(ini) == "[Song]\nname = Synthetic\nartist = Nobody\ndiff_guitarghl = 0\n\n[other]\nx = 1\n")
    }

    @Test("a negative diff_guitar (no 5-fret part) is not copied: the value is 0")
    func negativeDifficulty() throws {
        #expect(try patched("[song]\ndiff_guitar = -1\n") == "[song]\ndiff_guitar = -1\ndiff_guitarghl = 0\n")
        #expect(try patched("[song]\ndiff_guitar = 0\n")?.contains("diff_guitarghl = 0\n") == true)
        #expect(try patched("[song]\ndiff_guitar = abc\n")?.contains("diff_guitarghl = 0\n") == true)
        let good = try #require(try patched("[song]\ndiff_guitar = -1\n"))
        #expect(try patcher.verify(patched: Data(good.utf8), original: Data("[song]\ndiff_guitar = -1\n".utf8)) == "0")
    }

    @Test("an existing diff_guitarghl is never overwritten, whatever its case")
    func existingKeyKept() throws {
        #expect(try patcher.patch(Data("[song]\ndiff_guitar = 4\ndiff_guitarghl = 1\n".utf8)) == .alreadyPresent)
        #expect(try patcher.patch(Data("[song]\nDiff_GuitarGHL=\n".utf8)) == .alreadyPresent)
    }

    @Test("a diff_guitarghl in another section does not count")
    func keyInOtherSection() throws {
        let ini = "[song]\ndiff_guitar = 3\n[other]\ndiff_guitarghl = 9\n"
        #expect(try patched(ini) == "[song]\ndiff_guitar = 3\ndiff_guitarghl = 3\n[other]\ndiff_guitarghl = 9\n")
    }

    @Test("CRLF line endings and a BOM are kept byte for byte")
    func crlfAndBom() throws {
        let original = "\u{FEFF}[song]\r\nname = Synthetic\r\ndiff_guitar = 5\r\nicon = x\r\n"
        let expected = "\u{FEFF}[song]\r\nname = Synthetic\r\ndiff_guitar = 5\r\ndiff_guitarghl = 5\r\nicon = x\r\n"
        #expect(try patched(original) == expected)
    }

    @Test("a final line without a line break stays without one")
    func noFinalNewline() throws {
        #expect(try patched("[song]\ndiff_guitar = 2") == "[song]\ndiff_guitar = 2\ndiff_guitarghl = 2")
    }

    @Test("bytes that are not UTF-8 survive untouched")
    func nonUTF8Bytes() throws {
        var original = Data("[song]\nartist = Caf".utf8)
        original.append(0xE9)
        original.append(Data("\ndiff_guitar = 1\n".utf8))
        guard case .updated(let data, _) = try patcher.patch(original) else {
            Issue.record("not updated")
            return
        }
        #expect(data.starts(with: original.prefix(original.count - "\ndiff_guitar = 1\n".utf8.count)))
        #expect(try patcher.verify(patched: data, original: original) == "1")
    }

    @Test("a file without a [song] section is left alone")
    func noSongSection() throws {
        #expect(try patcher.patch(Data("[other]\ndiff_guitar = 1\n".utf8)) == .noSongSection)
    }

    @Test("star_power_note and multiplier_note are read from [song], and only when numeric")
    func starPowerNote() {
        func note(_ text: String) -> UInt8? { patcher.starPowerNote(in: Data(text.utf8)) }
        #expect(note("[song]\nstar_power_note = 116\n") == 116)
        #expect(note("[song]\nMultiplier_Note=103\r\n") == 103)
        #expect(note("[song]\nstar_power_note = x\n") == nil)
        #expect(note("[song]\nname = a\n") == nil)
        #expect(note("[other]\nstar_power_note = 116\n[song]\n") == nil)
    }

    @Test("patching twice adds nothing")
    func idempotent() throws {
        let once = try #require(try patched("[song]\ndiff_guitar = 4\n"))
        #expect(try patcher.patch(Data(once.utf8)) == .alreadyPresent)
    }

    @Test("verification accepts a good patch and rejects a damaged one")
    func verification() throws {
        let original = "[song]\nname = Synthetic\ndiff_guitar = 4\n"
        let good = try #require(try patched(original))
        #expect(try patcher.verify(patched: Data(good.utf8), original: Data(original.utf8)) == "4")
        let damaged = [
            good.replacingOccurrences(of: "Synthetic", with: "Other"),
            good.replacingOccurrences(of: "diff_guitarghl = 4", with: "diff_guitarghl = 5"),
            original,
        ]
        for text in damaged {
            #expect(throws: ConversionError.self) {
                try patcher.verify(patched: Data(text.utf8), original: Data(original.utf8))
            }
        }
    }
}
