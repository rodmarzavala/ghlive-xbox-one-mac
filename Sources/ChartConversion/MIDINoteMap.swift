import Foundation

/// MIDI note numbers of the lead guitar tracks.
/// Specs: mid-format/Tracks/5-Fret-Guitar.md (`PART GUITAR`) and mid-format/Tracks/6-Fret-Guitar.md
/// (`PART GUITAR GHL`), "Track Notes".
enum MIDIGuitarDifficulty: CaseIterable {
    case expert
    case hard
    case medium
    case easy

    /// The Green note; Red, Yellow, Blue and Orange follow one semitone apart. The Open note is one below.
    var fiveFretGreen: UInt8 {
        switch self {
        case .expert: 96
        case .hard: 84
        case .medium: 72
        case .easy: 60
        }
    }

    /// The Open note of the 6-fret track; the other lanes are offsets above it.
    var sixFretOpen: UInt8 {
        switch self {
        case .expert: 94
        case .hard: 82
        case .medium: 70
        case .easy: 58
        }
    }
}

/// Offsets from the 6-fret Open note (mid-format/Tracks/6-Fret-Guitar.md).
enum SixFretMIDIOffset: UInt8 {
    case open = 0
    case white1 = 1
    case white2 = 2
    case white3 = 3
    case black1 = 4
    case black2 = 5
    case black3 = 6
}

enum MIDIGuitarMarker {
    static let solo: UInt8 = 103
    static let tap: UInt8 = 104
    static let starPower: UInt8 = 116
    static let all: [UInt8] = [solo, tap, starPower]
}

enum MIDINoteMap {
    /// 5-fret lanes in note order (Green, Red, Yellow, Blue, Orange) and the 6-fret lane each one plays as:
    /// Clone Hero's control pairing, the same as for `.chart`.
    private static let laneTargets: [SixFretMIDIOffset] = [.black1, .black2, .black3, .white1, .white2]
    private static let forceHOPOOffset: UInt8 = 5
    private static let forceStrumOffset: UInt8 = 6

    /// 5-fret note to 6-fret note. Notes that are not in it are dropped: that is Rock Band hand animations,
    /// vocals harmonies, trill lanes and the like, which would otherwise play as notes.
    /// `enhancedOpens` maps the 5-fret open note (Green - 1), which only counts as a note when the track
    /// carries the `[ENHANCED_OPENS]` text event.
    static func make(enhancedOpens: Bool) -> [UInt8: UInt8] {
        var map: [UInt8: UInt8] = [:]
        for difficulty in MIDIGuitarDifficulty.allCases {
            let green = difficulty.fiveFretGreen
            let open = difficulty.sixFretOpen
            for (lane, target) in laneTargets.enumerated() { map[green + UInt8(lane)] = open + target.rawValue }
            for force in [forceHOPOOffset, forceStrumOffset] { map[green + force] = green + force }
            if enhancedOpens { map[green - 1] = open + SixFretMIDIOffset.open.rawValue }
        }
        for marker in MIDIGuitarMarker.all { map[marker] = marker }
        return map
    }
}
