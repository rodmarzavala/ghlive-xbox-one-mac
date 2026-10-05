import Foundation

/// Persists the user's keymap at `~/Library/Application Support/GHLive/keymap.json`.
public struct KeymapStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static var standard: KeymapStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return KeymapStore(fileURL: support.appendingPathComponent("GHLive/keymap.json"))
    }

    /// The default keymap when no file exists yet. A file that exists but is invalid throws, so a typo
    /// is reported instead of silently replaced by the defaults.
    public func load() throws -> Keymap {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .default }
        return try Keymap.load(from: fileURL)
    }

    public func save(_ keymap: Keymap) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try keymap.jsonData().write(to: fileURL, options: .atomic)
    }
}
