import Combine
import GHLiveCore
import GuitarInput
import Testing

@testable import GHLiveAppKit

private func guitarState(whammy: Double = 0, tilt: UInt8 = 100) -> GuitarState {
    GuitarState(pressedButtons: [], dpad: [], whammy: whammy, tilt: tilt)
}

@MainActor
struct GuitarTestModelTests {
    private func snapshot(_ controls: Set<Control>) -> GuitarSnapshot {
        GuitarSnapshot(state: guitarState(), controls: controls)
    }

    @Test func snapshotsAreIgnoredUntilTheTestIsActive() {
        let model = GuitarTestModel(thresholds: Thresholds())
        model.receive(snapshot([.black1]))
        #expect(model.session.verifiedCount == 0)
        model.isActive = true
        model.receive(snapshot([.black1]))
        #expect(model.session.isVerified(.black1))
    }

    @Test func progressSurvivesALostGuitarAndSwitchingTheTestOff() {
        let model = GuitarTestModel(thresholds: Thresholds())
        model.isActive = true
        model.receive(snapshot([.black1]))
        model.receive(nil)
        model.isActive = false
        model.isActive = true
        #expect(model.session.isVerified(.black1))
    }

    @Test func startOverClearsTheProgress() {
        let model = GuitarTestModel(thresholds: Thresholds())
        model.isActive = true
        model.receive(snapshot([.black1]))
        model.startOver()
        #expect(model.session.verifiedCount == 0)
        #expect(model.isActive)
    }

    @Test func followingAPublisherFeedsTheTest() {
        let model = GuitarTestModel(thresholds: Thresholds())
        let subject = PassthroughSubject<GuitarSnapshot?, Never>()
        model.follow(subject)
        model.isActive = true
        subject.send(nil)
        subject.send(snapshot([.strumDown]))
        #expect(model.session.isVerified(.strumDown))
    }

    @Test func newThresholdsApplyToTheRestOfTheTest() {
        let model = GuitarTestModel(thresholds: Thresholds())
        model.updateThresholds(Thresholds(tilt: 200, tiltHysteresis: 30))
        #expect(model.session.thresholds.tilt == 200)
    }
}

struct GuitarTestCopyTests {
    @Test func progressReadsNOfM() {
        var session = GuitarTestSession()
        #expect(session.progressText == "0 of 17 verified")
        session.record(state: guitarState(), controls: [.black1, .white1])
        #expect(session.progressText == "2 of 17 verified")
    }

    @Test func rowsReadVerifiedOrNotYet() {
        var session = GuitarTestSession()
        #expect(session.statusText(for: .black1) == "Not yet")
        session.record(state: guitarState(), controls: [.black1])
        #expect(session.statusText(for: .black1) == "Verified")
    }

    @Test func analogRowsShowTheirSeenRange() {
        var session = GuitarTestSession()
        #expect(session.rangeText(for: .whammy) == "Not moved yet")
        #expect(session.rangeText(for: .tilt) == "Not moved yet")
        #expect(session.rangeText(for: .black1) == nil)
        session.record(state: guitarState(whammy: 0.04, tilt: 96), controls: [])
        session.record(state: guitarState(whammy: 0.97, tilt: 171), controls: [])
        #expect(session.rangeText(for: .whammy) == "Seen 0.04 to 0.97")
        #expect(session.rangeText(for: .tilt) == "Seen 96 to 171")
    }
}
