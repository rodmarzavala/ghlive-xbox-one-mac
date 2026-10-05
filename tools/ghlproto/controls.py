"""Digital controls derived from a GuitarState, including the thresholds that digitise whammy and tilt."""

from dataclasses import dataclass
from enum import StrEnum

from ghlproto.guitar_state import DpadDirection, GuitarState

DEFAULT_WHAMMY_THRESHOLD = 0.5
DEFAULT_WHAMMY_HYSTERESIS = 0.1
# Measured on hardware: tilt idles between 95 and 115 and reaches about 171 when raised.
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


# These controls are GuitarState bool fields of the same name.
DIGITAL_CONTROLS: tuple[Control, ...] = (
    Control.BLACK_1,
    Control.BLACK_2,
    Control.BLACK_3,
    Control.WHITE_1,
    Control.WHITE_2,
    Control.WHITE_3,
    Control.STRUM_UP,
    Control.STRUM_DOWN,
    Control.HERO_POWER,
    Control.PAUSE,
    Control.GHTV,
)

DPAD_CONTROLS: dict[DpadDirection, Control] = {
    DpadDirection.UP: Control.DPAD_UP,
    DpadDirection.DOWN: Control.DPAD_DOWN,
    DpadDirection.LEFT: Control.DPAD_LEFT,
    DpadDirection.RIGHT: Control.DPAD_RIGHT,
}


@dataclass(frozen=True)
class Thresholds:
    whammy: float = DEFAULT_WHAMMY_THRESHOLD
    whammy_hysteresis: float = DEFAULT_WHAMMY_HYSTERESIS
    tilt: int = DEFAULT_TILT_THRESHOLD
    tilt_hysteresis: int = DEFAULT_TILT_HYSTERESIS


class HysteresisDetector:
    """Digitises an analog value: engages at `engage_at` and releases once it drops `band` below it."""

    def __init__(self, engage_at: float, band: float) -> None:
        self._engage_at = engage_at
        self._release_below = engage_at - band
        self._active = False

    def update(self, value: float) -> bool:
        self._active = value >= (self._release_below if self._active else self._engage_at)
        return self._active


def active_controls(state: GuitarState, whammy_active: bool, tilt_active: bool) -> frozenset[Control]:
    active = {control for control in DIGITAL_CONTROLS if getattr(state, control.value)}
    active.update(DPAD_CONTROLS[direction] for direction in state.dpad)
    if whammy_active:
        active.add(Control.WHAMMY)
    if tilt_active:
        active.add(Control.TILT)
    return frozenset(active)


class ControlDetector:
    def __init__(self, thresholds: Thresholds) -> None:
        self._whammy = HysteresisDetector(thresholds.whammy, thresholds.whammy_hysteresis)
        self._tilt = HysteresisDetector(thresholds.tilt, thresholds.tilt_hysteresis)

    def detect(self, state: GuitarState) -> frozenset[Control]:
        return active_controls(state, self._whammy.update(state.whammy), self._tilt.update(state.tilt))
