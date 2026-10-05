import Foundation

/// `.chart` note numbers of the lead 5-fret track.
/// Spec: chart-format/Tracks/5-Fret-Guitar.md, "Note and Modifier Types".
enum FiveFretChartNote: Int {
    case green = 0
    case red = 1
    case yellow = 2
    case blue = 3
    case orange = 4
    case forceFlip = 5
    case tap = 6
    case open = 7
}

/// `.chart` note numbers of the 6-fret (GHL) guitar track.
/// Spec: chart-format/Tracks/6-Fret-Guitar.md, "Note and Modifier Types".
enum SixFretChartNote: Int {
    case white1 = 0
    case white2 = 1
    case white3 = 2
    case black1 = 3
    case black2 = 4
    case forceFlip = 5
    case tap = 6
    case open = 7
    case black3 = 8
}

/// Clone Hero pairs the 5-fret and the 6-fret controls: Green|Black 1, Red|Black 2, Yellow|Black 3,
/// Blue|White 1, Orange|White 2. Mapping lanes the same way makes a converted chart play like the original
/// with the same key bindings. White 3 has no 5-fret counterpart and stays unused.
enum ChartLaneMap {
    /// The 6-fret note for a 5-fret `.chart` note number; nil for numbers the 5-fret format does not define.
    static func sixFretNote(forFiveFret number: Int) -> Int? {
        guard let note = FiveFretChartNote(rawValue: number) else { return nil }
        let mapped: SixFretChartNote =
            switch note {
            case .green: .black1
            case .red: .black2
            case .yellow: .black3
            case .blue: .white1
            case .orange: .white2
            case .forceFlip: .forceFlip
            case .tap: .tap
            case .open: .open
            }
        return mapped.rawValue
    }
}
