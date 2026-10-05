import Foundation
import GuitarInput

/// Which key each control presses, plus the thresholds that digitise whammy and tilt.
public struct Keymap: Equatable, Sendable {
    public var bindings: [Control: KeyCode]
    public var thresholds: Thresholds

    public init(bindings: [Control: KeyCode], thresholds: Thresholds = Thresholds()) {
        self.bindings = bindings
        self.thresholds = thresholds
    }
}

// MARK: - Default

extension Keymap {
    public static let `default` = Keymap(bindings: defaultKeyNames.mapValues { KeyCode.named($0)! })

    private static let defaultKeyNames: [Control: String] = [
        .black1: "1", .black2: "2", .black3: "3",
        .white1: "q", .white2: "w", .white3: "e",
        .strumUp: "up", .strumDown: "down",
        .heroPower: "space", .tilt: "space",
        .whammy: "x", .pause: "escape", .ghtv: "tab",
        .dpadUp: "up", .dpadDown: "down", .dpadLeft: "left", .dpadRight: "right",
    ]
}

// MARK: - JSON

private enum ThresholdName {
    static let whammy = "whammy"
    static let whammyHysteresis = "whammy_hysteresis"
    static let tilt = "tilt"
    static let tiltHysteresis = "tilt_hysteresis"
}

private let tiltMaximum = 255

/// File shape: `{"keys": {"black_1": "1", ...}, "thresholds": {"tilt": 150, ...}}`; `thresholds` is optional.
private struct KeymapDocument: Codable {
    var keys: [String: String]
    var thresholds: [String: Double]?
}

extension Keymap {
    public static func parse(json: Data) throws -> Keymap {
        let document: KeymapDocument
        do {
            document = try JSONDecoder().decode(KeymapDocument.self, from: json)
        } catch let error as DecodingError {
            throw KeymapError.invalidJSON(error.humanDescription)
        }
        return try Keymap(
            bindings: parseBindings(document.keys),
            thresholds: parseThresholds(document.thresholds ?? [:])
        )
    }

    public static func load(from url: URL) throws -> Keymap {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw KeymapError.invalidFile(path: url.path, reason: "cannot read keymap: \(error.localizedDescription)")
        }
        do {
            return try parse(json: data)
        } catch let error as KeymapError {
            throw KeymapError.invalidFile(path: url.path, reason: error.description)
        }
    }

    public func jsonData() throws -> Data {
        let keys = Dictionary(
            uniqueKeysWithValues: bindings.compactMap { control, key in key.name.map { (control.rawValue, $0) } }
        )
        let document = KeymapDocument(
            keys: keys,
            thresholds: [
                ThresholdName.whammy: thresholds.whammy,
                ThresholdName.whammyHysteresis: thresholds.whammyHysteresis,
                ThresholdName.tilt: Double(thresholds.tilt),
                ThresholdName.tiltHysteresis: Double(thresholds.tiltHysteresis),
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    private static func parseBindings(_ table: [String: String]) throws -> [Control: KeyCode] {
        var bindings: [Control: KeyCode] = [:]
        for (controlName, keyName) in table.sorted(by: { $0.key < $1.key }) {
            guard let control = Control(rawValue: controlName) else {
                throw KeymapError.unknownControl(controlName)
            }
            guard let key = KeyCode.named(keyName) else {
                throw KeymapError.unknownKey(keyName, control: controlName)
            }
            bindings[control] = key
        }
        return bindings
    }

    private static func parseThresholds(_ table: [String: Double]) throws -> Thresholds {
        var thresholds = Thresholds()
        let known = [
            ThresholdName.whammy, ThresholdName.whammyHysteresis, ThresholdName.tilt, ThresholdName.tiltHysteresis,
        ]
        if let unknown = table.keys.sorted().first(where: { !known.contains($0) }) {
            throw KeymapError.unknownThreshold(unknown)
        }
        if let value = table[ThresholdName.whammy] { thresholds.whammy = value }
        if let value = table[ThresholdName.whammyHysteresis] { thresholds.whammyHysteresis = value }
        if let value = table[ThresholdName.tilt] {
            thresholds.tilt = try wholeNumber(value, named: ThresholdName.tilt)
        }
        if let value = table[ThresholdName.tiltHysteresis] {
            thresholds.tiltHysteresis = try wholeNumber(value, named: ThresholdName.tiltHysteresis)
        }
        try validate(thresholds)
        return thresholds
    }

    private static func wholeNumber(_ value: Double, named name: String) throws -> Int {
        guard value.rounded() == value, abs(value) < Double(Int32.max) else {
            throw KeymapError.thresholdOutOfRange(name, value: value, allowed: "a whole number")
        }
        return Int(value)
    }

    /// The band must fit below its threshold, otherwise the release level would be negative and the
    /// control could never switch off.
    private static func validate(_ thresholds: Thresholds) throws {
        try require(
            thresholds.whammy > 0 && thresholds.whammy <= 1, ThresholdName.whammy, thresholds.whammy,
            "above 0 and at most 1")
        try require(
            thresholds.whammyHysteresis >= 0 && thresholds.whammyHysteresis <= thresholds.whammy,
            ThresholdName.whammyHysteresis, thresholds.whammyHysteresis, "between 0 and the whammy threshold"
        )
        try require(
            (1...tiltMaximum).contains(thresholds.tilt),
            ThresholdName.tilt, Double(thresholds.tilt), "between 1 and \(tiltMaximum)"
        )
        try require(
            (0...thresholds.tilt).contains(thresholds.tiltHysteresis),
            ThresholdName.tiltHysteresis, Double(thresholds.tiltHysteresis), "between 0 and the tilt threshold"
        )
    }

    private static func require(_ isValid: Bool, _ name: String, _ value: Double, _ allowed: String) throws {
        guard isValid else { throw KeymapError.thresholdOutOfRange(name, value: value, allowed: allowed) }
    }
}

extension DecodingError {
    fileprivate var humanDescription: String {
        switch self {
        case .keyNotFound(let key, _): "missing \"\(key.stringValue)\""
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            context.debugDescription
        @unknown default: String(describing: self)
        }
    }
}
