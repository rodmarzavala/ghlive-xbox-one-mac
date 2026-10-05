import Foundation
import Testing

@testable import ChartConversion

@Suite("MIDI (.mid) conversion")
struct MIDIChartConverterTests {
    private typealias M = SyntheticMIDI
    private let converter = MIDIChartConverter()

    private static let guitarName = "PART GUITAR"
    private static let ghlName = "PART GUITAR GHL"
    private static let enhancedOpens = "[ENHANCED_OPENS]"

    /// (5-fret green note, GHL open note) per difficulty. Spec: mid-format/Tracks/{5,6}-Fret-Guitar.md.
    private static let bases: [(green: Int, ghlOpen: Int)] = [(96, 94), (84, 82), (72, 70), (60, 58)]

    /// Green, Red, Yellow, Blue, Orange as GHL offsets from the open note: B1, B2, B3, W1, W2.
    private static let ghlOffsets = [4, 5, 6, 1, 2]

    private func guitarTrack(_ events: [UInt8]..., enhancedOpens: Bool = false, name: String = guitarName) -> [UInt8] {
        M.track(
            M.name(name), enhancedOpens ? M.text(Self.enhancedOpens) : [], events.flatMap { $0 }, M.endOfTrack())
    }

    private func source(_ guitar: [UInt8]) -> Data {
        M.file([M.track(M.meta(M.tempoType, [7, 0xA1, 0x20]), M.endOfTrack()), guitar])
    }

    private func convert(_ data: Data) throws -> StandardMIDIFile? {
        guard case .converted(let out, _) = try converter.convert(data) else { return nil }
        return try StandardMIDIFile(data: out)
    }

    private func ghlTrack(_ file: StandardMIDIFile) throws -> [MIDIEvent] {
        try #require(try file.tracks.first { try $0.name() == Self.ghlName }).events()
    }

    /// Absolute tick and pitch of every note-on with a velocity.
    private func pressed(_ events: [MIDIEvent]) -> [(tick: Int, note: Int)] {
        var tick = 0
        var result: [(Int, Int)] = []
        for event in events {
            tick += Int(event.delta)
            if case .channel(M.noteOnStatus, let data) = event.kind, data[1] > 0 { result.append((tick, Int(data[0]))) }
        }
        return result
    }

    /// The file with one track body swapped; chunk 0 is the header, so tracks start at 1.
    private func rebuilt(_ file: StandardMIDIFile, replacingChunk index: Int, with body: [UInt8]) -> Data {
        let chunks = file.chunks.enumerated().map { M.chunk($1.type, $0 == index ? body : $1.body) }
        return Data(chunks.flatMap { $0 })
    }

    private func totalTicks(_ events: [MIDIEvent]) -> Int { events.reduce(0) { $0 + Int($1.delta) } }

    @Test("every lane of every difficulty maps to its Clone Hero pair", arguments: bases)
    func laneMapping(green: Int, ghlOpen: Int) throws {
        let notes = (0..<5).map { M.note(green + $0, delta: 100) }
        let file = try #require(try convert(source(guitarTrack(notes[0], notes[1], notes[2], notes[3], notes[4]))))
        let notesOut = try pressed(ghlTrack(file)).map(\.note)
        #expect(notesOut == Self.ghlOffsets.map { ghlOpen + $0 })
    }

    @Test("force HOPO and force strum keep their note numbers", arguments: bases)
    func forceNotes(green: Int, ghlOpen: Int) throws {
        let track = guitarTrack(M.note(green + 5), M.note(green + 6))
        let file = try #require(try convert(source(track)))
        #expect(try pressed(ghlTrack(file)).map(\.note) == [green + 5, green + 6])
    }

    @Test("opens are mapped only when the track has [ENHANCED_OPENS]", arguments: bases)
    func opens(green: Int, ghlOpen: Int) throws {
        let withFlag = try #require(try convert(source(guitarTrack(M.note(green - 1), enhancedOpens: true))))
        #expect(try pressed(ghlTrack(withFlag)).map(\.note) == [ghlOpen])
        let without = try #require(try convert(source(guitarTrack(M.note(green - 1), M.note(green)))))
        #expect(try pressed(ghlTrack(without)).map(\.note) == [ghlOpen + 4])
    }

    @Test("solo, tap and star power markers are kept")
    func markers() throws {
        let track = guitarTrack(M.note(103), M.note(104), M.note(116))
        let file = try #require(try convert(source(track)))
        #expect(try pressed(ghlTrack(file)).map(\.note) == [103, 104, 116])
    }

    @Test("other notes are dropped but their time is carried: later notes stay where they were")
    func animationNotesDropped() throws {
        let track = guitarTrack(
            M.note(96, delta: 10), M.note(40, delta: 50), M.note(12, delta: 20, length: 7), M.note(97, delta: 30),
            M.note(127, delta: 5))
        let original = source(track)
        let file = try #require(try convert(original))
        let sourceEvents = try #require(try StandardMIDIFile(data: original).tracks.last).events()
        let ghl = try ghlTrack(file)
        #expect(pressed(ghl).map(\.note) == [98, 99])
        #expect(pressed(ghl).map(\.tick) == [10, 137])
        #expect(totalTicks(ghl) == totalTicks(sourceEvents))
    }

    @Test("text, sysex and meta events are kept; only the track name changes")
    func nonNoteEventsKept() throws {
        let track = M.track(
            M.name(Self.guitarName), M.sysex([0x7E, 0x00], delta: 3), M.text("[some_event]", delta: 4),
            M.meta(M.tempoType, [1, 2, 3], delta: 5), M.note(96, delta: 6), M.endOfTrack(delta: 7))
        let file = try #require(try convert(source(track)))
        let events = try ghlTrack(file)
        let original = try MIDIEvent.decodeTrack(Array(track.dropFirst(8)))
        #expect(events.count == original.count)
        #expect(events[0].kind == .meta(type: M.trackNameType, payload: Array(Self.ghlName.utf8)))
        #expect(events.dropFirst().filter(Self.isNotChannel) == Array(original.dropFirst()).filter(Self.isNotChannel))
    }

