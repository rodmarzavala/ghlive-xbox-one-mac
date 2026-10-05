import io
import unittest
from unittest import mock

from ghlproto.gip import GipCommand, GipFlag, GipPacket
from ghlproto.packet_log import Direction, NullPacketLogger, PacketLogger, format_packet, format_undecodable

UNKNOWN_COMMAND = 0x3F
GUITAR_INPUT = GipPacket(GipCommand.GHL_GUITAR_INPUT, 0, 1, bytes(27))


class FormatPacketTest(unittest.TestCase):
    def test_known_command_shows_name_header_and_hex_payload(self):
        packet = GipPacket(GipCommand.POWER, GipFlag.SYSTEM, 1, bytes([0x00]))
        self.assertEqual(
            format_packet(1.5, Direction.HOST_TO_DEVICE, packet),
            "   1.500 -> POWER            flags=0x20 seq=1   len=1   | 00",
        )

    def test_unknown_command_shows_hex_id(self):
        packet = GipPacket(UNKNOWN_COMMAND, 0, 2, bytes([0xAB, 0xCD]))
        self.assertEqual(
            format_packet(0.0, Direction.DEVICE_TO_HOST, packet),
            "   0.000 <- 0x3f             flags=0x00 seq=2   len=2   | ab cd",
        )

    def test_undecodable_shows_raw_bytes(self):
        self.assertEqual(
            format_undecodable(0.25, bytes([0x20, 0x00]), "too short"),
            "   0.250 <- undecodable (too short) | 20 00",
        )


class PacketLoggerTest(unittest.TestCase):
    def setUp(self):
        self.out = io.StringIO()

    def logger(self, show_repeats: bool = False) -> PacketLogger:
        return PacketLogger(show_repeats, clock=lambda: 0.0, out=self.out)

    def lines(self) -> list[str]:
        return self.out.getvalue().splitlines()

    def test_identical_guitar_input_is_printed_once(self):
        logger = self.logger()
        logger.received(GUITAR_INPUT)
        logger.received(GUITAR_INPUT)
        self.assertEqual(len(self.lines()), 1)

    def test_changed_guitar_input_is_printed_again(self):
        logger = self.logger()
        logger.received(GUITAR_INPUT)
        logger.received(GipPacket(GipCommand.GHL_GUITAR_INPUT, 0, 2, bytes([1]) + bytes(26)))
        self.assertEqual(len(self.lines()), 2)

    def test_show_repeats_prints_every_report(self):
        logger = self.logger(show_repeats=True)
        logger.received(GUITAR_INPUT)
        logger.received(GUITAR_INPUT)
        self.assertEqual(len(self.lines()), 2)

    def test_repeated_non_noisy_command_is_always_printed(self):
        logger = self.logger()
        status = GipPacket(GipCommand.STATUS, GipFlag.SYSTEM, 1, bytes([0x83]))
        logger.received(status)
        logger.received(status)
        self.assertEqual(len(self.lines()), 2)

    def test_sent_packets_are_never_suppressed(self):
        logger = self.logger()
        logger.sent(GUITAR_INPUT)
        logger.sent(GUITAR_INPUT)
        self.assertEqual(len(self.lines()), 2)

    def test_elapsed_time_is_relative_to_construction(self):
        times = iter([10.0, 11.5])
        logger = PacketLogger(False, clock=lambda: next(times), out=self.out)
        logger.note("hello")
        self.assertEqual(self.lines(), ["   1.500 !! hello"])


class NullPacketLoggerTest(unittest.TestCase):
    def test_every_logging_call_is_silent(self):
        logger = NullPacketLogger()
        with mock.patch("builtins.print") as printed:
            logger.sent(GUITAR_INPUT)
            logger.received(GUITAR_INPUT)
            logger.undecodable(b"\x00", "bad")
            logger.note("hello")
        printed.assert_not_called()


if __name__ == "__main__":
    unittest.main()
