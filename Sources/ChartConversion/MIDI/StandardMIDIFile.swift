import Foundation

/// A chunk exactly as stored: four-character type and body. Unknown chunk types survive a round trip.
struct MIDIChunk: Equatable, Sendable {
    static let headerType: [UInt8] = Array("MThd".utf8)
    static let trackType: [UInt8] = Array("MTrk".utf8)
    static let typeLength = 4

    var type: [UInt8]
    var body: [UInt8]
}

struct MIDITrack: Equatable, Sendable {
    let body: [UInt8]

    func events() throws -> [MIDIEvent] {
        try MIDIEvent.decodeTrack(body)
    }

    /// The first track-name meta event; nil when the track has none.
    func name() throws -> String? {
        for event in try events() {
            guard case .meta(MIDIEvent.trackNameType, let payload) = event.kind else { continue }
            return String(bytes: payload, encoding: .utf8) ?? String(bytes: payload, encoding: .isoLatin1)
        }
        return nil
    }
}

/// A Standard MIDI File as a list of chunks. Reading keeps every chunk body (and any bytes after the last
/// chunk) verbatim, so writing a file back reproduces it byte for byte; only tracks that are deliberately
/// added are encoded.
struct StandardMIDIFile: Equatable, Sendable {
    private static let minimumHeaderLength = 6
    private static let formatOffset = 0
    private static let trackCountOffset = 2
    /// The two header bytes that count the tracks.
    static let trackCountRange = trackCountOffset..<trackCountOffset + 2
    private static let byteBits = 8
    private static let byteMask = 0xFF

    private(set) var chunks: [MIDIChunk]
    private let trailingBytes: [UInt8]

    init(data: Data) throws {
        var reader = ByteReader([UInt8](data))
        var chunks: [MIDIChunk] = []
        while reader.remaining >= MIDIChunk.typeLength + 4 {
            chunks.append(try Self.readChunk(&reader))
        }
        guard chunks.first?.type == MIDIChunk.headerType, chunks[0].body.count >= Self.minimumHeaderLength else {
            throw MIDIError.notAMIDIFile
        }
        self.chunks = chunks
        trailingBytes = try reader.readBytes(reader.remaining, "trailing bytes")
    }

    private static func readChunk(_ reader: inout ByteReader) throws -> MIDIChunk {
        let typeBytes = try reader.readBytes(MIDIChunk.typeLength, "a chunk type")
        let length = try reader.readUInt32("a chunk length")
        let label = String(decoding: typeBytes, as: UTF8.self)
        return MIDIChunk(type: typeBytes, body: try reader.readBytes(Int(length), "a \(label) chunk"))
    }

    var format: Int { word(at: Self.formatOffset) }

    var tracks: [MIDITrack] {
        chunks.filter { $0.type == MIDIChunk.trackType }.map { MIDITrack(body: $0.body) }
    }

    private func word(at offset: Int) -> Int {
        chunks[0].body[offset...offset + 1].reduce(0) { $0 << Self.byteBits | Int($1) }
    }

    /// Appends a track at the end of the file and counts it in the header.
    mutating func appendTrack(events: [MIDIEvent]) {
        chunks.append(MIDIChunk(type: MIDIChunk.trackType, body: MIDIEvent.encodeTrack(events)))
        let count = tracks.count
        chunks[0].body[Self.trackCountOffset] = UInt8(count >> Self.byteBits & Self.byteMask)
        chunks[0].body[Self.trackCountOffset + 1] = UInt8(count & Self.byteMask)
    }

    func serialized() -> Data {
        var bytes: [UInt8] = []
        for chunk in chunks {
            bytes += chunk.type
            bytes += Self.bigEndian(UInt32(chunk.body.count))
            bytes += chunk.body
        }
        return Data(bytes + trailingBytes)
    }

    private static func bigEndian(_ value: UInt32) -> [UInt8] {
        (0..<4).reversed().map { UInt8(value >> UInt32($0 * byteBits) & UInt32(byteMask)) }
    }
}
