import unittest
from dataclasses import replace

from ghlproto.controls import DEFAULT_TILT_THRESHOLD, Control, Thresholds
from ghlproto.guitar_state import GuitarState
from ghlproto.keymap import Keymap
from ghlproto.output import KeyboardSink
from tests.fixtures import IDLE, FakeEmitter

KEY_A = 0x10
KEY_B = 0x20
KEY_SHARED = 0x30


def make_sink(emitter: FakeEmitter) -> KeyboardSink:
    bindings = {
        Control.BLACK_1: KEY_A,
        Control.WHITE_1: KEY_B,
        Control.HERO_POWER: KEY_SHARED,
        Control.TILT: KEY_SHARED,
    }
    return KeyboardSink(Keymap(bindings, Thresholds()), emitter)


def pressed(**fields: bool) -> GuitarState:
    return replace(IDLE, **fields)


class KeyboardSinkTest(unittest.TestCase):
    def setUp(self) -> None:
        self.emitter = FakeEmitter()
        self.sink = make_sink(self.emitter)

    def test_press_then_release(self):
        self.sink.apply(pressed(black_1=True))
        self.sink.apply(IDLE)
        self.assertEqual(self.emitter.events, [("down", KEY_A), ("up", KEY_A)])

    def test_held_key_is_not_repeated(self):
        for _ in range(3):
            self.sink.apply(pressed(black_1=True))
        self.assertEqual(self.emitter.events, [("down", KEY_A)])

    def test_only_the_difference_is_emitted(self):
        self.sink.apply(pressed(black_1=True))
        self.sink.apply(pressed(black_1=True, white_1=True))
        self.sink.apply(pressed(white_1=True))
        self.assertEqual(
            self.emitter.events,
            [("down", KEY_A), ("down", KEY_B), ("up", KEY_A)],
        )

    def test_unbound_controls_emit_nothing(self):
        self.sink.apply(pressed(black_3=True))
        self.assertEqual(self.emitter.events, [])

    def test_shared_key_stays_down_while_either_control_is_active(self):
        tilted = DEFAULT_TILT_THRESHOLD + 10
        self.sink.apply(pressed(hero_power=True))
        self.sink.apply(pressed(hero_power=True, tilt=tilted))
        self.sink.apply(pressed(tilt=tilted))
        self.assertEqual(self.emitter.events, [("down", KEY_SHARED)])
        self.sink.apply(IDLE)
        self.assertEqual(self.emitter.events, [("down", KEY_SHARED), ("up", KEY_SHARED)])

    def test_a_key_down_that_failed_midway_is_still_released(self):
        class FailingOnce(FakeEmitter):
            def key_down(self, keycode: int) -> None:
                if not self.events and not self.failed:
                    self.failed = True
                    raise OSError("post failed")
                super().key_down(keycode)

            failed = False

        emitter = FailingOnce()
        sink = make_sink(emitter)
        with self.assertRaises(OSError):
            sink.apply(pressed(black_1=True, white_1=True))
        sink.release_all()
        self.assertEqual(emitter.events, [("up", KEY_A)])

    def test_a_key_up_that_failed_is_retried_by_release_all(self):
        class FailingUp(FakeEmitter):
            fail = False

            def key_up(self, keycode: int) -> None:
                if self.fail:
                    self.fail = False
                    raise OSError("post failed")
                super().key_up(keycode)

        emitter = FailingUp()
        sink = make_sink(emitter)
        sink.apply(pressed(black_1=True))
        emitter.fail = True
        with self.assertRaises(OSError):
            sink.apply(IDLE)
        sink.release_all()
        self.assertEqual(emitter.events, [("down", KEY_A), ("up", KEY_A)])

    def test_release_all_lifts_every_pressed_key(self):
        self.sink.apply(pressed(black_1=True, white_1=True))
        self.emitter.events.clear()
        self.sink.release_all()
        self.assertEqual(sorted(self.emitter.events), [("up", KEY_A), ("up", KEY_B)])

    def test_release_all_is_idempotent_and_the_next_press_is_emitted_again(self):
        self.sink.apply(pressed(black_1=True))
        self.sink.release_all()
        self.sink.release_all()
        self.sink.apply(pressed(black_1=True))
        self.assertEqual(self.emitter.events, [("down", KEY_A), ("up", KEY_A), ("down", KEY_A)])


if __name__ == "__main__":
    unittest.main()
