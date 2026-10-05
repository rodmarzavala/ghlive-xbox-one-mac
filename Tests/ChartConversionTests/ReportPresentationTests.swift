import Foundation
import Testing

@testable import ChartConversion

@Suite("Report wording")
struct ReportPresentationTests {
    private func result(_ outcome: SongOutcome, path: String = "Pack/Song/notes.chart") -> SongResult {
        SongResult(path: path, outcome: outcome)
    }

    @Test("a converted song names the added tracks, the verified notes and the song.ini change")
    func converted() {
        let outcome = SongOutcome.converted(
            addedTracks: ["ExpertGHLGuitar", "HardGHLGuitar"], notes: 12, songIni: .added(value: "3"))
        #expect(
            result(outcome).line(dryRun: false)
                == "converted: Pack/Song/notes.chart (added ExpertGHLGuitar, HardGHLGuitar; 12 notes verified; song.ini: added diff_guitarghl = 3)"
        )
        #expect(result(outcome).line(dryRun: true).hasPrefix("would convert: Pack/Song/notes.chart"))
    }

    @Test(
        "every song.ini outcome has wording",
        arguments: [
            (SongIniChange.alreadyPresent, "song.ini: diff_guitarghl already set"),
            (.missing, "song.ini: none to update"),
            (.failed("disk full"), "song.ini: could not update (disk full)"),
        ])
    func iniWording(change: SongIniChange, text: String) {
        let outcome = SongOutcome.converted(addedTracks: ["PART GUITAR GHL"], notes: 1, songIni: change)
        #expect(result(outcome).line(dryRun: false).contains(text))
    }

    @Test("skips and failures read plainly")
    func others() {
        #expect(
            result(.alreadyHasSixFret).line(dryRun: false)
                == "skipped: Pack/Song/notes.chart (already has a 6-fret track)")
        #expect(
            result(.noFiveFretTrack).line(dryRun: false) == "skipped: Pack/Song/notes.chart (no 5-fret guitar track)")
        #expect(
            result(.unsupportedFormat).line(dryRun: false)
                == "skipped: Pack/Song/notes.chart (.sng is not supported yet)")
        #expect(result(.failed("boom")).line(dryRun: false) == "failed: Pack/Song/notes.chart (boom)")
    }

    @Test("the summary counts each kind, and says whether it was a dry run")
    func summary() {
        let results = [
            result(.converted(addedTracks: ["X"], notes: 1, songIni: .missing)), result(.alreadyHasSixFret),
            result(.unsupportedFormat), result(.failed("x")),
        ]
        let root = URL(fileURLWithPath: "/songs")
        let real = ConversionReport(root: root, isDryRun: false, results: results, backupFolder: nil)
        #expect(real.summary == "1 converted, 2 skipped, 1 failed")
        let dry = ConversionReport(root: root, isDryRun: true, results: results, backupFolder: nil)
        #expect(dry.summary == "1 would be converted, 2 skipped, 1 failed")
    }
}
