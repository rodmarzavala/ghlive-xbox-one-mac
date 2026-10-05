import Foundation

/// Hand-assembled Standard MIDI File bytes, independent of the library's own writer, so the round-trip and
/// converter tests do not check the code against itself. Every song here is synthetic.
enum SyntheticMIDI {
    static let ticksPerQuarter: UInt16 = 480
    static let noteOnStatus: UInt8 = 0x90
    static let noteOffStatus: UInt8 = 0x80
    static let metaStatus: UInt8 = 0xFF
    static let sysexStatus: UInt8 = 0xF0
    static let trackNameType: UInt8 = 0x03
    static let textType: UInt8 = 0x01
    static let tempoType: UInt8 = 0x51
    static let endOfTrackType: UInt8 = 0x2F
    static let defaultVelocity: UInt8 = 100
    static let continuationBit: UInt8 = 0x80
    static let sevenBitMask: Int = 0x7F

    static func vlq(_ value: Int) -> [UInt8] {
        var groups: [UInt8] = [UInt8(value & sevenBitMask)]
        var rest = value >> 7
        while rest > 0 {
            groups.append(UInt8(rest & sevenBitMask) | continuationBit)
            rest >>= 7
        }
        return groups.reversed()
    }

    static func be32(_ value: Int) -> [UInt8] {
        [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    static func be16(_ value: Int) -> [UInt8] {
        [UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    static func header(format: Int = 1, tracks: Int) -> [UInt8] {
        Array("MThd".utf8) + be32(6) + be16(format) + be16(tracks) + be16(Int(ticksPerQuarter))
    }

    static func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
        Array(type.utf8) + be32(body.count) + body
    }

    static func track(_ events: [UInt8]...) -> [UInt8] {
        chunk("MTrk", events.flatMap { $0 })
    }

    static func file(format: Int = 1, _ chunks: [[UInt8]]) -> Data {
        Data(header(format: format, tracks: chunks.count) + chunks.flatMap { $0 })
    }

    static func meta(_ type: UInt8, _ payload: [UInt8], delta: Int = 0) -> [UInt8] {
        vlq(delta) + [metaStatus, type] + vlq(payload.count) + payload
    }

    static func name(_ name: String, delta: Int = 0) -> [UInt8] {
        meta(trackNameType, Array(name.utf8), delta: delta)
    }

    static func text(_ text: String, delta: Int = 0) -> [UInt8] {
        meta(textType, Array(text.utf8), delta: delta)
    }

    static func endOfTrack(delta: Int = 0) -> [UInt8] {
        meta(endOfTrackType, [], delta: delta)
    }

    static func sysex(_ payload: [UInt8], delta: Int = 0) -> [UInt8] {
        vlq(delta) + [sysexStatus] + vlq(payload.count + 1) + payload + [0xF7]
    }

    static func noteOn(_ note: Int, delta: Int = 0, velocity: UInt8 = defaultVelocity) -> [UInt8] {
        vlq(delta) + [noteOnStatus, UInt8(note), velocity]
    }

    static func noteOff(_ note: Int, delta: Int = 0) -> [UInt8] {
        vlq(delta) + [noteOffStatus, UInt8(note), 0]
    }

    /// A note-on written with running status: the status byte is left out.
    static func runningNoteOn(_ note: Int, delta: Int = 0, velocity: UInt8 = defaultVelocity) -> [UInt8] {
        vlq(delta) + [UInt8(note), velocity]
    }

    /// A pressed note and its release, `length` ticks later.
    static func note(_ note: Int, delta: Int = 0, length: Int = 10) -> [UInt8] {
        noteOn(note, delta: delta) + noteOff(note, delta: length)
    }
}
