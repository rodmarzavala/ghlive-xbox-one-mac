import dataclasses
import unittest

from ghlproto.guitar_state import (
    DpadDirection,
    GuitarReportError,
    GuitarState,
    parse_guitar_report,
)
from tests.fixtures import IDLE_PAYLOAD, IDLE_TILT, payload_with


def pressed_flags(state: GuitarState) -> set[str]:
    return {field.name for field in dataclasses.fields(state) if getattr(state, field.name) is True}


class ParseGuitarReportTest(unittest.TestCase):
    def test_idle_report_has_nothing_pressed(self):
        state = parse_guitar_report(IDLE_PAYLOAD)
        self.assertEqual(pressed_flags(state), set())
        self.assertEqual(state.dpad, frozenset())
        self.assertEqual(state.whammy, 0.0)
        self.assertEqual(state.tilt, IDLE_TILT)

    def test_each_fret_bit(self):
        cases = {
            "black_1": 0x02,
            "black_2": 0x04,
            "black_3": 0x08,
            "white_1": 0x01,
            "white_2": 0x10,
            "white_3": 0x20,
        }
        for name, bit in cases.items():
            with self.subTest(name):
                self.assertEqual(pressed_flags(parse_guitar_report(payload_with(b0=bit))), {name})

    def test_unknown_bits_are_ignored(self):
        self.assertEqual(pressed_flags(parse_guitar_report(payload_with(b0=0xC0, b1=0xF8))), set())

    def test_each_button_bit(self):
        cases = {"hero_power": 0x01, "pause": 0x02, "ghtv": 0x04}
        for name, bit in cases.items():
            with self.subTest(name):
                self.assertEqual(pressed_flags(parse_guitar_report(payload_with(b1=bit))), {name})

    def test_strum(self):
        self.assertEqual(pressed_flags(parse_guitar_report(payload_with(b4=0x00))), {"strum_up"})
        self.assertEqual(pressed_flags(parse_guitar_report(payload_with(b4=0xFF))), {"strum_down"})

    def test_dpad_hat_values(self):
        up, right, down, left = DpadDirection.UP, DpadDirection.RIGHT, DpadDirection.DOWN, DpadDirection.LEFT
        cases = {
            0x00: {up},
            0x01: {up, right},
            0x02: {right},
            0x03: {right, down},
            0x04: {down},
            0x05: {down, left},
            0x06: {left},
            0x07: {left, up},
            **{hat: set() for hat in (0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F)},
        }
        for hat, expected in cases.items():
            with self.subTest(hat=hat):
                self.assertEqual(parse_guitar_report(payload_with(b2=hat)).dpad, frozenset(expected))

    def test_whammy_is_normalised_from_idle_to_fully_pressed(self):
        self.assertEqual(parse_guitar_report(payload_with(b6=0x80)).whammy, 0.0)
        self.assertEqual(parse_guitar_report(payload_with(b6=0xFF)).whammy, 1.0)
        self.assertAlmostEqual(parse_guitar_report(payload_with(b6=0xBF)).whammy, 0.5, places=2)

    def test_whammy_below_the_idle_value_is_clamped_to_zero(self):
        self.assertEqual(parse_guitar_report(payload_with(b6=0x00)).whammy, 0.0)

    def test_tilt_is_the_raw_byte(self):
        self.assertEqual(parse_guitar_report(payload_with(b19=171)).tilt, 171)

    def test_wrong_length_is_rejected(self):
        for length in (0, 14, 26, 28):
            with self.subTest(length=length), self.assertRaises(GuitarReportError):
                parse_guitar_report(bytes(length))


if __name__ == "__main__":
    unittest.main()
