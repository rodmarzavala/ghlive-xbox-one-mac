import unittest

from ghlproto.gip import (
    SEQUENCE_MAX,
    SEQUENCE_MIN,
    GipCommand,
    GipDecodeError,
    GipFlag,
    GipPacket,
    GipTransferError,
    SequenceCounter,
    acknowledgement_for,
    authentication_done,
    decode_packet,
    decode_packets,
    encode_packet,
    ghl_keep_alive,
    led_on,
    power_on,
)

SAMPLE_SEQUENCE = 0x07
CLIENT_ID = 0x00
CLIENT_ID_THREE = 0x03
USB_MAX_PACKET_SIZE = 64


class EncodeDecodeTest(unittest.TestCase):
    def test_encodes_header_then_payload(self):
        packet = GipPacket(GipCommand.POWER, GipFlag.SYSTEM, SAMPLE_SEQUENCE, bytes([0x00]))
        self.assertEqual(encode_packet(packet), bytes([0x05, 0x20, 0x07, 0x01, 0x00]))

    def test_round_trip(self):
        packet = GipPacket(GipCommand.GHL_GUITAR_INPUT, CLIENT_ID, SAMPLE_SEQUENCE, bytes(range(27)))
        self.assertEqual(decode_packet(encode_packet(packet)), packet)

    def test_long_payload_uses_varint_length(self):
        payload = bytes(200)
        encoded = encode_packet(GipPacket(GipCommand.ANNOUNCE, GipFlag.SYSTEM, 1, payload))
        self.assertEqual(encoded[3:5], bytes([0xC8, 0x01]))
        self.assertEqual(decode_packet(encoded).payload, payload)

    def test_truncated_header_is_rejected(self):
        with self.assertRaises(GipDecodeError):
            decode_packet(bytes([0x20, 0x00]))

    def test_truncated_payload_is_rejected(self):
        with self.assertRaises(GipDecodeError):
            decode_packet(bytes([0x20, 0x00, 0x01, 0x0E, 0x00]))

    def test_payload_one_byte_short_is_rejected(self):
        with self.assertRaises(GipDecodeError):
            decode_packet(bytes([0x03, 0x20, 0x01, 0x02, 0x83]))

    def test_trailing_usb_padding_is_ignored(self):
        packet = decode_packet(bytes([0x05, 0x20, 0x01, 0x01, 0x00, 0xAA, 0xAA]))
        self.assertEqual(packet.payload, bytes([0x00]))


class DecodePacketsTest(unittest.TestCase):
    def test_transfer_bundling_status_and_guitar_report_yields_both(self):
        status = bytes([0x03, 0x20, 0x13, 0x01, 0x83])
        guitar_payload = bytes([0x00, 0x00, 0x0F]) + bytes(24)
        guitar = bytes([0x21, 0x00, 0x95, 0x1B]) + guitar_payload
        self.assertEqual(
            decode_packets(status + guitar),
            [
                GipPacket(GipCommand.STATUS, GipFlag.SYSTEM, 0x13, bytes([0x83])),
                GipPacket(GipCommand.GHL_GUITAR_INPUT, 0, 0x95, guitar_payload),
            ],
        )

    def test_single_message_yields_one_packet(self):
        self.assertEqual(len(decode_packets(bytes([0x05, 0x20, 0x01, 0x01, 0x00]))), 1)

    def test_trailing_zero_padding_is_not_decoded_as_packets(self):
        status = bytes([0x03, 0x20, 0x01, 0x01, 0x83])
        self.assertEqual(len(decode_packets(status + bytes(USB_MAX_PACKET_SIZE - len(status)))), 1)

    def test_empty_payload_message_is_followed_by_the_next_one(self):
        empty = bytes([0x03, 0x20, 0x01, 0x00])
        status = bytes([0x03, 0x20, 0x02, 0x01, 0x83])
        self.assertEqual([packet.payload for packet in decode_packets(empty + status)], [b"", b"\x83"])

    def test_truncated_second_message_reports_error_with_first_packet(self):
        first = bytes([0x05, 0x20, 0x01, 0x01, 0x00])
        truncated = bytes([0x21, 0x00, 0x02, 0x1B, 0x00])
        with self.assertRaises(GipTransferError) as raised:
            decode_packets(first + truncated)
        self.assertEqual([packet.command for packet in raised.exception.packets], [GipCommand.POWER])
        self.assertEqual(raised.exception.tail, truncated)


class PacketFlagsTest(unittest.TestCase):
    def test_requires_acknowledgement(self):
        packet = GipPacket(GipCommand.ANNOUNCE, GipFlag.SYSTEM | GipFlag.ACKNOWLEDGE_REQUIRED, 1, b"")
        self.assertTrue(packet.requires_acknowledgement)

    def test_input_does_not_require_acknowledgement(self):
        self.assertFalse(GipPacket(GipCommand.NAVIGATION_INPUT, CLIENT_ID, 1, b"").requires_acknowledgement)


class BuildersTest(unittest.TestCase):
    def test_power_on(self):
        self.assertEqual(encode_packet(power_on(SAMPLE_SEQUENCE)), bytes([0x05, 0x20, 0x07, 0x01, 0x00]))

    def test_led_on(self):
        self.assertEqual(encode_packet(led_on(SAMPLE_SEQUENCE)), bytes([0x0A, 0x20, 0x07, 0x03, 0x00, 0x01, 0x14]))

    def test_authentication_done(self):
        self.assertEqual(
            encode_packet(authentication_done(SAMPLE_SEQUENCE)), bytes([0x06, 0x20, 0x07, 0x02, 0x01, 0x00])
        )

    def test_ghl_keep_alive_matches_reference_bytes(self):
        self.assertEqual(
            encode_packet(ghl_keep_alive()),
            bytes([0x22, 0x00, 0x00, 0x08, 0x02, 0x08, 0x0A, 0x00, 0x00, 0x00, 0x00, 0x00]),
        )

    def test_acknowledgement_echoes_command_sequence_and_length(self):
        received = GipPacket(
            GipCommand.VIRTUAL_KEY, GipFlag.SYSTEM | GipFlag.ACKNOWLEDGE_REQUIRED, SAMPLE_SEQUENCE, bytes(2)
        )
        self.assertEqual(
            encode_packet(acknowledgement_for(received)),
            bytes([0x01, 0x20, 0x07, 0x09, 0x00, 0x07, 0x20, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00]),
        )

    def test_acknowledgement_keeps_the_client_id_in_header_and_options(self):
        received = GipPacket(GipCommand.NAVIGATION_INPUT, GipFlag.ACKNOWLEDGE_REQUIRED | CLIENT_ID_THREE, 4, b"")
        acknowledgement = acknowledgement_for(received)
        self.assertEqual(acknowledgement.flags, 0x23)
        self.assertEqual(acknowledgement.payload[2], CLIENT_ID_THREE)


class SequenceCounterTest(unittest.TestCase):
    def test_starts_at_one_and_skips_zero_on_wrap(self):
        counter = SequenceCounter()
        self.assertEqual(counter.next(), SEQUENCE_MIN)
        for _ in range(SEQUENCE_MAX - SEQUENCE_MIN - 1):
            counter.next()
        self.assertEqual(counter.next(), SEQUENCE_MAX)
        self.assertEqual(counter.next(), SEQUENCE_MIN)


if __name__ == "__main__":
    unittest.main()
