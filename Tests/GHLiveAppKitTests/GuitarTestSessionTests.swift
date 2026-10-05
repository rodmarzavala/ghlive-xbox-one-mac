import GuitarInput
import Testing

@testable import GHLiveAppKit

private let restingTilt: UInt8 = 100

extension GuitarTestSession {
    fileprivate mutating func feed(
        controls: Set<Control> = [], whammy: Double = 0, tilt: UInt8 = restingTilt
    ) {
        let state = GuitarState(pressedButtons: [], dpad: [], whammy: whammy, tilt: tilt)
        record(state: state, controls: controls)
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
        var session = GuitarTestSession()
        let before = session.isVerified(control)
        session.feed(controls: [control])
        session.feed()
        session.feed()
        #expect(!before)
        #expect(session.isVerified(control))
    }

    @Test func pressingOneControlVerifiesOnlyThatOne() {
        var session = GuitarTestSession()
        session.feed(controls: [.white2])
        let verified = Self.digitalControls.filter(session.isVerified)
        #expect(verified == [.white2])
    }

    @Test func whammyNeedsTheFullPressAndTheRelease() {
        var session = GuitarTestSession()
        session.feed(whammy: 0.6)
        #expect(!session.isVerified(.whammy))
        session.feed(whammy: GuitarTestSession.whammyFullLevel)
        #expect(!session.isVerified(.whammy))
        session.feed(whammy: 0.5)
        #expect(!session.isVerified(.whammy))
        session.feed(whammy: GuitarTestSession.whammyReleasedLevel)
        #expect(session.isVerified(.whammy))
    }

    @Test func aWhammyThatNeverPressedFullyIsNotVerifiedByTheRelease() {
        var session = GuitarTestSession()
        session.feed(whammy: 0.85)
        session.feed(whammy: 0)
        #expect(!session.isVerified(.whammy))
    }

    @Test func aWhammyReleasedBeforeTheFullPressDoesNotCount() {
        var session = GuitarTestSession()
        session.feed(whammy: 0)
        session.feed(whammy: 1)
        #expect(!session.isVerified(.whammy))
    }

    @Test func whammyMustAlsoCrossTheConfiguredThreshold() {
        var session = GuitarTestSession(thresholds: Thresholds(whammy: 0.95, whammyHysteresis: 0.05))
        session.feed(whammy: 0.92)
        session.feed(whammy: 0)
        #expect(!session.isVerified(.whammy))
        session.feed(whammy: 0.95)
        session.feed(whammy: 0)
        #expect(session.isVerified(.whammy))
    }

    @Test func whammyRangeIsTheMinimumAndMaximumSeen() {
        var session = GuitarTestSession()
        #expect(session.whammyRange == nil)
        session.feed(whammy: 0.3)
        session.feed(whammy: 0.8)
        session.feed(whammy: 0.1)
        #expect(session.whammyRange == 0.1...0.8)
    }

    @Test func tiltNeedsTheThresholdAndTheRelease() {
        let threshold = UInt8(Thresholds.defaultTilt)
        let releaseLevel = threshold - UInt8(Thresholds.defaultTiltHysteresis)
        var session = GuitarTestSession()
        session.feed(tilt: threshold - 1)
        #expect(!session.isVerified(.tilt))
        session.feed(tilt: threshold)
        #expect(!session.isVerified(.tilt))
        session.feed(tilt: releaseLevel)
        #expect(!session.isVerified(.tilt), "at the release level, not below it")
        session.feed(tilt: releaseLevel - 1)
        #expect(session.isVerified(.tilt))
    }

    @Test func tiltBelowTheThresholdNeverVerifies() {
        var session = GuitarTestSession()
        session.feed(tilt: 149)
        session.feed(tilt: 90)
        #expect(!session.isVerified(.tilt))
    }

    @Test func tiltRespectsCustomThresholds() {
        var session = GuitarTestSession(thresholds: Thresholds(tilt: 200, tiltHysteresis: 30))
        session.feed(tilt: 171)
        session.feed(tilt: 100)
        #expect(!session.isVerified(.tilt), "171 is below the custom threshold of 200")
        session.feed(tilt: 200)
        session.feed(tilt: 171)
        #expect(!session.isVerified(.tilt), "171 is not below the custom release level of 170")
        session.feed(tilt: 169)
        #expect(session.isVerified(.tilt))
    }

    @Test func tiltRangeIsTheMinimumAndMaximumSeen() {
        var session = GuitarTestSession()
        #expect(session.tiltRange == nil)
        session.feed(tilt: 110)
        session.feed(tilt: 171)
        session.feed(tilt: 95)
        #expect(session.tiltRange == 95...171)
    }

    @Test func progressCountsEveryVerifiedControl() {
        var session = GuitarTestSession()
        #expect(session.verifiedCount == 0)
        #expect(session.totalCount == 17)
        session.feed(controls: [.black1, .strumUp])
        #expect(session.verifiedCount == 2)
        session.feed(controls: [.black1])
        #expect(session.verifiedCount == 2)
        session.feed(whammy: 1)
        session.feed(whammy: 0)
        #expect(session.verifiedCount == 3)
        session.feed(tilt: 171)
        session.feed(tilt: 100)
        #expect(session.verifiedCount == 4)
    }

    @Test func isCompleteOnlyWhenEverythingIsVerified() {
        var session = GuitarTestSession()
        for control in Self.digitalControls {
            #expect(!session.isComplete)
            session.feed(controls: [control])
        }
        session.feed(whammy: 1)
        session.feed(whammy: 0)
        #expect(!session.isComplete)
        session.feed(tilt: 171)
        session.feed(tilt: 100)
        #expect(session.isComplete)
        #expect(session.verifiedCount == session.totalCount)
    }

    @Test func resetClearsEverything() {
        var session = GuitarTestSession()
        session.feed(controls: [.black1])
        session.feed(whammy: 1)
        session.feed(whammy: 0)
        session.feed(tilt: 171)
        session.feed(tilt: 100)
        session.reset()
        #expect(session == GuitarTestSession())
        #expect(session.verifiedCount == 0)
        #expect(session.whammyRange == nil)
        #expect(session.tiltRange == nil)
    }

    @Test func resetKeepsTheThresholds() {
        var session = GuitarTestSession(thresholds: Thresholds(tilt: 200))
        session.reset()
        #expect(session.thresholds.tilt == 200)
    }
}
