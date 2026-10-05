"""Digital controls derived from a GuitarState, including the thresholds that digitise whammy and tilt."""

from dataclasses import dataclass
from enum import StrEnum

from ghlproto.guitar_state import DpadDirection, GuitarState

DEFAULT_WHAMMY_THRESHOLD = 0.5
# Measured on hardware: tilt rests near 110 (+-3 jitter) and reaches about 171 when raised.
DEFAULT_TILT_THRESHOLD = 150
DEFAULT_TILT_HYSTERESIS = 10


class Control(StrEnum):
    BLACK_1 = "black_1"
    BLACK_2 = "black_2"
    BLACK_3 = "black_3"
    WHITE_1 = "white_1"
    WHITE_2 = "white_2"
    WHITE_3 = "white_3"
    STRUM_UP = "strum_up"
    STRUM_DOWN = "strum_down"
    HERO_POWER = "hero_power"
    PAUSE = "pause"
    GHTV = "ghtv"
    DPAD_UP = "dpad_up"
    DPAD_DOWN = "dpad_down"
    DPAD_LEFT = "dpad_left"
    DPAD_RIGHT = "dpad_right"
    WHAMMY = "whammy"
    TILT = "tilt"


DIGITAL_FIELD_CONTROLS: dict[str, Control] = {
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

DPAD_CONTROLS: dict[DpadDirection, Control] = {
    DpadDirection.UP: Control.DPAD_UP,
    DpadDirection.DOWN: Control.DPAD_DOWN,
    DpadDirection.LEFT: Control.DPAD_LEFT,
    DpadDirection.RIGHT: Control.DPAD_RIGHT,
}


@dataclass(frozen=True)
class Thresholds:
    whammy: float = DEFAULT_WHAMMY_THRESHOLD
    tilt: int = DEFAULT_TILT_THRESHOLD
    tilt_hysteresis: int = DEFAULT_TILT_HYSTERESIS


class TiltDetector:
    """Turns the analog tilt into a flag that engages at the threshold and releases `hysteresis` below it."""

    def __init__(self, thresholds: Thresholds) -> None:
        self._engage_at = thresholds.tilt
        self._release_below = thresholds.tilt - thresholds.tilt_hysteresis
        self._active = False

    def update(self, tilt: int) -> bool:
        if self._active:
            self._active = tilt >= self._release_below
        else:
            self._active = tilt >= self._engage_at
        return self._active


def active_controls(state: GuitarState, thresholds: Thresholds, tilt_active: bool) -> frozenset[Control]:
    active = {control for field, control in DIGITAL_FIELD_CONTROLS.items() if getattr(state, field)}
    active.update(DPAD_CONTROLS[direction] for direction in state.dpad)
    if state.whammy >= thresholds.whammy:
        active.add(Control.WHAMMY)
    if tilt_active:
        active.add(Control.TILT)
    return frozenset(active)


class ControlDetector:
    def __init__(self, thresholds: Thresholds) -> None:
        self._thresholds = thresholds
        self._tilt = TiltDetector(thresholds)

    def detect(self, state: GuitarState) -> frozenset[Control]:
        return active_controls(state, self._thresholds, self._tilt.update(state.tilt))
