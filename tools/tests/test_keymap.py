import tempfile
import unittest
from pathlib import Path

from ghlproto.controls import (
    DEFAULT_TILT_HYSTERESIS,
    DEFAULT_TILT_THRESHOLD,
    DEFAULT_WHAMMY_THRESHOLD,
    Control,
)
from ghlproto.keymap import KEY_CODES, Keymap, KeymapError, load_keymap, parse_keymap

DEFAULT_KEYMAP_PATH = Path(__file__).resolve().parents[1] / "keymaps" / "default.toml"

# Carbon HIToolbox Events.h, asserted as literals so a typo in the table cannot hide behind itself
KNOWN_KEY_CODES = {"a": 0x00, "q": 0x0C, "1": 0x12, "0": 0x1D, "space": 0x31, "escape": 0x35, "up": 0x7E, "f12": 0x6F}


class DefaultKeymapTest(unittest.TestCase):
    def test_default_file_binds_the_documented_keys(self):
        keymap = load_keymap(DEFAULT_KEYMAP_PATH)
        expected = {
            Control.BLACK_1: "1",
            Control.BLACK_2: "2",
            Control.BLACK_3: "3",
            Control.WHITE_1: "q",
            Control.WHITE_2: "w",
            Control.WHITE_3: "e",
            Control.STRUM_UP: "up",
            Control.STRUM_DOWN: "down",
            Control.HERO_POWER: "space",
            Control.TILT: "space",
            Control.WHAMMY: "x",
            Control.PAUSE: "escape",
            Control.GHTV: "tab",
            Control.DPAD_UP: "up",
            Control.DPAD_DOWN: "down",
            Control.DPAD_LEFT: "left",
            Control.DPAD_RIGHT: "right",
        }
        self.assertEqual(keymap.bindings, {control: KEY_CODES[key] for control, key in expected.items()})

    def test_default_file_leaves_thresholds_at_their_defaults(self):
        thresholds = load_keymap(DEFAULT_KEYMAP_PATH).thresholds
        self.assertEqual(thresholds.whammy, DEFAULT_WHAMMY_THRESHOLD)
        self.assertEqual(thresholds.tilt, DEFAULT_TILT_THRESHOLD)
        self.assertEqual(thresholds.tilt_hysteresis, DEFAULT_TILT_HYSTERESIS)


class ParseKeymapTest(unittest.TestCase):
    def test_key_table_matches_hitoolbox(self):
        for name, code in KNOWN_KEY_CODES.items():
            self.assertEqual(KEY_CODES[name], code, name)

    def test_key_table_covers_the_required_names(self):
        required = [*"abcdefghijklmnopqrstuvwxyz0123456789", "up", "down", "left", "right"]
        required += ["space", "return", "escape", "tab", *(f"f{number}" for number in range(1, 13))]
        self.assertEqual([name for name in required if name not in KEY_CODES], [])

    def test_key_codes_are_unique_per_key_name(self):
        self.assertEqual(len(set(KEY_CODES.values())), len(KEY_CODES))

    def test_thresholds_default_when_omitted(self):
        keymap = parse_keymap('[keys]\nblack_1 = "a"\n')
        self.assertEqual(keymap, Keymap({Control.BLACK_1: KEY_CODES["a"]}, keymap.thresholds))
        self.assertEqual(keymap.thresholds.whammy, DEFAULT_WHAMMY_THRESHOLD)

    def test_thresholds_can_be_overridden(self):
        keymap = parse_keymap("[keys]\n[thresholds]\nwhammy = 0.25\ntilt = 140\ntilt_hysteresis = 4\n")
        self.assertEqual(
            (keymap.thresholds.whammy, keymap.thresholds.tilt, keymap.thresholds.tilt_hysteresis), (0.25, 140, 4)
        )

    def test_several_controls_may_share_a_key(self):
        keymap = parse_keymap('[keys]\ntilt = "space"\nhero_power = "space"\n')
        self.assertEqual(keymap.bindings[Control.TILT], keymap.bindings[Control.HERO_POWER])

    def test_unknown_control_is_named_in_the_error(self):
        with self.assertRaisesRegex(KeymapError, "banjo_1"):
            parse_keymap('[keys]\nbanjo_1 = "a"\n')

    def test_unknown_key_is_named_in_the_error(self):
        with self.assertRaisesRegex(KeymapError, r"hyper.*black_1"):
            parse_keymap('[keys]\nblack_1 = "hyper"\n')

    def test_unknown_threshold_is_named_in_the_error(self):
        with self.assertRaisesRegex(KeymapError, "wobble"):
            parse_keymap("[keys]\n[thresholds]\nwobble = 1\n")

    def test_non_numeric_threshold_is_rejected(self):
        with self.assertRaisesRegex(KeymapError, "tilt"):
            parse_keymap('[keys]\n[thresholds]\ntilt = "high"\n')

    def test_invalid_toml_is_a_keymap_error(self):
        with self.assertRaises(KeymapError):
            parse_keymap("[keys\n")

    def test_missing_file_is_a_keymap_error_naming_the_path(self):
        with tempfile.TemporaryDirectory() as directory, self.assertRaisesRegex(KeymapError, "nope.toml"):
            load_keymap(Path(directory) / "nope.toml")


if __name__ == "__main__":
    unittest.main()
