public enum GHLiveInfo {
    public static let version = "1.0.2"
    /// The app's bundle id. `scripts/build-app.sh` reads it from this file for Info.plist, and it is the
    /// subsystem of the unified log, so there is one source of truth.
    public static let bundleIdentifier = "io.github.rodmarzavala.ghlive"
}
