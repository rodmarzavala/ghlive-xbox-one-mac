import time
from collections.abc import Callable

from ghlproto.gip import GipPacket, GipTransferError, decode_packets, encode_packet
from ghlproto.packet_log import PacketLogger
from ghlproto.session import GipSession
from ghlproto.transport import PacketTransport

READ_TIMEOUT_MS = 100
RUN_FOREVER = 0.0


def send_all(transport: PacketTransport, logger: PacketLogger, packets: list[GipPacket]) -> None:
    for packet in packets:
        transport.write(encode_packet(packet))
        logger.sent(packet)


def run_session(
    transport: PacketTransport,
    logger: PacketLogger,
    seconds: float,
    clock: Callable[[], float] = time.monotonic,
) -> None:
    session = GipSession()
    deadline = clock() + seconds if seconds > RUN_FOREVER else float("inf")
    send_all(transport, logger, session.start())
    while clock() < deadline:
        send_all(transport, logger, session.due_packets(clock()))
        data = transport.read(READ_TIMEOUT_MS)
        if data is None:
            continue
        try:
            packets = decode_packets(data)
        except GipTransferError as error:
            handle_packets(session, transport, logger, error.packets)
            logger.undecodable(error.tail, error.reason)
            continue
        handle_packets(session, transport, logger, packets)


def handle_packets(
    session: GipSession, transport: PacketTransport, logger: PacketLogger, packets: list[GipPacket]
) -> None:
    for packet in packets:
        logger.received(packet)
        reason = session.unsupported_reason(packet)
        if reason:
            logger.note(reason)
        send_all(transport, logger, session.handle(packet))