    private static func isNotChannel(_ event: MIDIEvent) -> Bool {
        if case .channel = event.kind { return false }
        return true
    }

    @Test("the original tracks stay byte for byte and the header counts the new track")
    func originalsUntouched() throws {
        let track = guitarTrack(M.note(96))
        let original = source(track)
        let out = try #require(try convert(original))
        let before = try StandardMIDIFile(data: original)
        #expect(Array(out.tracks.prefix(2)) == before.tracks)
        #expect(out.tracks.count == 3)
        #expect(out.chunks[0].body[3] == 3)
    }

    @Test("a file with PART GUITAR GHL is already done, one without PART GUITAR has nothing to convert")
    func skipReasons() throws {
        let both = M.file([guitarTrack(M.note(96)), guitarTrack(M.note(96), name: Self.ghlName)])
        #expect(try converter.convert(both) == .alreadyHasSixFret)
        let none = M.file([guitarTrack(M.note(96), name: "PART BASS")])
        #expect(try converter.convert(none) == .noFiveFretTrack)
    }

    @Test("running twice adds nothing")
    func idempotent() throws {
        let out = try #require(try converter.convert(source(guitarTrack(M.note(96)))))
        guard case .converted(let data, let added) = out else { return }
        #expect(added == [Self.ghlName])
        #expect(try converter.convert(data) == .alreadyHasSixFret)
    }

    @Test("only type 1 files are accepted")
    func formatZero() {
        let data = M.file(format: 0, [guitarTrack(M.note(96))])
        #expect(throws: MIDIError.unsupportedFormat(0)) { try converter.convert(data) }
    }

    @Test("running status in the source is handled and the new track is written with explicit status")
    func runningStatus() throws {
        let track = M.track(
            M.name(Self.guitarName), M.noteOn(96), M.runningNoteOn(97, delta: 4), M.noteOff(96, delta: 5),
            M.noteOff(97), M.endOfTrack())
        let file = try #require(try convert(source(track)))
        #expect(try pressed(ghlTrack(file)).map(\.note) == [98, 99])
        #expect(try ghlTrack(file).allSatisfy { !$0.usesRunningStatus })
    }

    @Test("a note-on with velocity 0 is a release, not a note")
    func velocityZero() throws {
        let track = M.track(
            M.name(Self.guitarName), M.noteOn(96), M.noteOn(96, delta: 10, velocity: 0), M.endOfTrack())
        let file = try #require(try convert(source(track)))
        let ghl = try ghlTrack(file)
        #expect(pressed(ghl).count == 1)
        #expect(totalTicks(ghl) == 10)
    }

    @Test("dropped notes whose delta times add up past the VLQ limit fail instead of crashing")
    func deltaOverflow() throws {
        let maxDelta = Int(VariableLengthQuantity.maxValue)
        let dropped = (0..<20).map { _ in M.note(40, delta: maxDelta, length: 0) }
        let track = M.track(M.name(Self.guitarName), dropped.flatMap { $0 }, M.note(96), M.endOfTrack())
        #expect(throws: MIDIError.deltaTooLarge) { try converter.convert(source(track)) }
    }

    @Test("a carried delta that still fits is written, up to the limit")
    func deltaAtTheLimit() throws {
        let maxDelta = Int(VariableLengthQuantity.maxValue)
        let track = M.track(M.name(Self.guitarName), M.note(40, delta: maxDelta, length: 0), M.note(96), M.endOfTrack())
        let file = try #require(try convert(source(track)))
        #expect(try pressed(ghlTrack(file)).map(\.tick) == [maxDelta])
    }

    // MARK: Verification

    private func converted(_ original: Data) throws -> Data {
        guard case .converted(let data, _) = try converter.convert(original) else { throw ConversionError.notUTF8 }
        return data
    }

    @Test("verification counts the notes of a good conversion")
    func verifiesGood() throws {
        let original = source(guitarTrack(M.note(96), M.note(97), M.note(40), M.note(103)))
        #expect(try converter.verify(converted: try converted(original), original: original) == 3)
    }

    @Test("verification catches a changed note, a missing note and a shifted time")
    func catchesCorruption() throws {
        let original = source(guitarTrack(M.note(96, delta: 10), M.note(97, delta: 10)))
        let good = try StandardMIDIFile(data: try converted(original))
        let ghlIndex = good.chunks.count - 1
        let events = try ghlTrack(good)
        var wrongNote = events
        wrongNote[1].kind = .channel(status: M.noteOnStatus, data: [60, M.defaultVelocity])
        var missing = events
        missing.remove(at: 1)
        var shifted = events
        shifted[shifted.count - 1].delta += 1
        for damaged in [wrongNote, missing, shifted] {
            let file = rebuilt(good, replacingChunk: ghlIndex, with: MIDIEvent.encodeTrack(damaged))
            #expect(throws: ConversionError.self) { try converter.verify(converted: file, original: original) }
        }
    }

    @Test("verification catches a changed original track")
    func catchesChangedOriginal() throws {
        let original = source(guitarTrack(M.note(96)))
        let good = try StandardMIDIFile(data: try converted(original))
        let file = rebuilt(good, replacingChunk: 2, with: [0x00])
        #expect(throws: ConversionError.self) { try converter.verify(converted: file, original: original) }
    }
}
