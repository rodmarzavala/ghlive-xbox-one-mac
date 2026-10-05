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
            now: { clock.now() }
        )
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
