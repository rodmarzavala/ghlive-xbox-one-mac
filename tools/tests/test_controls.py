import unittest
from dataclasses import replace

from ghlproto.controls import (
    DEFAULT_TILT_HYSTERESIS,
    DEFAULT_TILT_THRESHOLD,
    DEFAULT_WHAMMY_THRESHOLD,
    Control,
    ControlDetector,
    Thresholds,
    TiltDetector,
    active_controls,
)
from ghlproto.guitar_state import DpadDirection, GuitarState

IDLE = GuitarState(
    black_1=False,
    black_2=False,
    black_3=False,
    white_1=False,
    white_2=False,
    white_3=False,
    strum_up=False,
    strum_down=False,
    hero_power=False,
    pause=False,
    ghtv=False,
    dpad=frozenset(),
    whammy=0.0,
    tilt=110,
)


class ActiveControlsTest(unittest.TestCase):
    def test_idle_has_no_active_controls(self):
        self.assertEqual(active_controls(IDLE, Thresholds(), tilt_active=False), frozenset())

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
                self.assertEqual(active_controls(state, Thresholds(), tilt_active=False), frozenset({control}))

    def test_dpad_directions_including_diagonals(self):
        state = replace(IDLE, dpad=frozenset({DpadDirection.UP, DpadDirection.LEFT}))
        self.assertEqual(
            active_controls(state, Thresholds(), tilt_active=False),
            frozenset({Control.DPAD_UP, Control.DPAD_LEFT}),
        )

    def test_whammy_activates_at_the_threshold(self):
        thresholds = Thresholds()
        below = replace(IDLE, whammy=DEFAULT_WHAMMY_THRESHOLD - 0.01)
        at = replace(IDLE, whammy=DEFAULT_WHAMMY_THRESHOLD)
        self.assertNotIn(Control.WHAMMY, active_controls(below, thresholds, tilt_active=False))
        self.assertIn(Control.WHAMMY, active_controls(at, thresholds, tilt_active=False))

    def test_custom_whammy_threshold(self):
        state = replace(IDLE, whammy=0.2)
        self.assertIn(Control.WHAMMY, active_controls(state, Thresholds(whammy=0.1), tilt_active=False))

    def test_tilt_comes_from_the_detector_flag(self):
        self.assertIn(Control.TILT, active_controls(IDLE, Thresholds(), tilt_active=True))


class TiltDetectorTest(unittest.TestCase):
    def setUp(self) -> None:
        self.detector = TiltDetector(Thresholds())
        self.release_below = DEFAULT_TILT_THRESHOLD - DEFAULT_TILT_HYSTERESIS

    def test_rest_is_inactive(self):
        self.assertFalse(self.detector.update(110))

    def test_activates_at_the_threshold(self):
        self.assertFalse(self.detector.update(DEFAULT_TILT_THRESHOLD - 1))
        self.assertTrue(self.detector.update(DEFAULT_TILT_THRESHOLD))

    def test_jitter_inside_the_hysteresis_band_does_not_chatter(self):
        self.detector.update(DEFAULT_TILT_THRESHOLD + 20)
        for value in (DEFAULT_TILT_THRESHOLD - 1, DEFAULT_TILT_THRESHOLD, self.release_below):
            self.assertTrue(self.detector.update(value), value)

    def test_releases_below_the_band(self):
        self.detector.update(DEFAULT_TILT_THRESHOLD + 20)
        self.assertFalse(self.detector.update(self.release_below - 1))

    def test_jitter_below_the_threshold_does_not_activate(self):
        for value in (DEFAULT_TILT_THRESHOLD - 3, DEFAULT_TILT_THRESHOLD - 1, DEFAULT_TILT_THRESHOLD - 2):
            self.assertFalse(self.detector.update(value))

    def test_custom_thresholds(self):
        detector = TiltDetector(Thresholds(tilt=100, tilt_hysteresis=5))
        self.assertTrue(detector.update(100))
        self.assertTrue(detector.update(95))
        self.assertFalse(detector.update(94))


class ControlDetectorTest(unittest.TestCase):
    def test_includes_tilt_with_hysteresis_across_states(self):
        detector = ControlDetector(Thresholds())
        tilted = replace(IDLE, tilt=DEFAULT_TILT_THRESHOLD + 10)
        edge = replace(IDLE, tilt=DEFAULT_TILT_THRESHOLD - 1)
        self.assertIn(Control.TILT, detector.detect(tilted))
        self.assertIn(Control.TILT, detector.detect(edge))
        self.assertNotIn(Control.TILT, detector.detect(IDLE))


if __name__ == "__main__":
    unittest.main()
