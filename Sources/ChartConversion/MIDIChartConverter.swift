import Foundation

/// Appends a `PART GUITAR GHL` track derived from `PART GUITAR`. Existing tracks are never rewritten.
public struct MIDIChartConverter: ChartFormatConverter {
    static let fiveFretTrackName = "PART GUITAR"
    static let sixFretTrackName = "PART GUITAR GHL"
    static let enhancedOpensEvent = "[ENHANCED_OPENS]"
    static let supportedFormat = 1
    private static let textMetaTypes: ClosedRange<UInt8> = 0x01...0x07
    private static let headerTrackCountRange = 2..<4

    public init() {}

    public func convert(_ data: Data) throws -> ConversionAttempt {
        var file = try StandardMIDIFile(data: data)
        guard file.format == Self.supportedFormat else { throw MIDIError.unsupportedFormat(file.format) }
        let names = try file.tracks.map { try $0.name() }
        if names.contains(Self.sixFretTrackName) { return .alreadyHasSixFret }
        guard let index = names.firstIndex(of: Self.fiveFretTrackName) else { return .noFiveFretTrack }
        let source = try file.tracks[index].events()
        file.appendTrack(events: Self.sixFretEvents(from: source))
        return .converted(file.serialized(), addedTracks: [Self.sixFretTrackName])
    }

    public func verify(converted: Data, original: Data) throws -> Int {
        let output = try StandardMIDIFile(data: converted)
        try Self.verifyOriginalsUntouched(output: output, original: try StandardMIDIFile(data: original))
        let names = try output.tracks.map { try $0.name() }
        guard let fiveIndex = names.firstIndex(of: Self.fiveFretTrackName),
            let sixIndex = names.firstIndex(of: Self.sixFretTrackName)
        else { throw ConversionError.verificationFailed("the output lacks a guitar track or its 6-fret copy") }
        let five = try output.tracks[fiveIndex].events()
        let six = try output.tracks[sixIndex].events()
        let map = MIDINoteMap.make(enhancedOpens: Self.hasEnhancedOpens(five))
        var expected: [UInt8: Int] = [:]
        for (note, count) in Self.pressedCounts(five) {
            if let mapped = map[note] { expected[mapped, default: 0] += count }
        }
        let actual = Self.pressedCounts(six).filter { Set(map.values).contains($0.key) }
        guard expected == actual else {
            throw ConversionError.verificationFailed("note counts differ between PART GUITAR and PART GUITAR GHL")
        }
        guard Self.totalTicks(five) == Self.totalTicks(six) else {
            throw ConversionError.verificationFailed("track lengths differ")
        }
        return actual.values.reduce(0, +)
    }

    // MARK: Conversion

    /// The notes are mapped, everything else is copied. A dropped note's delta time moves to the next kept
    /// event, so the notes that stay keep their tick and the track keeps its length. Events are written with
    /// an explicit status byte because dropping an event could leave a running status without its source.
    static func sixFretEvents(from source: [MIDIEvent]) -> [MIDIEvent] {
        let map = MIDINoteMap.make(enhancedOpens: hasEnhancedOpens(source))
        var converted: [MIDIEvent] = []
        var carried: UInt32 = 0
        for event in source {
            guard let kept = mapped(event, with: map) else {
                carried += event.delta
                continue
            }
            converted.append(kept.withDelta(kept.delta + carried).withExplicitStatus())
            carried = 0
        }
        return converted
    }

    private static func mapped(_ event: MIDIEvent, with map: [UInt8: UInt8]) -> MIDIEvent? {
        switch event.kind {
        case .meta(MIDIEvent.trackNameType, _):
            var renamed = event
            renamed.kind = .meta(type: MIDIEvent.trackNameType, payload: Array(sixFretTrackName.utf8))
            return renamed
        case .channel(let status, let data) where isNoteEvent(status):
            guard let note = map[data[0]] else { return nil }
            var remapped = event
            remapped.kind = .channel(status: status, data: [note] + data.dropFirst())
            return remapped
        default:
            return event
        }
    }

    private static let noteOffType: UInt8 = 0x80
    private static let noteOnType: UInt8 = 0x90

    private static func isNoteEvent(_ status: UInt8) -> Bool {
        let type = status & MIDIEvent.typeMask
        return type == noteOffType || type == noteOnType
    }

    private static func hasEnhancedOpens(_ events: [MIDIEvent]) -> Bool {
        events.contains { event in
            guard case .meta(let type, let payload) = event.kind, textMetaTypes.contains(type) else { return false }
            let text = String(decoding: payload, as: UTF8.self).trimmingCharacters(in: .whitespaces)
            return text == enhancedOpensEvent || text == String(enhancedOpensEvent.dropFirst().dropLast())
        }
    }

    // MARK: Verification

    private static func verifyOriginalsUntouched(output: StandardMIDIFile, original: StandardMIDIFile) throws {
        guard output.chunks.count == original.chunks.count + 1 else {
            throw ConversionError.verificationFailed("expected exactly one added track")
        }
        guard Array(output.chunks.dropFirst().prefix(original.chunks.count - 1)) == Array(original.chunks.dropFirst())
        else { throw ConversionError.verificationFailed("an original track changed") }
        var outputHeader = output.chunks[0].body
        var originalHeader = original.chunks[0].body
        outputHeader.removeSubrange(headerTrackCountRange)
        originalHeader.removeSubrange(headerTrackCountRange)
        guard outputHeader == originalHeader else { throw ConversionError.verificationFailed("the header changed") }
    }

    private static func pressedCounts(_ events: [MIDIEvent]) -> [UInt8: Int] {
        var counts: [UInt8: Int] = [:]
        for event in events {
            guard case .channel(let status, let data) = event.kind, status & MIDIEvent.typeMask == noteOnType,
                data[1] > 0
            else { continue }
            counts[data[0], default: 0] += 1
        }
        return counts
    }

    private static func totalTicks(_ events: [MIDIEvent]) -> UInt64 {
        events.reduce(0) { $0 + UInt64($1.delta) }
    }
}
