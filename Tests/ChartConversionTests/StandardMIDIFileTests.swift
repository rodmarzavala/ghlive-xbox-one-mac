import Foundation
import Testing

@testable import ChartConversion

@Suite("Standard MIDI File reader and writer")
struct StandardMIDIFileTests {
    private typealias M = SyntheticMIDI

    @Test("variable-length quantities round-trip at their byte-length boundaries")
    func variableLengthQuantities() throws {
        let values: [UInt32] = [0, 1, 0x7F, 0x80, 0x3FFF, 0x4000, 0x1F_FFFF, 0x20_0000, 0x0FFF_FFFF]
        for value in values {
            let encoded = VariableLengthQuantity.encode(value)
            #expect(encoded == M.vlq(Int(value)))
            var reader = ByteReader(encoded)
            #expect(try reader.readVariableLengthQuantity() == value)
            #expect(reader.isAtEnd)
        }
    }

    @Test("a truncated or overlong quantity is rejected")
    func malformedQuantity() {
        var truncated = ByteReader([0x81])
        #expect(throws: MIDIError.self) { try truncated.readVariableLengthQuantity() }
        var overlong = ByteReader([0x81, 0x81, 0x81, 0x81, 0x01])
        #expect(throws: MIDIError.self) { try overlong.readVariableLengthQuantity() }
    }

    private var busyTrack: [UInt8] {
        M.track(
            M.name("PART GUITAR"),
            M.noteOn(96, delta: 0), M.runningNoteOn(97, delta: 5), M.runningNoteOn(98, delta: 5),
            M.sysex([0x7E, 0x00, 0x09, 0x01], delta: 2),
            M.meta(M.tempoType, [0x07, 0xA1, 0x20], delta: 1),
            M.noteOff(96, delta: 300), M.noteOff(97), M.noteOff(98),
            M.text("[ENHANCED_OPENS]", delta: 128),
            M.endOfTrack(delta: 16384))
    }

    @Test("read then write gives identical bytes: running status, sysex, meta, several tracks")
    func roundTrip() throws {
        let tempoTrack = M.track(M.meta(M.tempoType, [0x07, 0xA1, 0x20]), M.endOfTrack())
        let unknown = M.chunk("XFIH", [1, 2, 3])
        let data = M.file([tempoTrack, busyTrack, unknown, M.track(M.name("EVENTS"), M.endOfTrack())])
        let parsed = try StandardMIDIFile(data: data)
        #expect(parsed.serialized() == data)
    }

    @Test("a chunk type that is not valid UTF-8 round-trips byte for byte")
    func binaryChunkType() throws {
        let data = M.file([busyTrack, M.chunk([0xFF, 0xFE, 0x80, 0x81], [1, 2])])
        #expect(try StandardMIDIFile(data: data).serialized() == data)
    }

    @Test("bytes after the last chunk are kept")
    func trailingBytes() throws {
        let data = M.file([busyTrack]) + Data([0x00, 0x01])
        #expect(try StandardMIDIFile(data: data).serialized() == data)
    }

    @Test("a track re-encodes to the same bytes it was read from")
    func trackEventsRoundTrip() throws {
        let body = Array(busyTrack.dropFirst(8))
        let events = try MIDIEvent.decodeTrack(body)
        #expect(MIDIEvent.encodeTrack(events) == body)
    }

    @Test("running status is decoded to the effective status")
    func runningStatusDecoded() throws {
        let body = Array(M.track(M.noteOn(60), M.runningNoteOn(61, delta: 7)).dropFirst(8))
        let events = try MIDIEvent.decodeTrack(body)
        #expect(events.count == 2)
        #expect(events[1].delta == 7)
        #expect(events[1].kind == .channel(status: M.noteOnStatus, data: [61, M.defaultVelocity]))
        #expect(events[1].usesRunningStatus)
    }

    @Test("an event written without running status can be forced to carry its status")
    func explicitStatusEncoding() throws {
        let body = Array(M.track(M.noteOn(60), M.runningNoteOn(61)).dropFirst(8))
        let explicit = try MIDIEvent.decodeTrack(body).map { $0.withExplicitStatus() }
        #expect(MIDIEvent.encodeTrack(explicit) == Array(M.track(M.noteOn(60), M.noteOn(61)).dropFirst(8)))
    }

    @Test("the header exposes format, track count and track names")
    func structure() throws {
        let data = M.file([M.track(M.name("T"), M.endOfTrack()), busyTrack])
        let file = try StandardMIDIFile(data: data)
        #expect(file.format == 1)
        #expect(file.tracks.count == 2)
        #expect(try file.tracks.map { try $0.name() } == ["T", "PART GUITAR"])
    }

    @Test("appending a track updates the header's track count")
    func appendTrack() throws {
        var file = try StandardMIDIFile(data: M.file([busyTrack]))
        file.appendTrack(events: [])
        let reread = try StandardMIDIFile(data: file.serialized())
        #expect(reread.tracks.count == 2)
    }

    @Test(
        "malformed files are rejected with a MIDIError",
        arguments: [
            ("not a MIDI file", Data("RIFFxxxxxxxxxxxxxxxx".utf8)),
            ("empty", Data()),
            ("truncated chunk", Data(M.header(tracks: 1) + Array("MTrk".utf8) + M.be32(50) + [0x00])),
            ("data byte with no running status", M.file([M.chunk("MTrk", [0x00, 0x3C, 0x40])])),
        ]
    )
    func malformed(_ label: String, _ data: Data) throws {
        #expect(throws: MIDIError.self) {
            let file = try StandardMIDIFile(data: data)
            for track in file.tracks { _ = try track.events() }
        }
    }
}
