import Foundation

public enum KeymapError: Error, Equatable, CustomStringConvertible, LocalizedError, Sendable {
    case unknownControl(String)
    case unknownKey(String, control: String)
    case unknownThreshold(String)
    case thresholdOutOfRange(String, value: Double, allowed: String)
    case invalidJSON(String)
    case invalidFile(path: String, reason: String)

    public var description: String {
        switch self {
        case .unknownControl(let name):
            "unknown control '\(name)' in \"keys\""
        case .unknownKey(let key, let control):
            "unknown key '\(key)' for control '\(control)'"
        case .unknownThreshold(let name):
            "unknown threshold '\(name)' in \"thresholds\""
        case .thresholdOutOfRange(let name, let value, let allowed):
            "threshold '\(name)' is \(value), it must be \(allowed)"
        case .invalidJSON(let detail):
            "invalid keymap JSON: \(detail)"
        case .invalidFile(let path, let reason):
            "\(path): \(reason)"
        }
    }

    public var errorDescription: String? { description }
}
