import unittest
from dataclasses import replace

from ghlproto.controls import (
    DEFAULT_TILT_HYSTERESIS,
    DEFAULT_TILT_THRESHOLD,
    DEFAULT_WHAMMY_HYSTERESIS,
    DEFAULT_WHAMMY_THRESHOLD,
    Control,
    ControlDetector,
    HysteresisDetector,
    Thresholds,
    active_controls,
)
from ghlproto.guitar_state import DpadDirection
from tests.fixtures import IDLE

# Idle tilt observed on hardware over several seconds
OBSERVED_IDLE_TILT_RANGE = range(95, 116)


class ActiveControlsTest(unittest.TestCase):
    def test_idle_has_no_active_controls(self):
        self.assertEqual(active_controls(IDLE, whammy_active=False, tilt_active=False), frozenset())

    def test_every_digital_field_maps_to_its_control(self):
        cases = {
            "black_1": Control.BLACK_1,
            "black_2": Control.BLACK_2,
            "black_3": Control.BLACK_3,
            "white_1": Control.WHITE_1,
            "white_2": Control.WHITE_2,
            "white_3": Control.WHITE_3,
            "strum_up": Control.STRUM_UP,
            "strum_down": Control.STRUM_DOWN,
            "hero_power": Control.HERO_POWER,
            "pause": Control.PAUSE,
            "ghtv": Control.GHTV,
        }
        for field, control in cases.items():
            with self.subTest(field):
                state = replace(IDLE, **{field: True})
                self.assertEqual(active_controls(state, False, False), frozenset({control}))

    def test_dpad_directions_including_diagonals(self):
        state = replace(IDLE, dpad=frozenset({DpadDirection.UP, DpadDirection.LEFT}))
        self.assertEqual(active_controls(state, False, False), frozenset({Control.DPAD_UP, Control.DPAD_LEFT}))

    def test_analog_controls_come_from_the_detector_flags(self):
        self.assertEqual(active_controls(IDLE, True, False), frozenset({Control.WHAMMY}))
        self.assertEqual(active_controls(IDLE, False, True), frozenset({Control.TILT}))


class HysteresisDetectorTest(unittest.TestCase):
    def setUp(self) -> None:
        self.detector = HysteresisDetector(engage_at=DEFAULT_TILT_THRESHOLD, band=DEFAULT_TILT_HYSTERESIS)
        self.release_below = DEFAULT_TILT_THRESHOLD - DEFAULT_TILT_HYSTERESIS

    def test_activates_at_the_threshold(self):
        self.assertFalse(self.detector.update(DEFAULT_TILT_THRESHOLD - 1))
        self.assertTrue(self.detector.update(DEFAULT_TILT_THRESHOLD))

    def test_jitter_inside_the_band_does_not_chatter(self):
        self.detector.update(DEFAULT_TILT_THRESHOLD + 20)
        for value in (DEFAULT_TILT_THRESHOLD - 1, DEFAULT_TILT_THRESHOLD, self.release_below):
            self.assertTrue(self.detector.update(value), value)

    def test_releases_below_the_band(self):
        self.detector.update(DEFAULT_TILT_THRESHOLD + 20)
        self.assertFalse(self.detector.update(self.release_below - 1))

    def test_observed_idle_tilt_never_engages(self):
        for value in OBSERVED_IDLE_TILT_RANGE:
            self.assertFalse(self.detector.update(value), value)

    def test_whammy_jitter_around_the_threshold_does_not_chatter(self):
        detector = HysteresisDetector(engage_at=DEFAULT_WHAMMY_THRESHOLD, band=DEFAULT_WHAMMY_HYSTERESIS)
        results = [detector.update(value) for value in (0.49, 0.51, 0.49, 0.51, 0.49)]
        self.assertEqual(results, [False, True, True, True, True])
        self.assertFalse(detector.update(DEFAULT_WHAMMY_THRESHOLD - DEFAULT_WHAMMY_HYSTERESIS - 0.01))


class ControlDetectorTest(unittest.TestCase):
    def test_tilt_keeps_its_hysteresis_across_states(self):
        detector = ControlDetector(Thresholds())
        tilted = replace(IDLE, tilt=DEFAULT_TILT_THRESHOLD + 10)
        edge = replace(IDLE, tilt=DEFAULT_TILT_THRESHOLD - 1)
        self.assertIn(Control.TILT, detector.detect(tilted))
        self.assertIn(Control.TILT, detector.detect(edge))
        self.assertNotIn(Control.TILT, detector.detect(IDLE))

    def test_whammy_keeps_its_hysteresis_across_states(self):
        detector = ControlDetector(Thresholds())
        self.assertNotIn(Control.WHAMMY, detector.detect(replace(IDLE, whammy=0.49)))
        self.assertIn(Control.WHAMMY, detector.detect(replace(IDLE, whammy=0.51)))
        self.assertIn(Control.WHAMMY, detector.detect(replace(IDLE, whammy=0.49)))

    def test_custom_thresholds(self):
        detector = ControlDetector(Thresholds(whammy=0.2, whammy_hysteresis=0.05, tilt=100, tilt_hysteresis=5))
        controls = detector.detect(replace(IDLE, whammy=0.2, tilt=100))
        self.assertEqual(controls, frozenset({Control.WHAMMY, Control.TILT}))
        self.assertEqual(detector.detect(replace(IDLE, whammy=0.16, tilt=95)), controls)
        self.assertEqual(detector.detect(replace(IDLE, whammy=0.14, tilt=94)), frozenset())


if __name__ == "__main__":
    unittest.main()
