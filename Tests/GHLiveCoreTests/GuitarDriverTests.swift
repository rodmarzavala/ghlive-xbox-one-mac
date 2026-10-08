import Combine
import Foundation
import GIPProtocol
import GuitarInput
import IOKit
import KeyMapping
import KeyboardOutput
import Testing
import USBTransport

@testable import GHLiveCore

private let fretBlack1: UInt8 = 0x02
private let fretOffset = 0
private let tiltOffset = 19
private let whammyOffset = 6
private let raisedTilt: UInt8 = 171
private let whammyFullyPressed: UInt8 = 0xFF

@MainActor
private final class Harness {
    let monitor = FakeMonitor()
    let emitter = RecordingEmitter()
    let clock = FakeClock()
    let events = RecordingEventLog()
    let driver: GuitarDriver
    let connector: FakeConnector

    init(
        connector: FakeConnector,
        timing: GuitarDriver.Timing = Harness.fastTiming
    ) {
        self.connector = connector
        let sink = KeyboardSink(keymap: .default, emitter: emitter)
        let clock = clock
        driver = GuitarDriver(
            monitor: monitor,
            connector: connector,
            sink: sink,
            thresholds: Keymap.default.thresholds,
            timing: timing,
            now: { clock.now() },
            eventLog: events
        )
    }

    /// The events without the zero-key releases, which every teardown path emits and which say nothing.
    var meaningfulEvents: [LogEvent] {
        events.events.filter {
            if case .inputReleased(let count, _) = $0 { return count > 0 }
            return true
        }
    }

    static var fastTiming: GuitarDriver.Timing {
        var timing = GuitarDriver.Timing()
        timing.retryDelay = .milliseconds(20)
        timing.tick = .milliseconds(10)
        return timing
    }

    func arrive(waitingFor transport: FakeTransport? = nil) async {
        driver.start()
        monitor.send(.arrived)
        if let transport {
            _ = await eventually { transport.written.count >= 3 }
        }
    }
}

private func commands(of writes: [Data]) -> [UInt8] {
    writes.flatMap { decodePackets($0).packets.map(\.command) }
}

@MainActor
@Suite("Guitar driver", .serialized)
struct GuitarDriverTests {
    @Test("starts out waiting for the dongle")
    func initialStatus() {
        let harness = Harness(connector: FakeConnector([]))
        #expect(harness.driver.status == .waitingForDongle)
        #expect(harness.driver.snapshot == nil)
        #expect(!harness.driver.isPaused)
    }

