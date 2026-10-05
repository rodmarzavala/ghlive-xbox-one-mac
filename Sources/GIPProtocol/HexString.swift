import Foundation

extension Data {
    /// Space-separated lowercase hex, the format used in logs and by `ghlive sniff`.
    public var hexString: String {
        map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}
