import ChartConversion
import Foundation
import Testing

@testable import GHLiveAppKit

@MainActor
private final class FakePicker: FolderPicking {
    var folder: URL?
    private(set) var askedCount = 0

    func pickSongsFolder() -> URL? {
        askedCount += 1
        return folder
    }
}

private final class FakeConverter: ChartConverting, @unchecked Sendable {
    private let lock = NSLock()
    private var folders: [URL] = []
    private var dryRuns: [Bool] = []
    private var mainThreadCalls = 0
    var outcome: Result<ConversionReport, any Error>
    /// When set, the conversion blocks (off the main thread) until it is signalled.
    let gate: DispatchSemaphore?

    init(outcome: Result<ConversionReport, any Error>, gate: DispatchSemaphore? = nil) {
        self.outcome = outcome
        self.gate = gate
    }

    var calls: Int { lock.withLock { folders.count } }
    var ranOnMainThread: Bool { lock.withLock { mainThreadCalls > 0 } }
    var lastFolder: URL? { lock.withLock { folders.last } }
    var lastDryRun: Bool? { lock.withLock { dryRuns.last } }

    func convert(folder: URL, dryRun: Bool) throws -> ConversionReport {
        lock.withLock {
            folders.append(folder)
            dryRuns.append(dryRun)
            if Thread.isMainThread { mainThreadCalls += 1 }
        }
        gate?.wait()
        return try outcome.get()
    }
}

private struct Boom: LocalizedError {
    var errorDescription: String? { "cannot read the folder" }
}

@MainActor
struct ChartConversionModelTests {
    private let songs = URL(fileURLWithPath: "/Users/someone/Songs", isDirectory: true)
    private let backup = URL(fileURLWithPath: "/Users/someone/Songs - backup 2025-01-01 120000", isDirectory: true)

    private func report(dryRun: Bool = false, results: [SongResult] = []) -> ConversionReport {
        ConversionReport(root: songs, isDryRun: dryRun, results: results, backupFolder: backup)
    }

    private func makeModel(
        picking folder: URL?, converting outcome: Result<ConversionReport, any Error>? = nil
    ) -> (model: ChartConversionModel, picker: FakePicker, converter: FakeConverter, revealed: Revealed) {
        let picker = FakePicker()
        picker.folder = folder
        let converter = FakeConverter(outcome: outcome ?? .success(report()))
        let revealed = Revealed()
        let model = ChartConversionModel(
            picker: picker, converter: converter, reveal: { revealed.urls.append($0) })
        return (model, picker, converter, revealed)
    }

    @MainActor final class Revealed { var urls: [URL] = [] }

    @Test("cancelling the open panel changes nothing")
    func panelCancelled() {
        let (model, picker, converter, _) = makeModel(picking: nil)
        #expect(model.chooseFolder() == false)
        #expect(model.state == .idle)
        #expect(picker.askedCount == 1)
        #expect(converter.calls == 0)
    }

    @Test("a chosen folder waits for the user's confirmation; nothing is converted yet")
    func folderChosen() {
        let (model, _, converter, _) = makeModel(picking: songs)
        #expect(model.chooseFolder() == true)
        #expect(model.state == .confirming(folder: songs))
        #expect(converter.calls == 0)
    }

    @Test("declining the confirmation goes back to idle without converting")
    func declined() {
        let (model, _, converter, _) = makeModel(picking: songs)
        model.chooseFolder()
        model.cancel()
        #expect(model.state == .idle)
        #expect(converter.calls == 0)
    }

    @Test("confirming converts the folder off the main thread and shows the report")
    func confirmed() async {
        let results = [SongResult(path: "A/notes.chart", outcome: .alreadyHasSixFret(songIni: .missing))]
        let (model, _, converter, _) = makeModel(picking: songs, converting: .success(report(results: results)))
        model.chooseFolder()
        await model.confirm()
        #expect(model.state == .finished(report(results: results)))
        #expect(converter.calls == 1)
        #expect(converter.lastFolder == songs)
        #expect(converter.lastDryRun == false)
        #expect(!converter.ranOnMainThread)
    }

    @Test("the state is converting while the work runs")
    func convertingState() async {
        let gate = DispatchSemaphore(value: 0)
        let picker = FakePicker()
        picker.folder = songs
        let model = ChartConversionModel(
            picker: picker, converter: FakeConverter(outcome: .success(report()), gate: gate), reveal: { _ in })
        model.chooseFolder()
        let work = Task { await model.confirm() }
        for _ in 0..<1000 where model.state != .converting(folder: songs) { await Task.yield() }
        #expect(model.state == .converting(folder: songs))
        #expect(model.chooseFolder() == false)
        gate.signal()
        await work.value
        #expect(model.state == .finished(report()))
    }

    @Test("a converter that throws shows the reason and nothing else")
    func failed() async {
        let (model, _, _, _) = makeModel(picking: songs, converting: .failure(Boom()))
        model.chooseFolder()
        await model.confirm()
        #expect(model.state == .failed("cannot read the folder"))
    }

    @Test("confirm does nothing unless a folder is waiting for confirmation")
    func confirmNeedsAFolder() async {
        let (model, _, converter, _) = makeModel(picking: songs)
        await model.confirm()
        #expect(model.state == .idle)
        #expect(converter.calls == 0)
    }

    @Test("a second confirmation after the run does not convert again")
    func confirmOnce() async {
        let (model, _, converter, _) = makeModel(picking: songs)
        model.chooseFolder()
        await model.confirm()
        await model.confirm()
        #expect(converter.calls == 1)
    }

    @Test("choosing again after a result starts over; dismissing returns to idle")
    func startOver() async {
        let (model, picker, _, _) = makeModel(picking: songs)
        model.chooseFolder()
        await model.confirm()
        model.dismiss()
        #expect(model.state == .idle)
        model.chooseFolder()
        #expect(model.state == .confirming(folder: songs))
        #expect(picker.askedCount == 2)
    }

    @Test("the backup folder of a result can be revealed")
    func revealsBackup() async {
        let (model, _, _, revealed) = makeModel(picking: songs)
        model.chooseFolder()
        await model.confirm()
        model.revealBackup()
        #expect(revealed.urls == [backup])
    }

    @Test("with no backup there is nothing to reveal")
    func noBackup() async {
        let none = ConversionReport(root: songs, isDryRun: false, results: [], backupFolder: nil)
        let (model, _, _, revealed) = makeModel(picking: songs, converting: .success(none))
        model.chooseFolder()
        await model.confirm()
        model.revealBackup()
        #expect(revealed.urls.isEmpty)
    }

    @Test("the confirmation says where the backup will go, next to the songs folder")
    func backupDescription() {
        #expect(
            ChartConversionCopy.backupLocation(for: songs)
                == "/Users/someone/Songs - backup <date and time>")
    }

    @Test("the model reports whether a window should be showing")
    func presenting() async {
        let (model, _, _, _) = makeModel(picking: songs)
        #expect(!model.isPresenting)
        model.chooseFolder()
        #expect(model.isPresenting)
        model.cancel()
        #expect(!model.isPresenting)
    }
}
