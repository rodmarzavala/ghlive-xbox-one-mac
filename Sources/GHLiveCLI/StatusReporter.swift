import GHLiveCore

/// What `ghlive run` always says about the driver, with or without `--verbose`: a failure must never be silent.
enum StatusReporter {
    static func line(for status: DriverStatus) -> String? {
        guard case .error(let message) = status else { return nil }
        return "error: \(message) (retrying)"
    }
}
