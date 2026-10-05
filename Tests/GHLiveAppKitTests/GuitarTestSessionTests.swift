import GuitarInput
import Testing

@testable import GHLiveAppKit

private let restingTilt: UInt8 = 100

/// Feeds a session the way the driver does: the controls come from a `ControlDetector`, not from the test.
private struct Rig {
    var session = GuitarTestSession()
    private var detector: ControlDetector

    init(thresholds: Thresholds = Thresholds()) {
        detector = ControlDetector(thresholds: thresholds)
    }

    mutating func feed(controls: Set<Control> = [], whammy: Double = 0, tilt: UInt8 = restingTilt) {
        let state = GuitarState(pressedButtons: [], dpad: [], whammy: whammy, tilt: tilt)
        session.record(state: state, controls: detector.detect(state).union(controls))
    }
}

struct GuitarTestSessionTests {
    private static let digitalControls: [Control] = Control.allCases.filter { $0 != .whammy && $0 != .tilt }

    @Test func theDigitalControlsComeFromTheControlEnum() {
        #expect(GuitarTestSession.digitalControls == Self.digitalControls)
        #expect(GuitarTestSession.digitalControls.count == 15)
    }

    @Test(arguments: GuitarTestSessionTests.digitalControls)
    func aDigitalControlVerifiesOnFirstPressAndStaysVerified(control: Control) {
        var rig = Rig()
        let before = rig.session.isVerified(control)
        rig.feed(controls: [control])
        rig.feed()
        rig.feed()
        #expect(!before)
        #expect(rig.session.isVerified(control))
    }

    @Test func pressingOneControlVerifiesOnlyThatOne() {
        var rig = Rig()
        rig.feed(controls: [.white2])
        let verified = Self.digitalControls.filter(rig.session.isVerified)
        #expect(verified == [.white2])
    }

    @Test func whammyNeedsTheFullPressAndTheRelease() {
        var rig = Rig()
        rig.feed(whammy: 0.6)
        #expect(!rig.session.isVerified(.whammy))
        rig.feed(whammy: GuitarTestSession.whammyFullLevel)
        #expect(!rig.session.isVerified(.whammy))
        rig.feed(whammy: 0.5)
        #expect(!rig.session.isVerified(.whammy))
        rig.feed(whammy: GuitarTestSession.whammyReleasedLevel)
        #expect(rig.session.isVerified(.whammy))
    }

    @Test func aWhammyThatNeverPressedFullyIsNotVerifiedByTheRelease() {
        var rig = Rig()
        rig.feed(whammy: 0.85)
        rig.feed(whammy: 0)
        #expect(!rig.session.isVerified(.whammy))
    }

    @Test func aWhammyReleasedBeforeTheFullPressDoesNotCount() {
        var rig = Rig()
        rig.feed(whammy: 0)
        rig.feed(whammy: 1)
        #expect(!rig.session.isVerified(.whammy))
    }

    @Test func whammyMustAlsoCrossTheConfiguredThreshold() {
        var rig = Rig(thresholds: Thresholds(whammy: 0.95, whammyHysteresis: 0.05))
        rig.feed(whammy: 0.92)
        rig.feed(whammy: 0)
        #expect(!rig.session.isVerified(.whammy))
        rig.feed(whammy: 0.95)
        rig.feed(whammy: 0)
        #expect(rig.session.isVerified(.whammy))
    }

    @Test func whammyRangeIsTheMinimumAndMaximumSeen() {
        var rig = Rig()
        #expect(rig.session.whammyRange == nil)
        rig.feed(whammy: 0.3)
        rig.feed(whammy: 0.8)
        rig.feed(whammy: 0.1)
        #expect(rig.session.whammyRange == 0.1...0.8)
    }

