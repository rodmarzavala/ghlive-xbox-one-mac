import AppKit
import Foundation
import GHLiveCore
import GuitarInput
import KeyMapping
import Testing
import USBTransport

@testable import GHLiveAppKit

struct StatusPresentationTests {
    private static let busy = "Another program has the dongle open."

    @Test func plainLanguageForEachState() {
        let cases: [(DriverStatus, Bool, String, StatusTone)] = [
            (.waitingForDongle, false, "Waiting for the dongle", .waiting),
            (.connecting, false, "Connecting to the dongle", .waiting),
            (.dongleReady, false, "Dongle ready, turn on your guitar", .ready),
            (.guitarActive, false, "Guitar connected", .active),
            (.guitarActive, true, "Paused", .paused),
            (.dongleReady, true, "Paused", .paused),
            (.error(Self.busy), false, Self.busy, .error),
            (.error(Self.busy), true, Self.busy, .error),
        ]
        for (status, isPaused, headline, tone) in cases {
            let presentation = StatusPresentation(status: status, isPaused: isPaused)
            #expect(presentation.headline == headline)
            #expect(presentation.tone == tone)
        }
    }

    @Test func unknownErrorsComeWithARetryHint() {
        let presentation = StatusPresentation(status: .error("boom"), isPaused: false)
        #expect(presentation.headline == "boom")
        #expect(presentation.detail == "GHLive retries every few seconds.")
    }

    @Test func aMissingDongleReadsTheSameWhetherWaitingOrFailed() {
        let waiting = StatusPresentation(status: .waitingForDongle, isPaused: false)
        let failed = StatusPresentation(status: .error(DongleError.notFound.localizedDescription), isPaused: false)
        #expect(failed == waiting)
        #expect(waiting.detail == "Plug in the Xbox One wireless adapter.")
    }

    @Test func aBusyDongleSaysWhoToQuit() {
        let presentation = StatusPresentation(
            status: .error(DongleError.exclusiveAccess.localizedDescription), isPaused: false)
        #expect(presentation.tone == .error)
        #expect(presentation.headline == "The dongle is in use by another app")
        #expect(presentation.detail?.hasPrefix("Quit Steam or any other app that reads Xbox controllers.") == true)
    }

    @Test func connectingAndReadyStatesSetExpectations() {
        #expect(StatusPresentation(status: .connecting, isPaused: false).detail == "This takes a few seconds.")
        #expect(
            StatusPresentation(status: .dongleReady, isPaused: false).detail
                == "If it doesn't connect, turn the guitar off and on again.")
    }

    @Test func everyToneHasADistinctSymbolThatExists() {
        let tones: [StatusTone] = [.waiting, .ready, .active, .paused, .error]
        let names = tones.map(StatusPresentation.symbolName(for:))
        #expect(Set(names).count == tones.count)
        for name in names {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil)
        }
    }
}

struct ControlNamesTests {
    @Test func everyControlHasAUniqueFriendlyName() {
        let names = Control.allCases.map(\.friendlyName)
        #expect(Set(names).count == Control.allCases.count)
        #expect(Control.black1.friendlyName == "Black 1")
        #expect(Control.white3.friendlyName == "White 3")
        #expect(Control.heroPower.friendlyName == "Hero Power")
    }

    @Test func everyControlIsInExactlyOneGroup() {
        let grouped = ControlGroup.all.flatMap(\.controls)
        #expect(grouped.count == Control.allCases.count)
        #expect(Set(grouped) == Set(Control.allCases))
    }

    @Test func keyLabelsAreReadable() {
        #expect(KeyLabel.text(for: KeyCode.named("q")!) == "Q")
        #expect(KeyLabel.text(for: KeyCode.named("space")!) == "Space")
        #expect(KeyLabel.text(for: KeyCode.named("up")!) == "\u{2191}")
        #expect(KeyLabel.text(for: KeyCode.named("f5")!) == "F5")
    }
}

