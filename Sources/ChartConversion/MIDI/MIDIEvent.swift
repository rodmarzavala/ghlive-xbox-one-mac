import Foundation

/// One track event: a delta time and a channel, sysex or meta message. Anything the converter does not
/// interpret is kept as its raw payload and written back unchanged.
struct MIDIEvent: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case channel(status: UInt8, data: [UInt8])
        case sysex(status: UInt8, payload: [UInt8])
        case meta(type: UInt8, payload: [UInt8])
    }

    static let metaStatus: UInt8 = 0xFF
    static let sysexStatus: UInt8 = 0xF0
    static let sysexEscapeStatus: UInt8 = 0xF7
    static let trackNameType: UInt8 = 0x03
    static let firstStatusByte: UInt8 = 0x80
    static let firstSystemStatus: UInt8 = 0xF0
    static let channelMask: UInt8 = 0x0F
    static let typeMask: UInt8 = 0xF0
    static let programChangeType: UInt8 = 0xC0
    static let channelPressureType: UInt8 = 0xD0

    var delta: UInt32
    var kind: Kind
    /// The status byte was left out in the file (the previous channel status applies).
    var usesRunningStatus = false

    func withExplicitStatus() -> MIDIEvent {
        MIDIEvent(delta: delta, kind: kind, usesRunningStatus: false)
    }

    func withDelta(_ delta: UInt32) -> MIDIEvent {
        MIDIEvent(delta: delta, kind: kind, usesRunningStatus: usesRunningStatus)
    }

    // MARK: Decoding

    static func decodeTrack(_ body: [UInt8]) throws -> [MIDIEvent] {
        var reader = ByteReader(body)
        var events: [MIDIEvent] = []
        var runningStatus: UInt8?
        while !reader.isAtEnd {
            let delta = try reader.readVariableLengthQuantity()
            let event = try decodeEvent(delta: delta, reader: &reader, runningStatus: &runningStatus)
            events.append(event)
        }
        return events
    }

    private static func decodeEvent(
        delta: UInt32, reader: inout ByteReader, runningStatus: inout UInt8?
    ) throws -> MIDIEvent {
        let first = try reader.readByte("an event")
        guard first >= firstStatusByte else {
            guard let status = runningStatus else { throw MIDIError.missingRunningStatus }
            let data = try readChannelData(status: status, firstDataByte: first, reader: &reader)
            return MIDIEvent(delta: delta, kind: .channel(status: status, data: data), usesRunningStatus: true)
        }
        switch first {
        case metaStatus:
            let type = try reader.readByte("a meta event")
            let length = try reader.readVariableLengthQuantity()
            let payload = try reader.readBytes(Int(length), "a meta event")
            return MIDIEvent(delta: delta, kind: .meta(type: type, payload: payload))
        case sysexStatus, sysexEscapeStatus:
            let length = try reader.readVariableLengthQuantity()
            let payload = try reader.readBytes(Int(length), "a system exclusive event")
            return MIDIEvent(delta: delta, kind: .sysex(status: first, payload: payload))
        case firstSystemStatus...:
            throw MIDIError.unsupportedStatus(first)
        default:
            runningStatus = first
            let firstData = try reader.readByte("a channel event")
            let data = try readChannelData(status: first, firstDataByte: firstData, reader: &reader)
            return MIDIEvent(delta: delta, kind: .channel(status: first, data: data))
        }
    }

    private static func readChannelData(status: UInt8, firstDataByte: UInt8, reader: inout ByteReader) throws
        -> [UInt8]
    {
        guard dataByteCount(status: status) == 2 else { return [firstDataByte] }
        return [firstDataByte, try reader.readByte("a channel event")]
    }

    private static func dataByteCount(status: UInt8) -> Int {
        let type = status & typeMask
        return type == programChangeType || type == channelPressureType ? 1 : 2
    }

    // MARK: Encoding

    static func encodeTrack(_ events: [MIDIEvent]) -> [UInt8] {
        events.flatMap { $0.encoded() }
    }

    func encoded() -> [UInt8] {
        let time = VariableLengthQuantity.encode(delta)
        switch kind {
        case .channel(let status, let data):
            return time + (usesRunningStatus ? [] : [status]) + data
        case .sysex(let status, let payload):
            return time + [status] + VariableLengthQuantity.encode(UInt32(payload.count)) + payload
        case .meta(let type, let payload):
            return time + [Self.metaStatus, type] + VariableLengthQuantity.encode(UInt32(payload.count)) + payload
        }
    }
}
