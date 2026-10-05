from ghlproto.gip import (
    GipFlag,
    GipPacket,
    SequenceCounter,
    acknowledgement_for,
    authentication_done,
    ghl_keep_alive,
    led_on,
    power_on,
)

KEEP_ALIVE_INTERVAL_SECONDS = 8.0
CHUNKED_NOT_SUPPORTED = "chunked packet not supported: not reassembled, not acknowledged"


class GipSession:
    """Host side of the GIP conversation with the GHL dongle, free of any USB I/O."""

    def __init__(self) -> None:
        self._sequence = SequenceCounter()
        self._next_keep_alive_at: float | None = None

    def start(self) -> list[GipPacket]:
        # Same order Linux xpad uses for every Xbox One device; it does not wait for the announce.
        return [
            power_on(self._sequence.next()),
            led_on(self._sequence.next()),
            authentication_done(self._sequence.next()),
        ]

    def unsupported_reason(self, packet: GipPacket) -> str | None:
        return CHUNKED_NOT_SUPPORTED if packet.flags & GipFlag.CHUNKED else None

    def handle(self, packet: GipPacket) -> list[GipPacket]:
        if self.unsupported_reason(packet) or not packet.requires_acknowledgement:
            return []
        return [acknowledgement_for(packet)]

    def due_packets(self, now: float) -> list[GipPacket]:
        if self._next_keep_alive_at is not None and now < self._next_keep_alive_at:
            return []
        self._next_keep_alive_at = now + KEEP_ALIVE_INTERVAL_SECONDS
        return [ghl_keep_alive()]
