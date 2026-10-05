import Foundation
import Testing

@testable import GIPProtocol

private let startTime: TimeInterval = 100

@Suite("GIP session")
struct SessionTests {
    @Test("start sends power on, LED and auth done in order")
    func startOrder() {
        var session = GipSession()
        let commands = session.startPackets().map(\.command)
        #expect(commands == [GipCommand.power, .led, .authenticate].map(\.rawValue))
    }

    @Test("start uses increasing sequences")
    func startSequences() {
        var session = GipSession()
        #expect(session.startPackets().map(\.sequence) == [1, 2, 3])
    }

    @Test("packets that require it are acknowledged")
    func acknowledges() {
        let announce = GipPacket(
            command: .announce,
            flags: [.system, .acknowledgeRequired],
            sequence: 9,
            payload: Data(count: 28)
        )
        let replies = GipSession().handle(announce)
        #expect(replies.map(\.command) == [GipCommand.acknowledge.rawValue])
        #expect(replies.first?.sequence == 9)
    }

    @Test("plain input is not acknowledged")
    func ignoresPlainInput() {
        let input = GipPacket(command: .ghlGuitarInput, flags: [], sequence: 1, payload: Data(count: 27))
        #expect(GipSession().handle(input).isEmpty)
    }

    @Test("a chunked packet is not acknowledged and is reported")
    func chunkedUnsupported() {
        let chunked = GipPacket(
            command: .announce,
            flags: [.acknowledgeRequired, .chunked],
            sequence: 1,
            payload: Data(count: 8)
        )
        let session = GipSession()
        #expect(session.handle(chunked).isEmpty)
        #expect(session.unsupportedReason(for: chunked) == GipSession.chunkedNotSupported)
    }

    @Test("a plain packet has no unsupported reason")
    func plainSupported() {
        let status = GipPacket(command: .status, flags: .system, sequence: 1, payload: Data())
        #expect(GipSession().unsupportedReason(for: status) == nil)
    }
}

@Suite("GIP keep-alive")
struct KeepAliveTests {
    @Test("the first keep-alive is due immediately")
    func firstDue() {
        var session = GipSession()
        #expect(session.duePackets(now: startTime).map(\.command) == [GipCommand.ghlOutput.rawValue])
    }

    @Test("it is not due again before the interval")
    func notDueEarly() {
        var session = GipSession()
        _ = session.duePackets(now: startTime)
        #expect(session.duePackets(now: startTime + GipSession.keepAliveInterval - 0.1).isEmpty)
    }

    @Test("it is due again after the interval")
    func dueAgain() {
        var session = GipSession()
        _ = session.duePackets(now: startTime)
        #expect(session.duePackets(now: startTime + GipSession.keepAliveInterval).count == 1)
    }

    @Test("the interval is eight seconds")
    func intervalMatchesDocs() {
        #expect(GipSession.keepAliveInterval == 8)
    }
}
