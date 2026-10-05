import Combine
import Foundation
import GIPProtocol
import GuitarInput
import KeyMapping
import KeyboardOutput
import USBTransport

public enum DriverStatus: Equatable, Sendable {
    case waitingForDongle
    case connecting
    /// Handshake sent; no guitar report seen yet (the guitar may be off or out of range).
    case dongleReady
    /// A guitar report arrived less than `Timing.guitarTimeout` ago.
    case guitarActive
    case error(String)
}

/// The latest guitar report and the controls it activates, for an input monitor.
public struct GuitarSnapshot: Equatable, Sendable {
    public let state: GuitarState
    public let controls: Set<Control>

    public init(state: GuitarState, controls: Set<Control>) {
        self.state = state
        self.controls = controls
    }
}

public enum PacketDirection: Sendable {
    case received
    case sent
}

/// Runs the whole pipeline: dongle monitor, connection, GIP session, report parser, control detector and
/// output sink. Reconnects by itself and guarantees `releaseAll` on stop, disconnect, pause and silence.
///
/// Everything here is `@MainActor`: USB completions are bridged in through `AsyncStream`s, so state is only
/// ever touched on the main actor and it is directly observable from SwiftUI (`ObservableObject`).
@MainActor
public final class GuitarDriver: ObservableObject {
    public struct Timing: Sendable {
        /// Pause before reconnecting after a failure while the dongle is still plugged in.
        public var retryDelay: Duration = .seconds(2)
        /// How often keep-alives and guitar silence are checked.
        public var tick: Duration = .milliseconds(250)
        /// A guitar that has not reported for this long is no longer `guitarActive`.
        public var guitarTimeout: TimeInterval = 1

        public init() {}
    }

    @Published public private(set) var status: DriverStatus = .waitingForDongle
    @Published public private(set) var snapshot: GuitarSnapshot?
    @Published public private(set) var isPaused = false

    public var guitarState: GuitarState? { snapshot?.state }
    public var activeControls: Set<Control> { snapshot?.controls ?? [] }

    private let monitor: any DongleEventSource
    private let connector: any DongleConnecting
    private let timing: Timing
    private let now: @Sendable () -> TimeInterval
    private let log: (String) -> Void
    private let packetObserver: (PacketDirection, GipPacket) -> Void

    private var sink: any OutputSink
    private var detector: ControlDetector
    private var gipSession = GipSession()
    private var lastReportAt: TimeInterval?
    private var hasWarnedAboutReports = false
    private var runTask: Task<Void, Never>?

    public init(
        monitor: any DongleEventSource,
        connector: any DongleConnecting,
        sink: any OutputSink,
        thresholds: Thresholds = Thresholds(),
        timing: Timing = Timing(),
        now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        log: @escaping (String) -> Void = { _ in },
        packetObserver: @escaping (PacketDirection, GipPacket) -> Void = { _, _ in }
    ) {
        self.monitor = monitor
        self.connector = connector
        self.sink = sink
        self.detector = ControlDetector(thresholds: thresholds)
        self.timing = timing
        self.now = now
        self.log = log
        self.packetObserver = packetObserver
    }

    /// The real thing: IOKit monitor and connection, keyboard sink on the given emitter.
    public static func live(
        keymap: Keymap,
        emitter: any KeyEmitter,
        log: @escaping (String) -> Void = { _ in },
        packetObserver: @escaping (PacketDirection, GipPacket) -> Void = { _, _ in }
    ) -> GuitarDriver {
        GuitarDriver(
            monitor: DongleMonitor(),
            connector: DongleConnector(),
            sink: KeyboardSink(keymap: keymap, emitter: emitter),
            thresholds: keymap.thresholds,
            log: log,
            packetObserver: packetObserver
        )
    }

    // MARK: Lifecycle

    /// Starts watching for the dongle. Calling it again while running does nothing.
    public func start() {
        guard runTask == nil else { return }
        runTask = Task { await watchDongle() }
    }

    /// Stops everything and waits until the keys are released and the dongle is closed.
    public func stop() async {
        guard let task = runTask else { return }
        runTask = nil
        task.cancel()
        await task.value
        resetInput()
        setStatus(.waitingForDongle)
    }

    /// Releases every key and ignores guitar input until `resume()`. The dongle stays connected.
    public func pause() {
        guard !isPaused else { return }
        isPaused = true
        sink.releaseAll()
    }

    public func resume() {
        isPaused = false
    }

    /// Swaps the output, for example after the keymap changed. The old sink is released first.
    public func reconfigure(sink newSink: any OutputSink, thresholds: Thresholds) {
        sink.releaseAll()
        sink = newSink
        detector = ControlDetector(thresholds: thresholds)
    }

