"""GIP (Gaming Input Protocol) framing and the host packets needed by the GHL dongle.

Header layout per MS-GIPUSB: command, flags, sequence, then the payload length
as a little-endian base-128 varint.
"""

import struct
from dataclasses import dataclass
from enum import IntEnum, IntFlag

HEADER_FIXED_LENGTH = 3
MIN_PACKET_LENGTH = HEADER_FIXED_LENGTH + 1
VARINT_VALUE_MASK = 0x7F
VARINT_CONTINUATION_BIT = 0x80
VARINT_BITS_PER_BYTE = 7
SEQUENCE_MIN = 1
SEQUENCE_MAX = 0xFF


class GipCommand(IntEnum):
    # 0x01-0x0A: MS-GIPUSB system messages. 0x20-0x22: PlasticBand GHL guitar reports.
    ACKNOWLEDGE = 0x01
    ANNOUNCE = 0x02
    STATUS = 0x03
    IDENTIFY = 0x04
    POWER = 0x05
    AUTHENTICATE = 0x06
    VIRTUAL_KEY = 0x07
    LED = 0x0A
    NAVIGATION_INPUT = 0x20
    GHL_GUITAR_INPUT = 0x21
    GHL_OUTPUT = 0x22


# MS-GIPUSB header flags byte: bit 4 ack required, bit 5 system message, bits 6-7 chunking
class GipFlag(IntFlag):
    ACKNOWLEDGE_REQUIRED = 0x10
    SYSTEM = 0x20
    CHUNK_START = 0x40
    CHUNKED = 0x80


# MS-GIPUSB: the low nibble of the flags byte is the client id
CLIENT_ID_MASK = 0x0F

# MS-GIPUSB power message: mode 0x00 = on
POWER_MODE_ON = 0x00
# LED payload as used by Linux xpad for every Xbox One device: reserved, mode "on", brightness
LED_RESERVED = 0x00
LED_MODE_ON = 0x01
LED_BRIGHTNESS_DEFAULT = 0x14
# Tells the device the console finished authentication (Linux xpad "auth done" packet)
AUTHENTICATION_COMPLETE = bytes([0x01, 0x00])
# PlasticBand "6-Fret Guitar/Xbox One.md": sub-command 0x02, must be sent every 8 s for input to flow
GHL_KEEP_ALIVE_PAYLOAD = bytes([0x02, 0x08, 0x0A, 0x00, 0x00, 0x00, 0x00, 0x00])
# PlasticBand: the keep-alive always goes out with sequence 0
GHL_KEEP_ALIVE_SEQUENCE = 0x00
ACKNOWLEDGE_FORMAT = "<BBBHHH"  # MS-GIPUSB acknowledge message
ACKNOWLEDGE_RESERVED = 0x00
ACKNOWLEDGE_PADDING = 0x0000
ACKNOWLEDGE_BYTES_REMAINING = 0x0000


class GipDecodeError(ValueError):
    pass


class GipTransferError(GipDecodeError):
    def __init__(self, packets: list["GipPacket"], tail: bytes, reason: str) -> None:
        super().__init__(reason)
        self.packets = packets
        self.tail = tail
        self.reason = reason


@dataclass(frozen=True)
class GipPacket:
    command: int
    flags: int
    sequence: int
    payload: bytes

    @property
    def requires_acknowledgement(self) -> bool:
        return bool(self.flags & GipFlag.ACKNOWLEDGE_REQUIRED)


class SequenceCounter:
    def __init__(self) -> None:
        self._last = SEQUENCE_MIN - 1

    def next(self) -> int:
        self._last = self._last + 1 if self._last < SEQUENCE_MAX else SEQUENCE_MIN
        return self._last


def encode_varint(value: int) -> bytes:
    encoded = bytearray()
    while True:
        low_bits = value & VARINT_VALUE_MASK
        value >>= VARINT_BITS_PER_BYTE
        if not value:
            encoded.append(low_bits)
            return bytes(encoded)
        encoded.append(low_bits | VARINT_CONTINUATION_BIT)


def decode_varint(data: bytes, offset: int) -> tuple[int, int]:
    """Returns (value, offset just past the varint)."""
    value = 0
    shift = 0
    while offset < len(data):
        byte = data[offset]
        offset += 1
        value |= (byte & VARINT_VALUE_MASK) << shift
        if not byte & VARINT_CONTINUATION_BIT:
            return value, offset
        shift += VARINT_BITS_PER_BYTE
    raise GipDecodeError("truncated length field")


def encode_packet(packet: GipPacket) -> bytes:
    header = bytes([packet.command, packet.flags, packet.sequence])
    return header + encode_varint(len(packet.payload)) + packet.payload


def decode_packet_at(data: bytes, offset: int) -> tuple[GipPacket, int]:
    """Returns (packet, offset just past it)."""
    if len(data) - offset < MIN_PACKET_LENGTH:
        raise GipDecodeError(f"packet too short: {len(data) - offset} bytes")
    length, payload_start = decode_varint(data, offset + HEADER_FIXED_LENGTH)
    payload_end = payload_start + length
    if payload_end > len(data):
        raise GipDecodeError(f"payload truncated: expected {length} bytes, got {len(data) - payload_start}")
    command, flags, sequence = data[offset : offset + HEADER_FIXED_LENGTH]
    return GipPacket(command, flags, sequence, bytes(data[payload_start:payload_end])), payload_end


def decode_packet(data: bytes) -> GipPacket:
    return decode_packet_at(data, 0)[0]


def decode_packets(data: bytes) -> list[GipPacket]:
    """A USB transfer can carry several back-to-back messages; raises GipTransferError on a bad tail."""
    packets: list[GipPacket] = []
    offset = 0
    while offset < len(data):
        # No GIP command is 0x00, so an all-zero remainder is USB padding, not a message.
        if not any(data[offset:]):
            break
        try:
            packet, offset = decode_packet_at(data, offset)
        except GipDecodeError as error:
            raise GipTransferError(packets, data[offset:], str(error)) from error
        packets.append(packet)
    return packets


def power_on(sequence: int) -> GipPacket:
    return GipPacket(GipCommand.POWER, GipFlag.SYSTEM, sequence, bytes([POWER_MODE_ON]))


def led_on(sequence: int) -> GipPacket:
    payload = bytes([LED_RESERVED, LED_MODE_ON, LED_BRIGHTNESS_DEFAULT])
    return GipPacket(GipCommand.LED, GipFlag.SYSTEM, sequence, payload)


def authentication_done(sequence: int) -> GipPacket:
    return GipPacket(GipCommand.AUTHENTICATE, GipFlag.SYSTEM, sequence, AUTHENTICATION_COMPLETE)


def ghl_keep_alive() -> GipPacket:
    return GipPacket(GipCommand.GHL_OUTPUT, 0, GHL_KEEP_ALIVE_SEQUENCE, GHL_KEEP_ALIVE_PAYLOAD)


def acknowledgement_for(received: GipPacket) -> GipPacket:
    options = int(received.flags & (GipFlag.SYSTEM | CLIENT_ID_MASK))
    payload = struct.pack(
        ACKNOWLEDGE_FORMAT,
        ACKNOWLEDGE_RESERVED,
        received.command,
        options,
        len(received.payload),
        ACKNOWLEDGE_PADDING,
        ACKNOWLEDGE_BYTES_REMAINING,
    )
    flags = GipFlag.SYSTEM | (received.flags & CLIENT_ID_MASK)
    return GipPacket(GipCommand.ACKNOWLEDGE, int(flags), received.sequence, payload)
