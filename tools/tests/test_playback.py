import io
import unittest
from dataclasses import replace

from ghlproto.controls import Thresholds
from ghlproto.gip import GipCommand, GipPacket
from ghlproto.guitar_state import GuitarState
from ghlproto.keymap import KEY_CODES
from ghlproto.playback import (
    TILT_REPORT_STEP,
    DryRunEmitter,
    ReportingSink,
    guitar_packet_handler,
)
from tests.test_controls import IDLE
from tests.test_guitar_state import IDLE_PAYLOAD, payload_with


class RecordingSink:
    def __init__(self) -> None:
        self.states: list[GuitarState] = []
        self.released = 0

    def apply(self, state: GuitarState) -> None:
        self.states.append(state)

    def release_all(self) -> None:
        self.released += 1


def packet(command: int, payload: bytes) -> GipPacket:
    return GipPacket(command, 0, 1, payload)


class GuitarPacketHandlerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.sink = RecordingSink()
        self.errors = io.StringIO()
        self.handler = guitar_packet_handler(self.sink, self.errors)

    def test_guitar_input_is_parsed_and_applied(self):
        self.handler(packet(GipCommand.GHL_GUITAR_INPUT, payload_with(b0=0x02)))
        self.assertEqual(len(self.sink.states), 1)
        self.assertTrue(self.sink.states[0].black_1)

    def test_other_commands_are_ignored(self):
        self.handler(packet(GipCommand.STATUS, bytes([0x83])))
        self.handler(packet(GipCommand.NAVIGATION_INPUT, bytes(14)))
        self.assertEqual(self.sink.states, [])

    def test_a_malformed_guitar_report_is_skipped_and_warned_once(self):
        self.handler(packet(GipCommand.GHL_GUITAR_INPUT, bytes(5)))
        self.handler(packet(GipCommand.GHL_GUITAR_INPUT, bytes(5)))
        self.handler(packet(GipCommand.GHL_GUITAR_INPUT, IDLE_PAYLOAD))
        self.assertEqual(len(self.sink.states), 1)
        self.assertEqual(self.errors.getvalue().count("guitar report must be"), 1)


class DryRunEmitterTest(unittest.TestCase):
    def test_logs_key_names_instead_of_posting(self):
        out = io.StringIO()
        emitter = DryRunEmitter(out)
        emitter.key_down(KEY_CODES["space"])
        emitter.key_up(KEY_CODES["space"])
        self.assertEqual(out.getvalue().splitlines(), ["key down space", "key up space"])


class ReportingSinkTest(unittest.TestCase):
    def setUp(self) -> None:
        self.inner = RecordingSink()
        self.out = io.StringIO()
        self.sink = ReportingSink(self.inner, Thresholds(), self.out)

    def lines(self) -> list[str]:
        return self.out.getvalue().splitlines()

    def test_forwards_to_the_wrapped_sink(self):
        self.sink.apply(IDLE)
        self.sink.release_all()
        self.assertEqual((self.inner.states, self.inner.released), ([IDLE], 1))

    def test_prints_active_controls_only_when_they_change(self):
        self.sink.apply(replace(IDLE, black_1=True))
        self.sink.apply(replace(IDLE, black_1=True))
        self.sink.apply(replace(IDLE, black_1=True, white_2=True))
        self.sink.apply(IDLE)
        self.assertEqual(len(self.lines()), 3)
        self.assertIn("black_1", self.lines()[0])
        self.assertIn("white_2", self.lines()[1])
        self.assertIn("none", self.lines()[2])

    def test_every_line_shows_the_raw_tilt(self):
        self.sink.apply(replace(IDLE, black_1=True, tilt=123))
        self.assertIn("tilt=123", self.lines()[0])

    def test_tilt_movement_beyond_the_step_is_reported_for_calibration(self):
        self.sink.apply(IDLE)
        self.sink.apply(replace(IDLE, tilt=IDLE.tilt + TILT_REPORT_STEP - 1))
        self.assertEqual(len(self.lines()), 1)
        self.sink.apply(replace(IDLE, tilt=IDLE.tilt + TILT_REPORT_STEP))
        self.assertEqual(len(self.lines()), 2)
        self.assertIn(f"tilt={IDLE.tilt + TILT_REPORT_STEP}", self.lines()[1])


if __name__ == "__main__":
    unittest.main()
