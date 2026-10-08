import Combine
import Foundation
import GIPProtocol
import GuitarInput
import KeyMapping
import KeyboardOutput
import USBTransport

public enum DriverStatus: Hashable, Sendable {
    case waitingForDongle
    case connecting
    /// Handshake sent; no guitar report seen yet (the guitar may be off or out of range).
    case dongleReady
    /// A guitar report arrived less than `Timing.guitarTimeout` ago.
    case guitarActive
    case error(String)
}

extension DriverStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .waitingForDongle: "waiting for the dongle"
        case .connecting: "connecting"
        case .dongleReady: "dongle ready, no guitar report yet"
        case .guitarActive: "guitar active"
        case .error(let message): "error: \(message)"
        }
    }
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
        /// A connection that stays up this long counts as healthy, which ends a logged failure episode. Far
        /// longer than `retryDelay`, so a dongle that fails right after each handshake stays one episode.
        public var healthyStretch: TimeInterval = 30

        public init() {}
    }

    static let monitorStoppedMessage = "The USB monitor stopped, so the dongle can no longer be detected."

    @Published public private(set) var status: DriverStatus = .waitingForDongle
    @Published public private(set) var snapshot: GuitarSnapshot?
    @Published public private(set) var isPaused = false

    public var guitarState: GuitarState? { snapshot?.state }
    public var activeControls: Set<Control> { snapshot?.controls ?? [] }

    private let monitor: any DongleEventSource
    private let connector: any DongleConnecting
    private let timing: Timing
    private let now: @Sendable () -> TimeInterval
    private let log: @Sendable (String) -> Void
    private let eventLog: any EventLog
    private let packetObserver: (PacketDirection, GipPacket) -> Void

    private var sink: any OutputSink
    private var detector: ControlDetector
    private var gipSession = GipSession()
    private var lastReportAt: TimeInterval?
    private var connectedAt: TimeInterval?
    private var hasWarnedAboutReports = false
    private var runTask: Task<Void, Never>?
    /// Failures already logged since the last healthy state, so a retry loop logs each one once.
    private var reportedFailures: Set<LogEvent> = []

    public init(
        monitor: any DongleEventSource,
        connector: any DongleConnecting,
        sink: any OutputSink,
        thresholds: Thresholds = Thresholds(),
        timing: Timing = Timing(),
        now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        log: @escaping @Sendable (String) -> Void = { _ in },
        eventLog: any EventLog = NullEventLog(),
        packetObserver: @escaping (PacketDirection, GipPacket) -> Void = { _, _ in }
    ) {
        self.monitor = monitor
        self.connector = connector
        self.sink = sink
        self.detector = ControlDetector(thresholds: thresholds)
        self.timing = timing
        self.now = now
        self.log = log
        self.eventLog = eventLog
        self.packetObserver = packetObserver
    }

    /// The real thing: IOKit monitor and connection, keyboard sink on the given emitter.
    public static func live(
        keymap: Keymap,
        emitter: any KeyEmitter,
        log: @escaping @Sendable (String) -> Void = { _ in },
        eventLog: any EventLog = NullEventLog(),
        packetObserver: @escaping (PacketDirection, GipPacket) -> Void = { _, _ in }
    ) -> GuitarDriver {
        GuitarDriver(
            monitor: DongleMonitor(log: log),
            connector: DongleConnector(),
            sink: KeyboardSink(keymap: keymap, emitter: emitter),
            thresholds: keymap.thresholds,
            log: log,
            eventLog: eventLog,
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
        // Before the cancellation tears the connection down, so the log credits the release to the stop.
        releaseKeys(because: .stop)
        task.cancel()
        await task.value
        releaseInput(because: .stop)
        setStatus(.waitingForDongle)
    }

    /// Releases every key and ignores guitar input until `resume()`. The dongle stays connected.
    public func pause(reason: ReleaseReason = .pause) {
        guard !isPaused else { return }
        isPaused = true
        eventLog.record(.paused)
        releaseKeys(because: reason)
    }

    public func resume() {
        guard isPaused else { return }
        isPaused = false
        eventLog.record(.resumed)
    }

    /// Swaps the output, for example after the keymap changed. The old sink is released first.
    public func reconfigure(sink newSink: any OutputSink, thresholds: Thresholds) {
        releaseKeys(because: .reconfigure)
        sink = newSink
        detector = ControlDetector(thresholds: thresholds)
    }

    // MARK: Dongle presence

    private func watchDongle() async {
        var connection: Task<Void, Never>?
        for await event in monitor.events() {
            switch event {
            case .arrived:
                eventLog.record(.dongleArrived)
                guard connection == nil else { continue }
                connection = Task { await keepConnected() }
            case .removed:
                eventLog.record(.dongleRemoved)
                connection?.cancel()
                await connection?.value
                connection = nil
                releaseInput(because: .disconnect)
                setStatus(.waitingForDongle)
            }
        }
        connection?.cancel()
        await connection?.value
        releaseInput(because: .disconnect)
        if !Task.isCancelled { setStatus(.error(Self.monitorStoppedMessage)) }
    }

    // MARK: Connection

    private func keepConnected() async {
        while !Task.isCancelled {
            setStatus(.connecting)
            do {
                let transport = try await openTransport()
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
                // Closing the transport on cancellation makes the pending write throw; that is not a fault.
                if Task.isCancelled { break }
                setFailedStatus(error)
            }
            releaseInput(because: .disconnect)
            guard (try? await Task.sleep(for: timing.retryDelay)) != nil else { break }
        }
        releaseInput(because: .disconnect)
    }

    private func openTransport() async throws -> any PacketTransport {
        do {
            let transport = try await connector.connect()
            // Connecting says nothing about a dongle that keeps failing after the handshake.
            if !reportedFailures.contains(where: \.isConnectionFailure) { reportedFailures.removeAll() }
            return transport
        } catch {
            report(error) { reason in
                reason == FailureReason(DongleError.exclusiveAccess) ? .dongleBusy : .connectFailed(reason)
            }
            throw error
        }
    }

    private func run(on transport: any PacketTransport) async throws {
        defer {
            transport.close()
            connectedAt = nil
            releaseInput(because: .disconnect)
        }
        gipSession = GipSession()
        let startPackets = gipSession.startPackets()
        try await send(startPackets, over: transport, failure: { .writeFailed($0) })
        setStatus(.dongleReady)
        connectedAt = now()
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
        var failedWhileHandling = false
        do {
            for try await data in transport.incomingPackets() {
                do {
                    try await process(data, over: transport)
                } catch {
                    failedWhileHandling = true
                    throw error
                }
            }
        } catch {
            // Handling reports its own write failures; only an error from the stream itself is a read failure.
            if !failedWhileHandling { report(error) { .readFailed($0) } }
            throw error
        }
    }

    private func process(_ data: Data, over transport: any PacketTransport) async throws {
        let transfer = decodePackets(data)
        for packet in transfer.packets {
            try await handle(packet, over: transport)
        }
        if let failure = transfer.failure {
            log("undecodable bytes (\(failure.error)): \(failure.tail.hexString)")
        }
    }

    private func handle(_ packet: GipPacket, over transport: any PacketTransport) async throws {
        packetObserver(.received, packet)
        if let reason = gipSession.unsupportedReason(for: packet) { log(reason) }
        try await send(gipSession.handle(packet), over: transport, failure: { .writeFailed($0) })
        if packet.knownCommand == .ghlGuitarInput { handleGuitarReport(packet.payload) }
    }

    /// Sends due keep-alives and notices when the guitar has gone quiet.
    private func keepAlive(over transport: any PacketTransport) async throws {
        while true {
            try await Task.sleep(for: timing.tick)
            let time = now()
            endEpisodeIfHealthy(at: time)
            try await send(gipSession.duePackets(now: time), over: transport, failure: { .keepAliveFailed($0) })
            releaseIfGuitarSilent(at: time)
        }
    }

    private func endEpisodeIfHealthy(at time: TimeInterval) {
        guard let connectedAt, time - connectedAt >= timing.healthyStretch else { return }
        self.connectedAt = nil
        reportedFailures.removeAll()
    }

    private func send(
        _ packets: [GipPacket], over transport: any PacketTransport, failure: (FailureReason) -> LogEvent
    ) async throws {
        for packet in packets {
            do {
                try await transport.write(packet.encoded())
            } catch {
                report(error, as: failure)
                throw error
            }
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
        // Only a guitar report proves the link works end to end: the dongle answers the handshake with status
        // messages even when it then fails every read.
        reportedFailures.removeAll()
        let controls = detector.detect(state)
        lastReportAt = now()
        setStatus(.guitarActive)
        publish(GuitarSnapshot(state: state, controls: controls))
        if !isPaused { sink.apply(state: state, controls: controls) }
    }

    private func releaseIfGuitarSilent(at time: TimeInterval) {
        guard status == .guitarActive, let lastReportAt, time - lastReportAt > timing.guitarTimeout else { return }
        eventLog.record(.guitarSilent)
        releaseInput(because: .silence)
        setStatus(.dongleReady)
    }

    private func releaseInput(because reason: ReleaseReason) {
        releaseKeys(because: reason)
        detector.reset()
        lastReportAt = nil
        publish(nil)
    }

    private func publish(_ newSnapshot: GuitarSnapshot?) {
        if snapshot != newSnapshot { snapshot = newSnapshot }
    }

    private func releaseKeys(because reason: ReleaseReason) {
        eventLog.record(.inputReleased(count: sink.releaseAll(), reason: reason))
    }

    private func setStatus(_ newStatus: DriverStatus, loggedAs loggedStatus: DriverStatus? = nil) {
        guard status != newStatus else { return }
        status = newStatus
        recordStatus(loggedStatus ?? newStatus)
    }

    /// The menu shows the error's own text; the log gets the publishable description of it.
    private func setFailedStatus(_ error: Error) {
        setStatus(.error(error.localizedDescription), loggedAs: .error(FailureReason(error).description))
    }

    /// A dongle that stays busy, or takes the handshake and then fails, cycles through connecting, ready and
    /// error on every retry. The loop is one problem: it is logged once and ends with the first guitar report,
    /// a connection that stays up for `healthyStretch`, or the dongle being gone.
    private func recordStatus(_ newStatus: DriverStatus) {
        let event = LogEvent.driverStatus(newStatus)
        switch newStatus {
        case .error:
            recordOnce(event)
        case .connecting, .dongleReady:
            if reportedFailures.isEmpty { eventLog.record(event) }
        case .waitingForDongle:
            reportedFailures.removeAll()
            eventLog.record(event)
        case .guitarActive:
            eventLog.record(event)
        }
    }

    private func recordOnce(_ failure: LogEvent) {
        guard reportedFailures.insert(failure).inserted else { return }
        eventLog.record(failure)
    }

    /// A failure while shutting down is not a fault: closing the transport is what makes pending I/O throw.
    private func report(_ error: Error, as event: (FailureReason) -> LogEvent) {
        guard !Task.isCancelled, !(error is CancellationError) else { return }
        recordOnce(event(FailureReason(error)))
    }
}
