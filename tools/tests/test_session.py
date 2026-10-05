import unittest

from ghlproto.gip import GipCommand, GipFlag, GipPacket
from ghlproto.session import CHUNKED_NOT_SUPPORTED, KEEP_ALIVE_INTERVAL_SECONDS, GipSession

START_TIME = 100.0


class StartTest(unittest.TestCase):
    def test_start_sends_power_on_led_and_auth_done_in_order(self):
        commands = [packet.command for packet in GipSession().start()]
        self.assertEqual(commands, [GipCommand.POWER, GipCommand.LED, GipCommand.AUTHENTICATE])

    def test_start_uses_increasing_sequences(self):
        sequences = [packet.sequence for packet in GipSession().start()]
        self.assertEqual(sequences, [1, 2, 3])


class IncomingPacketTest(unittest.TestCase):
    def test_acknowledges_packets_that_require_it(self):
        announce = GipPacket(GipCommand.ANNOUNCE, GipFlag.SYSTEM | GipFlag.ACKNOWLEDGE_REQUIRED, 9, bytes(28))
        replies = GipSession().handle(announce)
        self.assertEqual([reply.command for reply in replies], [GipCommand.ACKNOWLEDGE])
        self.assertEqual(replies[0].sequence, 9)

    def test_ignores_plain_input(self):
        guitar_input = GipPacket(GipCommand.GHL_GUITAR_INPUT, 0, 1, bytes(27))
        self.assertEqual(GipSession().handle(guitar_input), [])

    def test_chunked_packet_is_not_acknowledged_and_is_reported(self):
        chunked = GipPacket(GipCommand.ANNOUNCE, GipFlag.ACKNOWLEDGE_REQUIRED | GipFlag.CHUNKED, 1, bytes(8))
        session = GipSession()
        self.assertEqual(session.handle(chunked), [])
        self.assertEqual(session.unsupported_reason(chunked), CHUNKED_NOT_SUPPORTED)

    def test_plain_packet_has_no_unsupported_reason(self):
        self.assertIsNone(GipSession().unsupported_reason(GipPacket(GipCommand.STATUS, GipFlag.SYSTEM, 1, b"")))


class KeepAliveTest(unittest.TestCase):
    def test_first_keep_alive_is_due_immediately(self):
        packets = GipSession().due_packets(START_TIME)
        self.assertEqual([packet.command for packet in packets], [GipCommand.GHL_OUTPUT])

    def test_not_due_again_before_interval(self):
        session = GipSession()
        session.due_packets(START_TIME)
        self.assertEqual(session.due_packets(START_TIME + KEEP_ALIVE_INTERVAL_SECONDS - 0.1), [])

    def test_due_again_after_interval(self):
        session = GipSession()
        session.due_packets(START_TIME)
        self.assertEqual(len(session.due_packets(START_TIME + KEEP_ALIVE_INTERVAL_SECONDS)), 1)


if __name__ == "__main__":
    unittest.main()
