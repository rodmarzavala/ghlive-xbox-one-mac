import sys
import time
from collections.abc import Callable
from enum import StrEnum
from typing import TextIO

from ghlproto.gip import GipCommand, GipPacket

NOISY_INPUT_COMMANDS = {GipCommand.GHL_GUITAR_INPUT}


class Direction(StrEnum):
    HOST_TO_DEVICE = "->"
    DEVICE_TO_HOST = "<-"


def command_name(command: int) -> str:
    try:
        return GipCommand(command).name
    except ValueError:
        return f"0x{command:02x}"


def format_packet(elapsed_seconds: float, direction: Direction, packet: GipPacket) -> str:
    return (
        f"{elapsed_seconds:8.3f} {direction} {command_name(packet.command):<16} "
        f"flags=0x{packet.flags:02x} seq={packet.sequence:<3} len={len(packet.payload):<3} | {packet.payload.hex(' ')}"
    )


def format_undecodable(elapsed_seconds: float, data: bytes, reason: str) -> str:
    return f"{elapsed_seconds:8.3f} {Direction.DEVICE_TO_HOST} undecodable ({reason}) | {data.hex(' ')}"


def format_note(elapsed_seconds: float, message: str) -> str:
    return f"{elapsed_seconds:8.3f} !! {message}"


class PacketLogger:
    def __init__(
        self,
        show_repeats: bool,
        clock: Callable[[], float] = time.monotonic,
        out: TextIO = sys.stdout,
    ) -> None:
        self._clock = clock
        self._out = out
        self._started_at = clock()
        self._show_repeats = show_repeats
        self._last_payload_by_command: dict[int, bytes] = {}

    def sent(self, packet: GipPacket) -> None:
        self._print(format_packet(self._elapsed(), Direction.HOST_TO_DEVICE, packet))

    def received(self, packet: GipPacket) -> None:
        if self._is_repeat(packet):
            return
        self._remember(packet)
        self._print(format_packet(self._elapsed(), Direction.DEVICE_TO_HOST, packet))

    def undecodable(self, data: bytes, reason: str) -> None:
        self._print(format_undecodable(self._elapsed(), data, reason))

    def note(self, message: str) -> None:
        self._print(format_note(self._elapsed(), message))

    def _is_repeat(self, packet: GipPacket) -> bool:
        if self._show_repeats or packet.command not in NOISY_INPUT_COMMANDS:
            return False
        return self._last_payload_by_command.get(packet.command) == packet.payload

    def _remember(self, packet: GipPacket) -> None:
        self._last_payload_by_command[packet.command] = packet.payload

    def _elapsed(self) -> float:
        return self._clock() - self._started_at

    def _print(self, line: str) -> None:
        print(line, file=self._out, flush=True)


class NullPacketLogger(PacketLogger):
    """Logs nothing, for callers that own the console themselves."""

    def __init__(self) -> None:
        super().__init__(show_repeats=False)

    def _print(self, line: str) -> None:
        return None
