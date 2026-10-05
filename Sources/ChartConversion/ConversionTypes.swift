import Foundation

public enum ChartFileFormat: Sendable, Equatable {
    case chart
    case midi
}

/// What converting one file in memory produced.
public enum ConversionAttempt: Equatable, Sendable {
    case alreadyHasSixFret
    case noFiveFretTrack
    /// The new file contents and the names of the tracks (or sections) that were added.
    case converted(Data, addedTracks: [String])
}

public enum ConversionError: Error, Equatable, Sendable, LocalizedError {
    case notUTF8
    case verificationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notUTF8: "the chart is not valid UTF-8"
        case .verificationFailed(let detail): "verification failed: \(detail)"
        }
    }
}

/// Converts and verifies one chart file format. Implementations are pure: bytes in, bytes out.
public protocol ChartFormatConverter: Sendable {
    func convert(_ data: Data) throws -> ConversionAttempt

    /// Checks `converted` against `original` and returns how many notes were compared.
    func verify(converted: Data, original: Data) throws -> Int
}
