import AppKit
import GHLiveCore
import GuitarInput
import KeyMapping
import Testing

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

    @Test func errorsComeWithARetryHint() {
        let presentation = StatusPresentation(status: .error("boom"), isPaused: false)
        #expect(presentation.detail?.contains("tries again") == true)
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
        #expect(Control.black1.friendlyName == "Top fret 1 (black)")
        #expect(Control.white3.friendlyName == "Bottom fret 3 (white)")
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
