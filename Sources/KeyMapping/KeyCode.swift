import Foundation

/// A macOS virtual key code (physical key on an ANSI layout).
public struct KeyCode: Hashable, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    /// Case-insensitive lookup by the names used in keymap files.
    public static func named(_ name: String) -> KeyCode? {
        codesByName[name.lowercased()].map(KeyCode.init(rawValue:))
    }

    public var name: String? { Self.namesByCode[rawValue] }

    public static var allNames: [String] { table.map(\.name) }

    // Carbon HIToolbox Events.h: kVK_ANSI_A ... kVK_ANSI_9, kVK_Return, kVK_Tab, kVK_Space, kVK_Escape,
    // kVK_LeftArrow ... kVK_UpArrow and kVK_F1 ... kVK_F12.
    private static let table: [(name: String, code: UInt16)] = [
        ("a", 0x00), ("s", 0x01), ("d", 0x02), ("f", 0x03), ("h", 0x04), ("g", 0x05), ("z", 0x06),
        ("x", 0x07), ("c", 0x08), ("v", 0x09), ("b", 0x0B), ("q", 0x0C), ("w", 0x0D), ("e", 0x0E),
        ("r", 0x0F), ("y", 0x10), ("t", 0x11), ("o", 0x1F), ("u", 0x20), ("i", 0x22), ("p", 0x23),
        ("l", 0x25), ("j", 0x26), ("k", 0x28), ("n", 0x2D), ("m", 0x2E),
        ("1", 0x12), ("2", 0x13), ("3", 0x14), ("4", 0x15), ("5", 0x17), ("6", 0x16), ("7", 0x1A),
        ("8", 0x1C), ("9", 0x19), ("0", 0x1D),
        ("return", 0x24), ("tab", 0x30), ("space", 0x31), ("escape", 0x35),
        ("left", 0x7B), ("right", 0x7C), ("down", 0x7D), ("up", 0x7E),
        ("f1", 0x7A), ("f2", 0x78), ("f3", 0x63), ("f4", 0x76), ("f5", 0x60), ("f6", 0x61),
        ("f7", 0x62), ("f8", 0x64), ("f9", 0x65), ("f10", 0x6D), ("f11", 0x67), ("f12", 0x6F),
    ]

    private static let codesByName: [String: UInt16] = Dictionary(
        uniqueKeysWithValues: table.map { ($0.name, $0.code) }
    )
    private static let namesByCode: [UInt16: String] = Dictionary(
        uniqueKeysWithValues: table.map { ($0.code, $0.name) }
    )
}