    @Test func tiltNeedsTheThresholdAndTheRelease() {
        let threshold = UInt8(Thresholds.defaultTilt)
        let releaseLevel = threshold - UInt8(Thresholds.defaultTiltHysteresis)
        var rig = Rig()
        rig.feed(tilt: threshold - 1)
        #expect(!rig.session.isVerified(.tilt))
        rig.feed(tilt: threshold)
        #expect(!rig.session.isVerified(.tilt))
        rig.feed(tilt: releaseLevel)
        #expect(!rig.session.isVerified(.tilt), "at the release level, not below it")
        rig.feed(tilt: releaseLevel - 1)
        #expect(rig.session.isVerified(.tilt))
    }

    @Test func tiltBelowTheThresholdNeverVerifies() {
        var rig = Rig()
        rig.feed(tilt: 149)
        rig.feed(tilt: 90)
        #expect(!rig.session.isVerified(.tilt))
    }

    @Test func tiltRespectsCustomThresholds() {
        var rig = Rig(thresholds: Thresholds(tilt: 200, tiltHysteresis: 30))
        rig.feed(tilt: 171)
        rig.feed(tilt: 100)
        #expect(!rig.session.isVerified(.tilt), "171 is below the custom threshold of 200")
        rig.feed(tilt: 200)
        rig.feed(tilt: 171)
        #expect(!rig.session.isVerified(.tilt), "171 is not below the custom release level of 170")
        rig.feed(tilt: 169)
        #expect(rig.session.isVerified(.tilt))
    }

    @Test func tiltRangeIsTheMinimumAndMaximumSeen() {
        var rig = Rig()
        #expect(rig.session.tiltRange == nil)
        rig.feed(tilt: 110)
        rig.feed(tilt: 171)
        rig.feed(tilt: 95)
        #expect(rig.session.tiltRange == 95...171)
    }

    @Test func progressCountsEveryVerifiedControl() {
        var rig = Rig()
        #expect(rig.session.verifiedCount == 0)
        #expect(rig.session.totalCount == 17)
        rig.feed(controls: [.black1, .strumUp])
        #expect(rig.session.verifiedCount == 2)
        rig.feed(controls: [.black1])
        #expect(rig.session.verifiedCount == 2)
        rig.feed(whammy: 1)
        rig.feed(whammy: 0)
        #expect(rig.session.verifiedCount == 3)
        rig.feed(tilt: 171)
        rig.feed(tilt: 100)
        #expect(rig.session.verifiedCount == 4)
    }

    @Test func isCompleteOnlyWhenEverythingIsVerified() {
        var rig = Rig()
        for control in Self.digitalControls {
            #expect(!rig.session.isComplete)
            rig.feed(controls: [control])
        }
        rig.feed(whammy: 1)
        rig.feed(whammy: 0)
        #expect(!rig.session.isComplete)
        rig.feed(tilt: 171)
        rig.feed(tilt: 100)
        #expect(rig.session.isComplete)
        #expect(rig.session.verifiedCount == rig.session.totalCount)
    }

    @Test func resetClearsEverything() {
        var rig = Rig()
        rig.feed(controls: [.black1])
        rig.feed(whammy: 1)
        rig.feed(whammy: 0)
        rig.feed(tilt: 171)
        rig.feed(tilt: 100)
        rig.session.reset()
        #expect(rig.session == GuitarTestSession())
        #expect(rig.session.verifiedCount == 0)
        #expect(rig.session.whammyRange == nil)
        #expect(rig.session.tiltRange == nil)
    }

    @Test func aVerifiedWhammyStaysVerified() {
        var rig = Rig()
        rig.feed(whammy: 1)
        rig.feed(whammy: 0)
        rig.feed(whammy: 0.5)
        rig.feed(whammy: 1)
        #expect(rig.session.isVerified(.whammy))
    }

    @Test func aVerifiedTiltStaysVerified() {
        var rig = Rig()
        rig.feed(tilt: 171)
        rig.feed(tilt: 100)
        rig.feed(tilt: 160)
        rig.feed(tilt: 171)
        #expect(rig.session.isVerified(.tilt))
    }
}
