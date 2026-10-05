import tempfile
import unittest
from pathlib import Path

from ghlproto.controls import (
    DEFAULT_TILT_HYSTERESIS,
    DEFAULT_TILT_THRESHOLD,
    DEFAULT_WHAMMY_HYSTERESIS,
    DEFAULT_WHAMMY_THRESHOLD,
    Control,
    Thresholds,
)
from ghlproto.keymap import KEY_CODES, Keymap, KeymapError, load_keymap, parse_keymap

KEYS_ONLY = '[keys]\nblack_1 = "a"\n'
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
        self.assertEqual(thresholds.whammy_hysteresis, DEFAULT_WHAMMY_HYSTERESIS)


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
        keymap = parse_keymap(KEYS_ONLY)
        self.assertEqual(keymap, Keymap({Control.BLACK_1: KEY_CODES["a"]}, Thresholds()))

    def test_thresholds_can_be_overridden(self):
        text = KEYS_ONLY + "[thresholds]\nwhammy = 0.25\nwhammy_hysteresis = 0.05\ntilt = 140\ntilt_hysteresis = 4\n"
        self.assertEqual(parse_keymap(text).thresholds, Thresholds(0.25, 0.05, 140, 4))

    def test_integer_valued_whammy_threshold_is_accepted(self):
        self.assertEqual(parse_keymap(KEYS_ONLY + "[thresholds]\nwhammy = 1\n").thresholds.whammy, 1)

    def test_several_controls_may_share_a_key(self):
        keymap = parse_keymap('[keys]\ntilt = "space"\nhero_power = "space"\n')
        self.assertEqual(keymap.bindings[Control.TILT], keymap.bindings[Control.HERO_POWER])

    def test_key_names_are_case_insensitive(self):
        self.assertEqual(parse_keymap('[keys]\nblack_1 = "SPACE"\n').bindings, {Control.BLACK_1: KEY_CODES["space"]})

    def test_unknown_control_is_named_in_the_error(self):
        with self.assertRaisesRegex(KeymapError, "banjo_1"):
            parse_keymap('[keys]\nbanjo_1 = "a"\n')

    def test_unknown_key_is_named_in_the_error(self):
        with self.assertRaisesRegex(KeymapError, r"hyper.*black_1"):
            parse_keymap('[keys]\nblack_1 = "hyper"\n')

    def test_non_string_key_is_rejected(self):
        with self.assertRaisesRegex(KeymapError, r"black_1.*must be a string"):
            parse_keymap("[keys]\nblack_1 = 5\n")

    def test_unknown_threshold_is_named_in_the_error(self):
        with self.assertRaisesRegex(KeymapError, "wobble"):
            parse_keymap(KEYS_ONLY + "[thresholds]\nwobble = 1\n")

    def test_invalid_threshold_values_are_rejected_by_name(self):
        cases = {
            "whammy = 0": "whammy",
            "whammy = 1.5": "whammy",
            "whammy = -0.2": "whammy",
            "whammy_hysteresis = -0.1": "whammy_hysteresis",
            "whammy_hysteresis = 0.5": "whammy_hysteresis",
            "tilt = -1": "tilt",
            "tilt = 256": "tilt",
            "tilt_hysteresis = -1": "tilt_hysteresis",
            "tilt_hysteresis = 150": "tilt_hysteresis",
            "tilt = 5\ntilt_hysteresis = 10": "tilt_hysteresis",
        }
        for line, name in cases.items():
            with self.subTest(line), self.assertRaisesRegex(KeymapError, name):
                parse_keymap(KEYS_ONLY + f"[thresholds]\n{line}\n")

    def test_boundary_threshold_values_are_accepted(self):
        text = KEYS_ONLY + "[thresholds]\nwhammy = 1.0\nwhammy_hysteresis = 0\ntilt = 255\ntilt_hysteresis = 0\n"
        self.assertEqual(parse_keymap(text).thresholds, Thresholds(1.0, 0, 255, 0))

    def test_threshold_type_errors(self):
        cases = {
            "tilt = 150.5": "tilt.*must be an integer",
            "tilt_hysteresis = 1.5": "tilt_hysteresis.*must be an integer",
            'tilt = "high"': "tilt.*must be an integer",
            "tilt = true": "tilt.*must be an integer",
            "whammy = true": "whammy.*must be a number",
            'whammy = "half"': "whammy.*must be a number",
        }
        for line, pattern in cases.items():
            with self.subTest(line), self.assertRaisesRegex(KeymapError, pattern):
                parse_keymap(KEYS_ONLY + f"[thresholds]\n{line}\n")

    def test_sections_must_be_tables(self):
        for text, name in (('keys = "x"\n', "keys"), (KEYS_ONLY + "[[thresholds]]\ntilt = 1\n", "thresholds")):
            with self.subTest(text), self.assertRaisesRegex(KeymapError, name):
                parse_keymap(text)

    def test_unknown_top_level_section_is_rejected(self):
        with self.assertRaisesRegex(KeymapError, "extras"):
            parse_keymap(KEYS_ONLY + "[extras]\nx = 1\n")

    def test_missing_or_empty_keys_section_is_rejected(self):
        for text in ("", "[keys]\n", "[thresholds]\ntilt = 150\n"):
            with self.subTest(text), self.assertRaisesRegex(KeymapError, "keys"):
                parse_keymap(text)

    def test_invalid_toml_is_a_keymap_error(self):
        with self.assertRaises(KeymapError):
            parse_keymap("[keys\n")

    def test_missing_file_names_the_path_and_the_reason(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "nope.toml"
            with self.assertRaises(KeymapError) as caught:
                load_keymap(path)
        self.assertIn(str(path), str(caught.exception))
        self.assertIn("No such file", str(caught.exception))

    def test_parse_errors_are_prefixed_with_the_path(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "bad.toml"
            path.write_text('[keys]\nbanjo = "a"\n', encoding="utf-8")
            with self.assertRaises(KeymapError) as caught:
                load_keymap(path)
        self.assertTrue(str(caught.exception).startswith(f"{path}: "))
        self.assertIn("banjo", str(caught.exception))


if __name__ == "__main__":
    unittest.main()
