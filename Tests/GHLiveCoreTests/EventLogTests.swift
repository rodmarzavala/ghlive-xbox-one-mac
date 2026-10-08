import Foundation
import Testing

@testable import GHLiveCore

/// The repository root, found from this file so the tests can read `scripts/`.
private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@Suite("Event log")
struct EventLogTests {
    @Test("the subsystem is the published bundle id")
    func subsystemIsTheBundleId() {
        #expect(GHLiveInfo.bundleIdentifier == "io.github.rodmarzavala.ghlive")
    }

    @Test("build-app.sh takes the bundle id from GHLiveInfo instead of repeating it")
    func buildScriptHasNoSecondCopy() throws {
        let script = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/build-app.sh"), encoding: .utf8)
        #expect(!script.contains(GHLiveInfo.bundleIdentifier))
        #expect(script.contains("Sources/GHLiveCore/GHLiveInfo.swift"))
    }

    @Test("state changes persist on disk and failures are errors")
    func levels() {
        #expect(LogEvent.driverStatus(.guitarActive).level == .notice)
        #expect(LogEvent.driverStatus(.error("x")).level == .error)
        #expect(LogEvent.dongleArrived.level == .notice)
        #expect(LogEvent.dongleBusy.level == .error)
        #expect(LogEvent.connectFailed("x").level == .error)
        #expect(LogEvent.readFailed("x").level == .error)
        #expect(LogEvent.writeFailed("x").level == .error)
        #expect(LogEvent.keepAliveFailed("x").level == .error)
        #expect(LogEvent.keymapLoadFailed.level == .error)
        #expect(LogEvent.terminationTimedOut.level == .fault)
        #expect(LogEvent.inputReleased(count: 2, reason: .pause).level == .notice)
        #expect(LogEvent.inputReleased(count: 0, reason: .pause).level == .debug)
    }

    @Test("every category is used by some event")
    func categories() {
        #expect(LogEvent.driverStatus(.connecting).category == .driver)
        #expect(LogEvent.dongleRemoved.category == .usb)
        #expect(LogEvent.inputReleased(count: 1, reason: .stop).category == .output)
        #expect(LogEvent.launched(version: "1").category == .app)
    }

    @Test("the busy dongle message says what to do")
    func busyMessage() {
        #expect(LogEvent.dongleBusy.message.contains("Steam"))
    }

    @Test("a composite log forwards to every log in order")
    func composite() {
        let first = RecordingEventLog()
        let second = RecordingEventLog()
        CompositeEventLog([first, second]).record(.paused)
        #expect(first.events == [.paused])
        #expect(second.events == [.paused])
    }
}
