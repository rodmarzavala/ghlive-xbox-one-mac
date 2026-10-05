import GHLiveCore
import GuitarInput

/// Turns the live input into calibration lines: the active controls plus the raw tilt, printed only when
/// the controls change or the tilt moves noticeably.
struct VerboseReporter {
    // Idle tilt wanders across a 20-wide range (95-115); a raw tilt change is reported only beyond that.
    static let tiltReportStep = 25
    static let noControlsLabel = "none"

    private var lastControls: Set<Control>?
    private var lastReportedTilt = 0

    mutating func line(for snapshot: GuitarSnapshot) -> String? {
        let tilt = Int(snapshot.state.tilt)
        guard snapshot.controls != lastControls || abs(tilt - lastReportedTilt) >= Self.tiltReportStep else {
            return nil
        }
        lastControls = snapshot.controls
        lastReportedTilt = tilt
        let names = snapshot.controls.map(\.rawValue).sorted().joined(separator: ", ")
        return "\(names.isEmpty ? Self.noControlsLabel : names) | tilt=\(tilt)"
    }
}
