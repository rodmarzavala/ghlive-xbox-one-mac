import Foundation
import GIPProtocol
import GuitarInput
import KeyMapping
import KeyboardOutput
import USBTransport

@testable import GHLiveCore

/// Real idle report captured on hardware; byte 19 (tilt) is 0x70.
let idleReport = Data(
    [
        0x00, 0x00, 0x0F, 0x80, 0x80, 0x80, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x70, 0x00, 0x80, 0x01, 0x00, 0x02, 0x00, 0x02,
    ]
)

func report(_ changes: [Int: UInt8]) -> Data {
    var bytes = [UInt8](idleReport)
    for (offset, value) in changes { bytes[offset] = value }
    return Data(bytes)
}

/// A guitar report as the dongle sends it: one GIP message.
func guitarMessage(_ payload: Data, sequence: UInt8 = 1) -> Data {
    GipPacket(command: .ghlGuitarInput, flags: [], sequence: sequence, payload: payload).encoded()
}

enum KeyEvent: Equatable {
    case down(KeyCode)
    case up(KeyCode)
}

@MainActor
final class RecordingEmitter: KeyEmitter {
    var events: [KeyEvent] = []

    func keyDown(_ key: KeyCode) { events.append(.down(key)) }
    func keyUp(_ key: KeyCode) { events.append(.up(key)) }
}

func key(_ name: String) -> KeyCode { KeyCode.named(name)! }

final class FakeTransport: PacketTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var writtenData: [Data] = []
    private var isClosed = false
    private var stallsWrites = false
    private var stalledWrites: [CheckedContinuation<Void, Error>] = []
    private var failingFromWrite: Int?
    private var writeError: Error = DongleError.disconnected
    private let stream: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation

    init() {
        (stream, continuation) = AsyncThrowingStream.makeStream(of: Data.self)
    }

    var written: [Data] { lock.withLock { writtenData } }
    var closed: Bool { lock.withLock { isClosed } }
    var stalledWriteCount: Int { lock.withLock { stalledWrites.count } }

    /// Every write hangs until `close()`, like a write to a wedged USB pipe.
    func stallWrites() { lock.withLock { stallsWrites = true } }
    /// The write with this zero-based index, and every later one, throws.
    func failWrites(from index: Int, with error: Error = DongleError.disconnected) {
        lock.withLock {
            failingFromWrite = index
            writeError = error
        }
    }

    func feed(_ data: Data) { continuation.yield(data) }
    func fail(_ error: Error) { continuation.finish(throwing: error) }
    func endStream() { continuation.finish() }

    func incomingPackets() -> AsyncThrowingStream<Data, Error> { stream }

    func write(_ data: Data) async throws {
        let failure = lock.withLock { failingFromWrite.map { writtenData.count >= $0 } == true ? writeError : nil }
        if let failure { throw failure }
        if lock.withLock({ stallsWrites }) {
            try await withCheckedThrowingContinuation { (waiter: CheckedContinuation<Void, Error>) in
                let alreadyClosed = lock.withLock {
                    if !isClosed { stalledWrites.append(waiter) }
                    return isClosed
                }
                if alreadyClosed { waiter.resume(throwing: DongleError.disconnected) }
            }
            return
        }
        lock.withLock { writtenData.append(data) }
    }

    func close() {
        let waiters = lock.withLock {
            isClosed = true
            defer { stalledWrites = [] }
            return stalledWrites
        }
        for waiter in waiters { waiter.resume(throwing: DongleError.disconnected) }
        continuation.finish()
    }
}

final class FakeMonitor: DongleEventSource, @unchecked Sendable {
    private let stream: AsyncStream<DongleEvent>
    private let continuation: AsyncStream<DongleEvent>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: DongleEvent.self)
    }

    func send(_ event: DongleEvent) { continuation.yield(event) }
    func finish() { continuation.finish() }
    func events() -> AsyncStream<DongleEvent> { stream }
}

/// Hands out the queued transports (or errors) one per `connect()` call.
final class FakeConnector: DongleConnecting, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<FakeTransport, Error>]
    private var attemptCount = 0

    init(_ results: [Result<FakeTransport, Error>]) {
        self.results = results
    }

    var attempts: Int { lock.withLock { attemptCount } }

    func connect() async throws -> any PacketTransport {
        let result = lock.withLock {
            attemptCount += 1
            return results.isEmpty ? Result<FakeTransport, Error>.failure(DongleError.notFound) : results.removeFirst()
        }
        return try result.get()
    }
}

final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time: TimeInterval = 1000

    func now() -> TimeInterval { lock.withLock { time } }
    func advance(by seconds: TimeInterval) { lock.withLock { time += seconds } }
}

/// Polls until the condition holds, yielding to the other main-actor work in between.
@MainActor
func eventually(timeout: Duration = .seconds(3), _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}
