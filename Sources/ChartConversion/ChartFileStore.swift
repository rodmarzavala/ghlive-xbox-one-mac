import Foundation

/// The file operations a conversion needs, behind a protocol so tests can make any step fail.
public protocol ChartFileStore: Sendable {
    func read(_ url: URL) throws -> Data
    func exists(_ url: URL) -> Bool
    /// Copies `url` to `destination`, creating folders; fails if `destination` already exists.
    func backUp(_ url: URL, to destination: URL) throws
    /// Writes `data` to a new hidden file next to `url` and returns it.
    func writeTemporary(_ data: Data, besides url: URL) throws -> URL
    /// Atomically swaps the temporary file in for `url`.
    func replace(_ url: URL, withTemporary temporary: URL) throws
    func remove(_ url: URL)
}

public struct DiskChartFileStore: ChartFileStore {
    private static let temporaryPrefix = "."
    private static let temporarySuffix = ".ghlive-tmp"

    public init() {}

    public func read(_ url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func backUp(_ url: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: url, to: destination)
    }

    public func writeTemporary(_ data: Data, besides url: URL) throws -> URL {
        let name = Self.temporaryPrefix + url.lastPathComponent + Self.temporarySuffix
        let temporary = url.deletingLastPathComponent().appendingPathComponent(name)
        try data.write(to: temporary)
        return temporary
    }

    public func replace(_ url: URL, withTemporary temporary: URL) throws {
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    }

    public func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
