import Testing

@testable import GuitarInput

private let idleTiltValue = 110

/// Feeds states to one detector, like the driver feeds reports. Results are returned (not asserted inline)
/// because `#expect` cannot call mutating members.
private struct Rig {
    private var detector: ControlDetector

    init(_ thresholds: Thresholds = Thresholds()) {
        detector = ControlDetector(thresholds: thresholds)
    }

    mutating func controls(
        buttons: Set<GuitarButton> = [],
        dpad: Set<DpadDirection> = [],
        whammy: Double = 0,
        tilt: Int = idleTiltValue
    ) -> Set<Control> {
        detector.detect(
            GuitarState(pressedButtons: buttons, dpad: dpad, whammy: whammy, tilt: UInt8(tilt))
        )
    }
}

@Suite("Control detection")
struct ControlDetectionTests {
    @Test("an idle guitar has no active controls")
    func idle() {
        var rig = Rig()
        #expect(rig.controls().isEmpty)
    }

    @Test(
        "every button maps to its control",
        arguments: [
            (GuitarButton.black1, Control.black1), (.black2, .black2), (.black3, .black3),
            (.white1, .white1), (.white2, .white2), (.white3, .white3),
            (.strumUp, .strumUp), (.strumDown, .strumDown),
            (.heroPower, .heroPower), (.pause, .pause), (.ghtv, .ghtv),
        ]
    )
    func buttonMapping(button: GuitarButton, control: Control) {
        var rig = Rig()
        #expect(rig.controls(buttons: [button]) == [control])
    }

    @Test("d-pad diagonals activate two controls")
    func dpadDiagonals() {
        var rig = Rig()
        #expect(rig.controls(dpad: [.up, .left]) == [.dpadUp, .dpadLeft])
    }

    @Test("every control is reachable")
    func everyControlIsDetectable() {
        var rig = Rig()
        var seen = rig.controls(
            buttons: Set(GuitarButton.allCases), dpad: Set(DpadDirection.allCases), whammy: 1, tilt: 255)
        seen.formUnion(rig.controls())
        #expect(seen == Set(Control.allCases))
    }

    @Test("whammy engages at the threshold")
    func whammyThreshold() {
        var rig = Rig()
        let below = rig.controls(whammy: Thresholds.defaultWhammy - 0.01)
        let at = rig.controls(whammy: Thresholds.defaultWhammy)
        #expect(!below.contains(.whammy))
        #expect(at.contains(.whammy))
    }

    @Test("whammy jitter inside the band does not chatter, below it releases")
    func whammyHysteresis() {
        var rig = Rig()
        _ = rig.controls(whammy: 0.8)
        let bandBottom = Thresholds.defaultWhammy - Thresholds.defaultWhammyHysteresis
        for value in [Thresholds.defaultWhammy - 0.01, Thresholds.defaultWhammy, bandBottom] {
            let active = rig.controls(whammy: value)
            #expect(active.contains(.whammy), "whammy \(value)")
        }
        let released = rig.controls(whammy: bandBottom - 0.01)
        #expect(!released.contains(.whammy))
    }

    @Test("whammy jitter just below the threshold never engages it")
    func whammyJitterBelow() {
        var rig = Rig()
        for value in [0.45, 0.49, 0.47, 0.499] {
            let active = rig.controls(whammy: value)
            #expect(!active.contains(.whammy), "whammy \(value)")
        }
    }

    @Test("a custom whammy threshold is honoured")
    func customWhammy() {
        var rig = Rig(Thresholds(whammy: 0.1, whammyHysteresis: 0))
        #expect(rig.controls(whammy: 0.2).contains(.whammy))
    }

    @Test("tilt engages at the threshold")
    func tiltThreshold() {
        var rig = Rig()
        let below = rig.controls(tilt: Thresholds.defaultTilt - 1)
        let at = rig.controls(tilt: Thresholds.defaultTilt)
        #expect(!below.contains(.tilt))
        #expect(at.contains(.tilt))
    }

    @Test("measured idle tilt jitter (95 to 115) never engages tilt")
    func idleTiltJitter() {
        var rig = Rig()
        for value in 95...115 {
            let active = rig.controls(tilt: value)
            #expect(!active.contains(.tilt), "tilt \(value)")
        }
    }

    @Test("tilt jitter inside the band does not chatter, below it releases")
    func tiltHysteresis() {
        var rig = Rig()
        _ = rig.controls(tilt: Thresholds.defaultTilt + 20)
        let releaseBelow = Thresholds.defaultTilt - Thresholds.defaultTiltHysteresis
        for value in [Thresholds.defaultTilt - 1, Thresholds.defaultTilt, releaseBelow] {
            let active = rig.controls(tilt: value)
            #expect(active.contains(.tilt), "tilt \(value)")
        }
        let released = rig.controls(tilt: releaseBelow - 1)
        #expect(!released.contains(.tilt))
    }

    @Test("custom tilt thresholds")
    func customTilt() {
        var rig = Rig(Thresholds(tilt: 100, tiltHysteresis: 5))
        let engaged = rig.controls(tilt: 100)
        let held = rig.controls(tilt: 95)
        let released = rig.controls(tilt: 94)
        #expect(engaged.contains(.tilt))
        #expect(held.contains(.tilt))
        #expect(!released.contains(.tilt))
    }

    @Test("the defaults are the values measured on hardware")
    func defaultsMatchMeasurements() {
        #expect(Thresholds.defaultTilt == 150)
        #expect(Thresholds.defaultTiltHysteresis == 10)
        #expect(Thresholds.defaultWhammy == 0.5)
        #expect(Thresholds.defaultWhammyHysteresis == 0.1)
    }

    @Test("reset forgets an engaged tilt")
    func resetForgets() {
        var detector = ControlDetector(thresholds: Thresholds())
        let tilted = GuitarState(pressedButtons: [], dpad: [], whammy: 0, tilt: 170)
        let between = GuitarState(pressedButtons: [], dpad: [], whammy: 0, tilt: 145)
        _ = detector.detect(tilted)
        detector.reset()
        let afterReset = detector.detect(between)
        #expect(!afterReset.contains(.tilt))
    }
}

@Suite("Hysteresis detector")
struct HysteresisDetectorTests {
    @Test("engages at the threshold and releases only below the band")
    func engagesAndReleases() {
        var detector = HysteresisDetector(engageAt: 10, releaseBelow: 7)
        let results = [9, 10, 7, 6, 9].map { detector.update($0) }
        #expect(results == [false, true, true, false, false])
    }

    @Test("reset forgets the engaged state")
    func reset() {
        var detector = HysteresisDetector(engageAt: 10, releaseBelow: 7)
        _ = detector.update(20)
        detector.reset()
        let result = detector.update(8)
        #expect(!result)
    }
}