struct KeyRecorderTests {
    @Test func everyKnownKeyIsAccepted() {
        for name in KeyCode.allNames {
            let key = KeyCode.named(name)!
            #expect(KeyRecorder.outcome(forKeyCode: key.rawValue) == .accepted(key))
        }
    }

    @Test func shortcutsAreNotRecorded() {
        #expect(KeyRecorder.isShortcut(.command))
        #expect(KeyRecorder.isShortcut([.control, .shift]))
        #expect(KeyRecorder.isShortcut(.option))
        #expect(!KeyRecorder.isShortcut([]))
        #expect(!KeyRecorder.isShortcut(.shift))
        #expect(!KeyRecorder.isShortcut(.capsLock))
    }

    @Test func unsupportedKeysAreRejectedWithAMessage() {
        let equalSign: UInt16 = 0x18
        #expect(KeyRecorder.outcome(forKeyCode: equalSign) == .rejected(KeyRecorder.unsupportedKeyMessage))
    }
}

struct MonitorPresentationTests {
    private func presentation(
        buttons: Set<GuitarButton>, whammy: Double = 0, tilt: UInt8 = 0, isPaused: Bool = false
    ) -> MonitorPresentation {
        let state = GuitarState(pressedButtons: buttons, dpad: [], whammy: whammy, tilt: tilt)
        var detector = ControlDetector(thresholds: Thresholds())
        let snapshot = GuitarSnapshot(state: state, controls: detector.detect(state))
        return MonitorPresentation(
            status: StatusPresentation(status: .guitarActive, isPaused: isPaused), snapshot: snapshot,
            thresholds: Thresholds(), bindings: Keymap.default.bindings, isPaused: isPaused)
    }

    @Test func keysBeingSentFollowTheKeymapWithoutDuplicates() {
        let monitor = presentation(buttons: [.black1, .strumUp, .heroPower], tilt: 160)
        #expect(monitor.keysBeingSent == ["1", "Space", "\u{2191}"])
    }

    @Test func nothingIsSentWhilePaused() {
        #expect(presentation(buttons: [.black1], isPaused: true).keysBeingSent.isEmpty)
    }

    @Test func metersUseTheThresholds() {
        let monitor = presentation(buttons: [], whammy: 0.6, tilt: 150)
        #expect(monitor.isActive(.whammy))
        #expect(monitor.isActive(.tilt))
        #expect(monitor.tiltThresholdLevel == 150.0 / 255.0)
    }

    @Test func withoutAGuitarEverythingIsIdle() {
        let monitor = MonitorPresentation(
            status: StatusPresentation(status: .dongleReady, isPaused: false), snapshot: nil,
            thresholds: Thresholds(), bindings: Keymap.default.bindings, isPaused: false)
        #expect(monitor.keysBeingSent.isEmpty)
        #expect(monitor.whammyLevel == 0)
        #expect(monitor.tiltLevel == 0)
    }
}

struct SliderSnappingTests {
    private static let whammy = 0.05...1.0

    @Test func stepsLandOnCleanDecimals() {
        #expect(SliderSnapping.snapped(0.3512, in: Self.whammy, step: 0.05) == 0.35)
        #expect(SliderSnapping.snapped(0.5, in: Self.whammy, step: 0.05) == 0.5)
        #expect(SliderSnapping.snapped(0.15, in: Self.whammy, step: 0.05) == 0.15)
    }

    @Test func valuesStayInsideTheRange() {
        #expect(SliderSnapping.snapped(-3, in: Self.whammy, step: 0.05) == 0.05)
        #expect(SliderSnapping.snapped(9, in: Self.whammy, step: 0.05) == 1.0)
    }

    @Test func wholeNumberSlidersRoundToIntegers() {
        #expect(SliderSnapping.snapped(149.6, in: 1...255, step: 1) == 150)
    }
}
