import GuitarInput
import KeyMapping

extension Control {
    /// The name shown in Settings and read out by VoiceOver.
    public var friendlyName: String {
        switch self {
        case .black1: "Black 1"
        case .black2: "Black 2"
        case .black3: "Black 3"
        case .white1: "White 1"
        case .white2: "White 2"
        case .white3: "White 3"
        case .strumUp: "Strum up"
        case .strumDown: "Strum down"
        case .heroPower: "Hero Power"
        case .pause: "Pause"
        case .ghtv: "GHTV"
        case .dpadUp: "D-pad up"
        case .dpadDown: "D-pad down"
        case .dpadLeft: "D-pad left"
        case .dpadRight: "D-pad right"
        case .whammy: "Whammy bar"
        case .tilt: "Tilt"
        }
    }
}

/// Controls grouped the way they are laid out on the guitar, for the Settings list.
public struct ControlGroup: Equatable, Sendable, Identifiable {
    public let title: String
    public let controls: [Control]

    public var id: String { title }

    public static let all: [ControlGroup] = [
        ControlGroup(title: "Frets", controls: [.black1, .black2, .black3, .white1, .white2, .white3]),
        ControlGroup(title: "Strum bar", controls: [.strumUp, .strumDown]),
        ControlGroup(title: "Buttons", controls: [.heroPower, .pause, .ghtv]),
        ControlGroup(title: "D-pad", controls: [.dpadUp, .dpadDown, .dpadLeft, .dpadRight]),
        ControlGroup(title: "Whammy bar and tilt", controls: [.whammy, .tilt]),
    ]
}

/// How a key is written on screen.
public enum KeyLabel {
    private static let symbols: [String: String] = [
        "up": "\u{2191}", "down": "\u{2193}", "left": "\u{2190}", "right": "\u{2192}",
        "return": "Return", "tab": "Tab", "space": "Space", "escape": "Esc",
    ]

    public static func text(for key: KeyCode) -> String {
        guard let name = key.name else { return "Key \(key.rawValue)" }
        return symbols[name] ?? name.uppercased()
    }
}