    @Test("arrival connects and sends the handshake in order")
    func handshake() async {
        let transport = FakeTransport()
        let harness = Harness(connector: FakeConnector([.success(transport)]))
        await harness.arrive(waitingFor: transport)
        #expect(await eventually { transport.written.count == 4 })
        #expect(
            commands(of: transport.written)
                == [
                    GipCommand.power, .led, .authenticate, .ghlOutput,
                ].map(\.rawValue)
        )
        #expect(harness.driver.status == .dongleReady)
        await harness.driver.stop()
    }

    @Test("an idle report makes the guitar active without pressing keys")
    func idleReportActivatesGuitar() async {
        let transport = FakeTransport()
        let harness = Harness(connector: FakeConnector([.success(transport)]))
        await harness.arrive(waitingFor: transport)
        transport.feed(guitarMessage(idleReport))
        #expect(await eventually { harness.driver.status == .guitarActive })
        #expect(harness.emitter.events.isEmpty)
        #expect(harness.driver.activeControls.isEmpty)
        #expect(harness.driver.guitarState?.tilt == 0x70)
        await harness.driver.stop()
    }

    @Test("a fret press and release become key down and up")
    func fretPressAndRelease() async {
        let transport = FakeTransport()
        let harness = Harness(connector: FakeConnector([.success(transport)]))
        await harness.arrive(waitingFor: transport)
        transport.feed(guitarMessage(report([fretOffset: fretBlack1])))
        #expect(await eventually { harness.emitter.events == [.down(key("1"))] })
        #expect(harness.driver.activeControls == [.black1])
        transport.feed(guitarMessage(idleReport))
        #expect(await eventually { harness.emitter.events == [.down(key("1")), .up(key("1"))] })
        await harness.driver.stop()
    }

    @Test("tilt and whammy digitise with the shared hysteresis")
    func tiltAndWhammy() async {
        let transport = FakeTransport()
        let harness = Harness(connector: FakeConnector([.success(transport)]))
        await harness.arrive(waitingFor: transport)
        transport.feed(guitarMessage(report([tiltOffset: raisedTilt, whammyOffset: whammyFullyPressed])))
        #expect(await eventually { harness.driver.activeControls == [.tilt, .whammy] })
        #expect(harness.emitter.events == [.down(key("x")), .down(key("space"))])
        await harness.driver.stop()
    }

    @Test("packets that require acknowledgement are acknowledged")
    func acknowledges() async {
        let transport = FakeTransport()
        let harness = Harness(connector: FakeConnector([.success(transport)]))
        await harness.arrive(waitingFor: transport)
        let announce = GipPacket(
            command: .announce,
            flags: [.system, .acknowledgeRequired],
            sequence: 9,
            payload: Data(count: 4)
        )
        transport.feed(announce.encoded())
        #expect(await eventually { transport.written.contains(announce.acknowledgement().encoded()) })
        await harness.driver.stop()
    }

    @Test("two messages in one transfer are both processed")
    func bundledTransfer() async {
        let transport = FakeTransport()
        let harness = Harness(connector: FakeConnector([.success(transport)]))
        await harness.arrive(waitingFor: transport)
        let status = GipPacket(command: .status, flags: .system, sequence: 2, payload: Data([0x83])).encoded()
        transport.feed(status + guitarMessage(report([fretOffset: fretBlack1])))
        #expect(await eventually { harness.emitter.events == [.down(key("1"))] })
        await harness.driver.stop()
    }

    @Test("a malformed guitar report is ignored")
    func malformedReport() async {
        let transport = FakeTransport()
        let harness = Harness(connector: FakeConnector([.success(transport)]))
        await harness.arrive(waitingFor: transport)
        transport.feed(guitarMessage(Data(count: 5)))
        transport.feed(guitarMessage(report([fretOffset: fretBlack1])))
        #expect(await eventually { harness.emitter.events == [.down(key("1"))] })
        await harness.driver.stop()
    }

    @Test("removal releases every key and goes back to waiting; re-arrival reconnects")
    func removalAndReconnect() async {
        let first = FakeTransport()
        let second = FakeTransport()
        let harness = Harness(connector: FakeConnector([.success(first), .success(second)]))
        await harness.arrive(waitingFor: first)
        first.feed(guitarMessage(report([fretOffset: fretBlack1])))
        #expect(await eventually { harness.emitter.events == [.down(key("1"))] })

        harness.monitor.send(.removed)
        #expect(await eventually { harness.driver.status == .waitingForDongle })
        #expect(harness.emitter.events == [.down(key("1")), .up(key("1"))])
        #expect(harness.driver.snapshot == nil)
        #expect(first.closed)

        harness.monitor.send(.arrived)
        #expect(await eventually { second.written.count == 4 })
        #expect(harness.driver.status == .dongleReady)
        await harness.driver.stop()
    }

    @Test("a duplicate arrival does not open a second connection")
    func duplicateArrival() async {
        let transport = FakeTransport()
        let harness = Harness(connector: FakeConnector([.success(transport)]))
        await harness.arrive(waitingFor: transport)
        harness.monitor.send(.arrived)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(harness.connector.attempts == 1)
        await harness.driver.stop()
    }

    @Test("a failed connect shows the error and retries")
    func connectFailureRetries() async {
        let transport = FakeTransport()
        let harness = Harness(
            connector: FakeConnector([.failure(DongleError.exclusiveAccess), .success(transport)])
        )
        harness.driver.start()
        harness.monitor.send(.arrived)
        #expect(
            await eventually {
                if case .error(let message) = harness.driver.status { return message.contains("Steam") }
                return false
            }
        )
        #expect(await eventually { harness.driver.status == .dongleReady })
        #expect(harness.connector.attempts == 2)
        await harness.driver.stop()
    }

    @Test("a read failure releases the keys, reports the error and reconnects")
    func readFailureReconnects() async {
        let first = FakeTransport()
        let second = FakeTransport()
        let harness = Harness(connector: FakeConnector([.success(first), .success(second)]))
        await harness.arrive(waitingFor: first)
        first.feed(guitarMessage(report([fretOffset: fretBlack1])))
        #expect(await eventually { harness.emitter.events == [.down(key("1"))] })

        first.fail(DongleError.disconnected)
        #expect(await eventually { harness.emitter.events == [.down(key("1")), .up(key("1"))] })
        #expect(await eventually { second.written.count == 4 })
        #expect(first.closed)
        await harness.driver.stop()
    }

    @Test("a stream that ends by itself counts as a lost connection")
    func streamEndReconnects() async {
        let first = FakeTransport()
        let second = FakeTransport()
        let harness = Harness(connector: FakeConnector([.success(first), .success(second)]))
        await harness.arrive(waitingFor: first)
        first.endStream()
        #expect(await eventually { second.written.count == 4 })
        await harness.driver.stop()
    }

    @Test("pause releases the keys and ignores input until resume")
    func pauseAndResume() async {
        let transport = FakeTransport()
        let harness = Harness(connector: FakeConnector([.success(transport)]))
        await harness.arrive(waitingFor: transport)
        transport.feed(guitarMessage(report([fretOffset: fretBlack1])))
        #expect(await eventually { harness.emitter.events == [.down(key("1"))] })

        harness.driver.pause()
        #expect(harness.driver.isPaused)
        #expect(harness.emitter.events == [.down(key("1")), .up(key("1"))])

        let held = guitarMessage(report([fretOffset: fretBlack1, whammyOffset: whammyFullyPressed]))
        transport.feed(held)
        #expect(await eventually { harness.driver.activeControls == [.black1, .whammy] })
        #expect(harness.emitter.events == [.down(key("1")), .up(key("1"))])

        harness.driver.resume()
        transport.feed(held)
        #expect(await eventually { harness.emitter.events.count == 4 })
        #expect(harness.emitter.events.suffix(2) == [.down(key("x")), .down(key("1"))])
        await harness.driver.stop()
    }

    @Test("stop releases the keys, closes the dongle and goes quiet")
    func stopReleases() async {
        let transport = FakeTransport()
        let harness = Harness(connector: FakeConnector([.success(transport)]))
        await harness.arrive(waitingFor: transport)
        transport.feed(guitarMessage(report([fretOffset: fretBlack1])))
        #expect(await eventually { harness.emitter.events == [.down(key("1"))] })

        await harness.driver.stop()
        #expect(harness.emitter.events == [.down(key("1")), .up(key("1"))])
        #expect(transport.closed)
        #expect(harness.driver.status == .waitingForDongle)
        #expect(harness.driver.snapshot == nil)
    }

    @Test("stop while no dongle is present is harmless, and start works again afterwards")
    func stopWhileWaiting() async {
        let harness = Harness(connector: FakeConnector([]))
        harness.driver.start()
        await harness.driver.stop()
        await harness.driver.stop()
        #expect(harness.driver.status == .waitingForDongle)
    }

    @Test("a silent guitar drops back to dongle ready and releases its keys")
    func guitarGoesSilent() async {
        let transport = FakeTransport()
        let harness = Harness(connector: FakeConnector([.success(transport)]))
        await harness.arrive(waitingFor: transport)
        transport.feed(guitarMessage(report([fretOffset: fretBlack1])))
        #expect(await eventually { harness.driver.status == .guitarActive })

        harness.clock.advance(by: Harness.fastTiming.guitarTimeout + 0.5)
        #expect(await eventually { harness.driver.status == .dongleReady })
        #expect(harness.emitter.events == [.down(key("1")), .up(key("1"))])
        #expect(harness.driver.snapshot == nil)
        await harness.driver.stop()
    }

    @Test("the keep-alive is resent every eight seconds")
    func keepAliveResent() async {
        let transport = FakeTransport()
        let harness = Harness(connector: FakeConnector([.success(transport)]))
        await harness.arrive(waitingFor: transport)
        #expect(await eventually { transport.written.count == 4 })
        harness.clock.advance(by: GipSession.keepAliveInterval + 0.1)
        #expect(await eventually { transport.written.count == 5 })
        #expect(commands(of: [transport.written[4]]) == [GipCommand.ghlOutput.rawValue])
        await harness.driver.stop()
    }

    @Test("reconfigure releases the old sink and uses the new one")
    func reconfigure() async {
        let transport = FakeTransport()
        let harness = Harness(connector: FakeConnector([.success(transport)]))
        await harness.arrive(waitingFor: transport)
        transport.feed(guitarMessage(report([fretOffset: fretBlack1])))
        #expect(await eventually { harness.emitter.events == [.down(key("1"))] })

        let newEmitter = RecordingEmitter()
        var keymap = Keymap.default
        keymap.bindings[.black1] = key("z")
        harness.driver.reconfigure(
            sink: KeyboardSink(keymap: keymap, emitter: newEmitter), thresholds: keymap.thresholds)
        #expect(harness.emitter.events == [.down(key("1")), .up(key("1"))])

        transport.feed(guitarMessage(report([fretOffset: fretBlack1])))
        #expect(await eventually { newEmitter.events == [.down(key("z"))] })
        await harness.driver.stop()
    }

    @Test("every observed packet is reported to the packet observer")
    func packetObserver() async {
        let transport = FakeTransport()
        let monitor = FakeMonitor()
        var seen: [(PacketDirection, UInt8)] = []
        let driver = GuitarDriver(
            monitor: monitor,
            connector: FakeConnector([.success(transport)]),
            sink: KeyboardSink(keymap: .default, emitter: RecordingEmitter()),
            timing: Harness.fastTiming,
            packetObserver: { seen.append(($0, $1.command)) }
        )
        driver.start()
        monitor.send(.arrived)
        #expect(await eventually { seen.count == 4 })
        transport.feed(guitarMessage(idleReport))
        #expect(await eventually { seen.count == 5 })
        #expect(seen[4].0 == .received)
        #expect(seen[4].1 == GipCommand.ghlGuitarInput.rawValue)
        #expect(seen[0].0 == .sent)
        await driver.stop()
    }

    @Test("stop returns promptly even when a write is stalled")
    func stopWithStalledWrite() async {
        let transport = FakeTransport()
        transport.stallWrites()
        let harness = Harness(connector: FakeConnector([.success(transport)]))
        harness.driver.start()
        harness.monitor.send(.arrived)
        #expect(await eventually { transport.stalledWriteCount == 1 })

        let started = ContinuousClock.now
        await harness.driver.stop()
        #expect(ContinuousClock.now - started < .seconds(1))
        #expect(transport.closed)
        #expect(harness.driver.status == .waitingForDongle)
    }

    @Test("a failed keep-alive write releases the keys, reports the error and reconnects")
    func keepAliveWriteFailure() async {
        let first = FakeTransport()
        let second = FakeTransport()
        let harness = Harness(connector: FakeConnector([.success(first), .success(second)]))
        await harness.arrive(waitingFor: first)
        first.feed(guitarMessage(report([fretOffset: fretBlack1])))
        #expect(await eventually { harness.emitter.events == [.down(key("1"))] })

        let writeFailure = DongleError.ioFailure(operation: "write", code: kIOReturnBadArgument)
        var statuses: [DriverStatus] = []
        let subscription = harness.driver.$status.sink { statuses.append($0) }
        defer { subscription.cancel() }
        first.failWrites(from: 0, with: writeFailure)
        harness.clock.advance(by: GipSession.keepAliveInterval + 0.1)
        #expect(await eventually { statuses.contains(.error(writeFailure.localizedDescription)) })
        #expect(await eventually { harness.emitter.events == [.down(key("1")), .up(key("1"))] })
        #expect(await eventually { second.written.count == 4 })
        #expect(first.closed)
        await harness.driver.stop()
    }

    @Test("the tilt state does not leak across a reconnect")
    func detectorResetsOnReconnect() async {
        let first = FakeTransport()
        let second = FakeTransport()
        let harness = Harness(connector: FakeConnector([.success(first), .success(second)]))
        await harness.arrive(waitingFor: first)
        first.feed(guitarMessage(report([tiltOffset: raisedTilt])))
        #expect(await eventually { harness.driver.activeControls == [.tilt] })
        first.fail(DongleError.disconnected)
        #expect(await eventually { second.written.count == 4 })

        let insideBand = UInt8(Thresholds.defaultTilt - 5)
        second.feed(guitarMessage(report([tiltOffset: insideBand, fretOffset: fretBlack1])))
        #expect(await eventually { harness.driver.activeControls == [.black1] })
        await harness.driver.stop()
    }

    @Test("a monitor that stops by itself is reported as an error")
    func monitorStops() async {
        let harness = Harness(connector: FakeConnector([]))
        harness.driver.start()
        harness.monitor.finish()
        #expect(
            await eventually {
                if case .error(let message) = harness.driver.status { return message.contains("monitor") }
                return false
            }
        )
        await harness.driver.stop()
    }

    @Test("stop and removal never publish an error status", arguments: [true, false])
    func noErrorOnDeliberateTeardown(removal: Bool) async {
        let transport = FakeTransport()
        transport.stallWrites()
        let harness = Harness(connector: FakeConnector([.success(transport)]))
        var statuses: [DriverStatus] = []
        let subscription = harness.driver.$status.sink { statuses.append($0) }
        defer { subscription.cancel() }
        harness.driver.start()
        harness.monitor.send(.arrived)
        #expect(await eventually { transport.stalledWriteCount == 1 })

        if removal {
            harness.monitor.send(.removed)
            #expect(await eventually { harness.driver.status == .waitingForDongle })
        }
        await harness.driver.stop()
        #expect(!statuses.contains { if case .error = $0 { true } else { false } })
    }
}

