import Foundation

/// Host side of the GIP conversation with the GHL dongle, free of any USB I/O.
public struct GipSession: Sendable {
    public static let keepAliveInterval: TimeInterval = 8
    public static let chunkedNotSupported = "chunked packet not supported: not reassembled, not acknowledged"

    private var sequence = SequenceCounter()
    private var nextKeepAliveAt: TimeInterval?

    public init() {}

    /// Same order Linux xpad uses for every Xbox One device (facts only); it does not wait for the announce.
    public mutating func startPackets() -> [GipPacket] {
        [
            .powerOn(sequence: sequence.next()),
            .ledOn(sequence: sequence.next()),
            .authenticationDone(sequence: sequence.next()),
        ]
    }

    public func unsupportedReason(for packet: GipPacket) -> String? {
        packet.flags.contains(.chunked) ? Self.chunkedNotSupported : nil
    }

    public func handle(_ packet: GipPacket) -> [GipPacket] {
        guard unsupportedReason(for: packet) == nil, packet.requiresAcknowledgement else { return [] }
        return [packet.acknowledgement()]
    }

    /// `now` is any monotonic clock in seconds.
    public mutating func duePackets(now: TimeInterval) -> [GipPacket] {
        if let nextKeepAliveAt, now < nextKeepAliveAt { return [] }
        nextKeepAliveAt = now + Self.keepAliveInterval
        return [.ghlKeepAlive()]
    }
}
