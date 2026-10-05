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
    case duplicateSection(String)

    public var errorDescription: String? {
        switch self {
        case .notUTF8: "the chart is not valid UTF-8"
        case .verificationFailed(let detail): "verification failed: \(detail)"
        case .duplicateSection(let name): "duplicate [\(name)]"
        }
    }
}

/// What the song's `song.ini` says that changes how a chart is converted.
public struct ConversionContext: Equatable, Sendable {
    /// `star_power_note` / `multiplier_note`: 103 forces solo markers to be Star Power, 116 forces it off.
    public var starPowerNote: UInt8?

    public init(starPowerNote: UInt8? = nil) {
        self.starPowerNote = starPowerNote
    }

    public static let none = ConversionContext()
}

/// Converts and verifies one chart file format. Implementations are pure: bytes in, bytes out.
public protocol ChartFormatConverter: Sendable {
    func convert(_ data: Data, context: ConversionContext) throws -> ConversionAttempt

    /// Checks `converted` against `original` and returns how many notes were compared.
    func verify(converted: Data, original: Data, context: ConversionContext) throws -> Int
}

extension ChartFormatConverter {
    public func convert(_ data: Data) throws -> ConversionAttempt {
        try convert(data, context: .none)
    }

    public func verify(converted: Data, original: Data) throws -> Int {
        try verify(converted: converted, original: original, context: .none)
    }
}