private struct UnexpectedFailure: LocalizedError {
    static let secret = "unexpected-failure-text-with-user-data"
    var errorDescription: String? { Self.secret }
}

private let statusMessage = GipPacket(
    command: .status, flags: .system, sequence: 2, payload: Data([0x83])
).encoded()

private func isReadFailure(_ event: LogEvent) -> Bool {
    if case .readFailed = event { return true }
    return false
}

@MainActor
@Suite("Guitar driver event log", .serialized)
struct GuitarDriverEventLogTests {
    private func status(_ status: DriverStatus) -> LogEvent { .driverStatus(status) }

    @Test("arrival, ready, active, silence and removal leave a trail with the released key count")
    func fullLifecycle() async {
        let transport = FakeTransport()
        let harness = Harness(connector: FakeConnector([.success(transport)]))
        await harness.arrive(waitingFor: transport)
        transport.feed(guitarMessage(report([fretOffset: fretBlack1])))
        #expect(await eventually { harness.driver.status == .guitarActive })

        harness.clock.advance(by: Harness.fastTiming.guitarTimeout + 0.5)
        #expect(await eventually { harness.driver.status == .dongleReady })
        transport.feed(guitarMessage(report([fretOffset: fretBlack1])))
        #expect(await eventually { harness.driver.status == .guitarActive })
        harness.monitor.send(.removed)
        #expect(await eventually { harness.driver.status == .waitingForDongle })

        #expect(
            harness.meaningfulEvents == [
                .dongleArrived, status(.connecting), status(.dongleReady), status(.guitarActive),
                .guitarSilent, .inputReleased(count: 1, reason: .silence), status(.dongleReady),
                status(.guitarActive),
                .dongleRemoved, .inputReleased(count: 1, reason: .disconnect), status(.waitingForDongle),
            ])
        await harness.driver.stop()
    }

    @Test("a busy dongle is logged once, not on every retry")
    func busyDongleIsDeduplicated() async {
        let transport = FakeTransport()
        let busy: Result<FakeTransport, Error> = .failure(DongleError.exclusiveAccess)
        let harness = Harness(connector: FakeConnector([busy, busy, busy, .success(transport)]))
        await harness.arrive(waitingFor: transport)
        #expect(await eventually { harness.driver.status == .dongleReady })

        #expect(harness.connector.attempts == 4)
        #expect(
            harness.meaningfulEvents == [
                .dongleArrived, status(.connecting), .dongleBusy,
                status(.error(DongleError.exclusiveAccess.localizedDescription)), status(.dongleReady),
            ])
        await harness.driver.stop()
    }

    @Test("a different failure after the first is still logged, once")
    func differentFailureIsLogged() async {
        let transport = FakeTransport()
        let busy: Result<FakeTransport, Error> = .failure(DongleError.exclusiveAccess)
        let noGip: Result<FakeTransport, Error> = .failure(DongleError.noGipInterface)
        let harness = Harness(connector: FakeConnector([busy, busy, noGip, noGip, .success(transport)]))
        await harness.arrive(waitingFor: transport)
        #expect(await eventually { harness.driver.status == .dongleReady })

        let noGipText = DongleError.noGipInterface.localizedDescription
        #expect(
            harness.meaningfulEvents == [
                .dongleArrived, status(.connecting), .dongleBusy,
                status(.error(DongleError.exclusiveAccess.localizedDescription)),
                .connectFailed(.dongle(.noGipInterface)), status(.error(noGipText)), status(.dongleReady),
            ])
        await harness.driver.stop()
    }

    @Test("the same failure after a healthy stretch is logged again")
    func sameFailureAfterHealthyStatus() async {
        let transports = [FakeTransport(), FakeTransport(), FakeTransport()]
        let harness = Harness(connector: FakeConnector(transports.map { .success($0) }))
        let failure = DongleError.ioFailure(operation: "read", code: kIOReturnBadArgument)
        await harness.arrive(waitingFor: transports[0])
        for (index, transport) in transports.enumerated() {
            if index > 0 { #expect(await eventually { transport.written.count == 4 }) }
            if index < 2 {
                transport.feed(guitarMessage(idleReport))
                #expect(await eventually { harness.driver.status == .guitarActive })
            }
            transport.fail(failure)
            #expect(await eventually { harness.events.events.count(where: isReadFailure) >= min(index + 1, 2) })
        }
        #expect(await eventually { harness.connector.attempts >= 4 })

        #expect(harness.events.events.count(where: isReadFailure) == 2)
        await harness.driver.stop()
    }

    @Test("unplugging the dongle ends the episode, so the same failure is logged again on return")
    func removalEndsTheEpisode() async {
        let busy: Result<FakeTransport, Error> = .failure(DongleError.exclusiveAccess)
        let harness = Harness(connector: FakeConnector([busy, busy, busy, busy]))
        await harness.arrive()
        #expect(await eventually { harness.events.events.contains(.dongleBusy) })
        harness.monitor.send(.removed)
        #expect(await eventually { harness.driver.status == .waitingForDongle })
        harness.monitor.send(.arrived)
        #expect(await eventually { harness.events.events.count(where: { $0 == .dongleBusy }) == 2 })
        await harness.driver.stop()
    }

    @Test("a connection that only exchanges status messages and stays up long enough ends the episode")
    func healthyStretchEndsTheEpisode() async {
        let failure = DongleError.ioFailure(operation: "read", code: kIOReturnBadArgument)
        let first = FakeTransport()
        let second = FakeTransport()
        let harness = Harness(connector: FakeConnector([.success(first), .success(second)]))
        first.feed(statusMessage)
        first.fail(failure)
        await harness.arrive(waitingFor: first)
        #expect(await eventually { second.written.count == 4 })

        second.feed(statusMessage)
        harness.clock.advance(by: Harness.fastTiming.healthyStretch + 1)
        // The keep-alive that falls due is written after the tick has checked the stretch.
        #expect(await eventually { second.written.count == 5 })
        second.fail(failure)
        #expect(await eventually { harness.events.events.count(where: isReadFailure) == 2 })
        await harness.driver.stop()
    }

    @Test("a dongle that takes the handshake and fails every read is one episode, not one per retry")
    func handshakeThenReadFailureLoop() async {
        let failure = DongleError.ioFailure(operation: "read", code: kIOReturnBadArgument)
        let transports = (0..<4).map { _ in FakeTransport() }
        // The real dongle answers the handshake with a status message before the reads start failing.
        for transport in transports {
            transport.feed(statusMessage)
            transport.fail(failure)
        }
        let harness = Harness(connector: FakeConnector(transports.map { .success($0) }))
        harness.driver.start()
        harness.monitor.send(.arrived)
        #expect(await eventually { harness.connector.attempts >= 4 })
        await harness.driver.stop()

        #expect(
            harness.meaningfulEvents == [
                .dongleArrived, status(.connecting), status(.dongleReady),
                .readFailed(.dongle(failure)), status(.error(failure.localizedDescription)),
                status(.waitingForDongle),
            ])
    }

    @Test("another connect failure is logged with its description")
    func connectFailure() async {
        let harness = Harness(connector: FakeConnector([.failure(DongleError.noGipInterface)]))
        harness.driver.start()
        harness.monitor.send(.arrived)
        let expected = LogEvent.connectFailed(.dongle(.noGipInterface))
        #expect(await eventually { harness.events.events.contains(expected) })
        await harness.driver.stop()
    }

    @Test("pause, resume and stop log the reason and the count of keys they released")
    func pauseResumeStop() async {
        let transport = FakeTransport()
        let harness = Harness(connector: FakeConnector([.success(transport)]))
        await harness.arrive(waitingFor: transport)
        let held = guitarMessage(report([fretOffset: fretBlack1]))
        transport.feed(held)
        #expect(await eventually { harness.emitter.events == [.down(key("1"))] })

        harness.driver.pause()
        harness.driver.pause()
        harness.driver.resume()
        harness.driver.resume()
        transport.feed(held)
        #expect(await eventually { harness.emitter.events.count == 3 })
        await harness.driver.stop()

        let lifecycle = harness.meaningfulEvents.filter {
            switch $0 {
            case .paused, .resumed, .inputReleased: true
            default: false
            }
        }
        #expect(
            lifecycle == [
                .paused, .inputReleased(count: 1, reason: .pause), .resumed,
                .inputReleased(count: 1, reason: .stop),
            ])
    }

    @Test("pausing to quit and reconfiguring are told apart from a user pause")
    func quitAndReconfigureReasons() async {
        let transport = FakeTransport()
        let harness = Harness(connector: FakeConnector([.success(transport)]))
        await harness.arrive(waitingFor: transport)
        transport.feed(guitarMessage(report([fretOffset: fretBlack1])))
        #expect(await eventually { harness.emitter.events == [.down(key("1"))] })
        harness.driver.reconfigure(
            sink: KeyboardSink(keymap: .default, emitter: RecordingEmitter()), thresholds: Keymap.default.thresholds)
        harness.driver.pause(reason: .quit)

        #expect(harness.events.events.contains(.inputReleased(count: 1, reason: .reconfigure)))
        #expect(harness.events.events.contains(.inputReleased(count: 0, reason: .quit)))
        await harness.driver.stop()
    }

    @Test("a read failure is logged once")
    func readFailure() async {
        let first = FakeTransport()
        let second = FakeTransport()
        let harness = Harness(connector: FakeConnector([.success(first), .success(second)]))
        await harness.arrive(waitingFor: first)
        let failure = DongleError.ioFailure(operation: "read", code: kIOReturnBadArgument)
        first.fail(failure)
        #expect(await eventually { second.written.count == 4 })

        let reads = harness.events.events.filter { $0 == .readFailed(.dongle(failure)) }
        #expect(reads.count == 1)
        #expect(!harness.events.events.contains { if case .writeFailed = $0 { true } else { false } })
        await harness.driver.stop()
    }

    @Test("a failed acknowledgement write is a write failure, never a read failure")
    func ackWriteFailure() async {
        let transport = FakeTransport()
        let harness = Harness(connector: FakeConnector([.success(transport)]))
        await harness.arrive(waitingFor: transport)
        transport.failWrites(from: transport.written.count)
        let status = GipPacket(
            command: .status, flags: [.acknowledgeRequired, .system], sequence: 1, payload: Data([0x01, 0, 0, 0]))
        transport.feed(status.encoded())
        #expect(await eventually { harness.events.events.contains(.writeFailed(.dongle(.disconnected))) })
        #expect(!harness.events.events.contains(where: isReadFailure))
        await harness.driver.stop()
    }

    @Test("a failed handshake write is a write failure")
    func writeFailure() async {
        let first = FakeTransport()
        first.failWrites(from: 1)
        let harness = Harness(connector: FakeConnector([.success(first)]))
        harness.driver.start()
        harness.monitor.send(.arrived)
        let expected = LogEvent.writeFailed(.dongle(.disconnected))
        #expect(await eventually { harness.events.events.contains(expected) })
        #expect(!harness.events.events.contains { if case .readFailed = $0 { true } else { false } })
        await harness.driver.stop()
    }

    @Test("a failed keep-alive is logged as a keep-alive failure")
    func keepAliveFailure() async {
        let first = FakeTransport()
        let second = FakeTransport()
        let harness = Harness(connector: FakeConnector([.success(first), .success(second)]))
        await harness.arrive(waitingFor: first)
        let failure = DongleError.ioFailure(operation: "write", code: kIOReturnBadArgument)
        first.failWrites(from: 0, with: failure)
        harness.clock.advance(by: GipSession.keepAliveInterval + 0.1)

        #expect(await eventually { second.written.count == 4 })
        #expect(harness.events.events.contains(.keepAliveFailed(.dongle(failure))))
        await harness.driver.stop()
    }

    @Test("a deliberate stop logs no failure")
    func stopLogsNoFailure() async {
        let transport = FakeTransport()
        transport.stallWrites()
        let harness = Harness(connector: FakeConnector([.success(transport)]))
        harness.driver.start()
        harness.monitor.send(.arrived)
        #expect(await eventually { transport.stalledWriteCount == 1 })
        await harness.driver.stop()
        #expect(harness.events.events.allSatisfy { $0.level != .error && $0.level != .fault })
    }

    @Test("no event names a key, a control or a report value")
    func eventsCarryNoInputIdentity() async {
        let transport = FakeTransport()
        let harness = Harness(connector: FakeConnector([.success(transport)]))
        await harness.arrive(waitingFor: transport)
        transport.feed(guitarMessage(report([fretOffset: fretBlack1, tiltOffset: raisedTilt, whammyOffset: 0xFF])))
        #expect(await eventually { harness.emitter.events.count == 3 })
        harness.driver.pause()
        await harness.driver.stop()

        let events = harness.events.events
        #expect(!events.isEmpty)
        for event in events {
            assertCarriesOnlyCountsAndText(event)
            for control in Control.allCases where control != .pause {
                #expect(!event.message.contains(control.rawValue), "\(event.message)")
            }
            for name in KeyCode.allNames where name.count > 1 {
                #expect(!event.message.contains(name), "\(event.message)")
            }
        }
    }

    @Test("the text of an unexpected error and the bytes of a report never reach the log")
    func noArbitraryTextInTheLog() async {
        let transport = FakeTransport()
        let harness = Harness(connector: FakeConnector([.success(transport)]))
        await harness.arrive(waitingFor: transport)
        let payload = report([fretOffset: fretBlack1, tiltOffset: raisedTilt, whammyOffset: 0xFF])
        transport.feed(guitarMessage(payload))
        #expect(await eventually { harness.driver.status == .guitarActive })
        transport.fail(UnexpectedFailure())
        #expect(await eventually { harness.events.events.contains(where: isReadFailure) })
        await harness.driver.stop()

        let forbidden = [UnexpectedFailure.secret, payload.hexString, guitarMessage(payload).hexString]
        for event in harness.events.events {
            for text in forbidden {
                #expect(!event.message.contains(text), "\(event.message)")
            }
        }
    }

    private func assertCarriesOnlyCountsAndText(_ value: Any) {
        for child in Mirror(reflecting: value).children {
            switch child.value {
            case is Control, is KeyCode, is Set<Control>, is GuitarState, is GuitarSnapshot:
                Issue.record("event payload carries input: \(type(of: child.value))")
            default:
                assertCarriesOnlyCountsAndText(child.value)
            }
        }
    }
}
