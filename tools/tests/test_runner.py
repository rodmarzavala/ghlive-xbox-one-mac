import io
import unittest
from collections.abc import Callable

from ghlproto.gip import GipCommand, GipFlag, GipPacket, decode_packet, encode_packet
from ghlproto.packet_log import PacketLogger
from ghlproto.runner import READ_TIMEOUT_MS, RUN_FOREVER, run_session
from ghlproto.session import KEEP_ALIVE_INTERVAL_SECONDS

SECONDS_PER_READ = 1.0
RUN_SECONDS = 20.0
READS_BEFORE_INTERRUPT = 50


class FakeClock:
    def __init__(self) -> None:
        self.now = 0.0

    def __call__(self) -> float:
        return self.now


class FakeTransport:
    """Replays scripted reads (None = timeout) and advances the clock on every read."""

    def __init__(self, clock: FakeClock, reads: list[bytes | None]) -> None:
        self._clock = clock
        self._reads = iter(reads)
        self.writes: list[GipPacket] = []
        self.read_count = 0

    def write(self, data: bytes) -> None:
        self.writes.append(decode_packet(data))

    def read(self, timeout_ms: int) -> bytes | None:
        assert timeout_ms == READ_TIMEOUT_MS
        self.read_count += 1
        self._clock.now += SECONDS_PER_READ
        return next(self._reads, None)


class InterruptingTransport(FakeTransport):
    def __init__(self, clock: FakeClock, reads_before_interrupt: int) -> None:
        super().__init__(clock, [])
        self._reads_before_interrupt = reads_before_interrupt

    def read(self, timeout_ms: int) -> bytes | None:
        result = super().read(timeout_ms)
        if self.read_count > self._reads_before_interrupt:
            raise KeyboardInterrupt
        return result


class RunSessionTest(unittest.TestCase):
    def run_with(
        self,
        reads: list[bytes | None],
        seconds: float = RUN_SECONDS,
        on_packet: Callable[[GipPacket], None] | None = None,
    ) -> tuple[FakeTransport, str]:
        clock = FakeClock()
        transport = FakeTransport(clock, reads)
        out = io.StringIO()
        run_session(transport, PacketLogger(False, clock=clock, out=out), seconds, clock=clock, on_packet=on_packet)
        return transport, out.getvalue()

    def test_starts_with_power_led_auth_then_keep_alive(self):
        transport, _ = self.run_with([])
        first_four = transport.writes[:4]
        self.assertEqual(
            [packet.command for packet in first_four],
            [GipCommand.POWER, GipCommand.LED, GipCommand.AUTHENTICATE, GipCommand.GHL_OUTPUT],
        )
        self.assertEqual([packet.sequence for packet in first_four[:3]], [1, 2, 3])

    def test_announce_requiring_acknowledgement_is_acked_with_same_sequence(self):
        announce = GipPacket(GipCommand.ANNOUNCE, GipFlag.SYSTEM | GipFlag.ACKNOWLEDGE_REQUIRED, 9, bytes(28))
        transport, _ = self.run_with([encode_packet(announce)])
        acknowledgements = [packet for packet in transport.writes if packet.command == GipCommand.ACKNOWLEDGE]
        self.assertEqual([packet.sequence for packet in acknowledgements], [9])

    def test_undecodable_bytes_are_logged_and_the_loop_continues(self):
        transport, output = self.run_with([bytes([0x20, 0x00]), None])
        self.assertIn("undecodable", output)
        self.assertGreater(transport.read_count, 1)

    def test_every_message_of_a_bundled_transfer_is_handled(self):
        status = GipPacket(GipCommand.STATUS, GipFlag.SYSTEM | GipFlag.ACKNOWLEDGE_REQUIRED, 4, bytes([0x83]))
        guitar = GipPacket(GipCommand.GHL_GUITAR_INPUT, 0, 5, bytes(27))
        transport, output = self.run_with([encode_packet(status) + encode_packet(guitar)])
        self.assertIn("GHL_GUITAR_INPUT", output)
        self.assertIn(4, [p.sequence for p in transport.writes if p.command == GipCommand.ACKNOWLEDGE])

    def test_on_packet_receives_every_decoded_packet_even_repeated_ones(self):
        guitar = encode_packet(GipPacket(GipCommand.GHL_GUITAR_INPUT, 0, 5, bytes(27)))
        status = encode_packet(GipPacket(GipCommand.STATUS, GipFlag.SYSTEM, 4, bytes([0x83])))
        received: list[GipPacket] = []
        self.run_with([guitar + status, guitar], on_packet=received.append)
        self.assertEqual(
            [packet.command for packet in received],
            [GipCommand.GHL_GUITAR_INPUT, GipCommand.STATUS, GipCommand.GHL_GUITAR_INPUT],
        )

    def test_on_packet_still_receives_complete_messages_before_a_bad_tail(self):
        status = encode_packet(GipPacket(GipCommand.STATUS, GipFlag.SYSTEM, 4, bytes([0x83])))
        received: list[GipPacket] = []
        self.run_with([status + bytes([0x21, 0x00, 0x05, 0x1B])], on_packet=received.append)
        self.assertEqual([packet.command for packet in received], [GipCommand.STATUS])

    def test_truncated_tail_is_logged_after_the_complete_messages(self):
        status = encode_packet(GipPacket(GipCommand.STATUS, GipFlag.SYSTEM, 4, bytes([0x83])))
        _, output = self.run_with([status + bytes([0x21, 0x00, 0x05, 0x1B])])
        self.assertIn("STATUS", output)
        self.assertIn("undecodable", output)

    def test_chunked_packet_is_reported_and_not_acknowledged(self):
        chunked = GipPacket(GipCommand.ANNOUNCE, GipFlag.ACKNOWLEDGE_REQUIRED | GipFlag.CHUNKED, 5, bytes(4))
        transport, output = self.run_with([encode_packet(chunked)])
        self.assertIn("chunked packet not supported", output)
        self.assertNotIn(GipCommand.ACKNOWLEDGE, [packet.command for packet in transport.writes])

    def test_keep_alive_is_resent_after_eight_seconds(self):
        transport, _ = self.run_with([], seconds=KEEP_ALIVE_INTERVAL_SECONDS + 2 * SECONDS_PER_READ)
        keep_alives = [packet for packet in transport.writes if packet.command == GipCommand.GHL_OUTPUT]
        self.assertEqual(len(keep_alives), 2)

    def test_run_forever_keeps_reading_until_interrupted(self):
        clock = FakeClock()
        transport = InterruptingTransport(clock, reads_before_interrupt=READS_BEFORE_INTERRUPT)
        with self.assertRaises(KeyboardInterrupt):
            run_session(transport, PacketLogger(False, clock=clock, out=io.StringIO()), RUN_FOREVER, clock=clock)
        self.assertEqual(transport.read_count, READS_BEFORE_INTERRUPT + 1)

    def test_loop_exits_at_the_deadline(self):
        transport, _ = self.run_with([], seconds=3 * SECONDS_PER_READ)
        self.assertEqual(transport.read_count, 3)


if __name__ == "__main__":
    unittest.main()