    // MARK: Dongle presence

    private func watchDongle() async {
        var connection: Task<Void, Never>?
        for await event in monitor.events() {
            switch event {
            case .arrived:
                guard connection == nil else { continue }
                connection = Task { await keepConnected() }
            case .removed:
                log("dongle removed")
                connection?.cancel()
                await connection?.value
                connection = nil
                resetInput()
                setStatus(.waitingForDongle)
            }
        }
        connection?.cancel()
        await connection?.value
        resetInput()
    }

    // MARK: Connection

    private func keepConnected() async {
        while !Task.isCancelled {
            setStatus(.connecting)
            do {
                let transport = try await connector.connect()
                // A write to a wedged pipe never completes; closing the transport is what unblocks it.
                try await withTaskCancellationHandler {
                    try await run(on: transport)
                } onCancel: {
                    transport.close()
                }
                if Task.isCancelled { break }
                setStatus(.error(DongleError.disconnected.localizedDescription))
            } catch is CancellationError {
                break
            } catch {
                setStatus(.error(error.localizedDescription))
            }
            resetInput()
            guard (try? await Task.sleep(for: timing.retryDelay)) != nil else { break }
        }
        resetInput()
    }

    private func run(on transport: any PacketTransport) async throws {
        defer {
            transport.close()
            resetInput()
        }
        gipSession = GipSession()
        let startPackets = gipSession.startPackets()
        try await send(startPackets, over: transport)
        setStatus(.dongleReady)
        let reader = Task { try await readPackets(from: transport) }
        let keepAliveTask = Task {
            do {
                try await keepAlive(over: transport)
            } catch is CancellationError {
                return nil as Error?
            } catch {
                reader.cancel()
                return error
            }
            return nil
        }
        defer { keepAliveTask.cancel() }
        try await withTaskCancellationHandler {
            try await reader.value
        } onCancel: {
            reader.cancel()
        }
        keepAliveTask.cancel()
        if let failure = await keepAliveTask.value, !Task.isCancelled { throw failure }
    }

    private func readPackets(from transport: any PacketTransport) async throws {
        for try await data in transport.incomingPackets() {
            let transfer = decodePackets(data)
            for packet in transfer.packets {
                try await handle(packet, over: transport)
            }
            if let failure = transfer.failure {
                log("undecodable bytes (\(failure.error)): \(failure.tail.hexString)")
            }
        }
    }

    private func handle(_ packet: GipPacket, over transport: any PacketTransport) async throws {
        packetObserver(.received, packet)
        if let reason = gipSession.unsupportedReason(for: packet) { log(reason) }
        try await send(gipSession.handle(packet), over: transport)
        if packet.knownCommand == .ghlGuitarInput { handleGuitarReport(packet.payload) }
    }

    /// Sends due keep-alives and notices when the guitar has gone quiet.
    private func keepAlive(over transport: any PacketTransport) async throws {
        while true {
            try await Task.sleep(for: timing.tick)
            let time = now()
            try await send(gipSession.duePackets(now: time), over: transport)
            releaseIfGuitarSilent(at: time)
        }
    }

    private func send(_ packets: [GipPacket], over transport: any PacketTransport) async throws {
        for packet in packets {
            try await transport.write(packet.encoded())
            packetObserver(.sent, packet)
        }
    }

    // MARK: Input

    private func handleGuitarReport(_ payload: Data) {
        let state: GuitarState
        do {
            state = try parseGuitarReport(payload)
        } catch {
            if !hasWarnedAboutReports { log("ignoring malformed guitar report: \(error)") }
            hasWarnedAboutReports = true
            return
        }
        let controls = detector.detect(state)
        lastReportAt = now()
        setStatus(.guitarActive)
        publish(GuitarSnapshot(state: state, controls: controls))
        if !isPaused { sink.apply(state: state, controls: controls) }
    }

    private func releaseIfGuitarSilent(at time: TimeInterval) {
        guard status == .guitarActive, let lastReportAt, time - lastReportAt > timing.guitarTimeout else { return }
        log("guitar silent, releasing keys")
        resetInput()
        setStatus(.dongleReady)
    }

    private func resetInput() {
        sink.releaseAll()
        detector.reset()
        lastReportAt = nil
        publish(nil)
    }

    private func publish(_ newSnapshot: GuitarSnapshot?) {
        if snapshot != newSnapshot { snapshot = newSnapshot }
    }

    private func setStatus(_ newStatus: DriverStatus) {
        guard status != newStatus else { return }
        status = newStatus
        log("status: \(newStatus)")
    }
}
