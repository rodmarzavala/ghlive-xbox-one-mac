from typing import Protocol

from ghlproto.controls import ControlDetector
from ghlproto.guitar_state import GuitarState
from ghlproto.keymap import Keymap


class OutputSink(Protocol):
    """Where guitar state goes. A future virtual-gamepad sink would also keep the analog whammy and tilt."""

    def apply(self, state: GuitarState) -> None: ...

    def release_all(self) -> None: ...


class KeyEmitter(Protocol):
    def key_down(self, keycode: int) -> None: ...

    def key_up(self, keycode: int) -> None: ...


class KeyboardSink:
    def __init__(self, keymap: Keymap, emitter: KeyEmitter) -> None:
        self._bindings = keymap.bindings
        self._detector = ControlDetector(keymap.thresholds)
        self._emitter = emitter
        self._pressed: frozenset[int] = frozenset()

    def apply(self, state: GuitarState) -> None:
        active = self._detector.detect(state)
        self._move_to(frozenset(self._bindings[control] for control in active if control in self._bindings))

    def release_all(self) -> None:
        self._move_to(frozenset())

    def _move_to(self, target: frozenset[int]) -> None:
        for keycode in sorted(self._pressed - target):
            self._emitter.key_up(keycode)
        for keycode in sorted(target - self._pressed):
            self._emitter.key_down(keycode)
        self._pressed = target
