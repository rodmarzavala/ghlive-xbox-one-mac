"""Decoding of the GHL_GUITAR_INPUT (0x21) payload.

Layout confirmed on hardware; it matches PlasticBand "6-Fret Guitar/Xbox One.md".
"""

from dataclasses import dataclass
from enum import Enum, IntFlag, auto


class GuitarReportError(ValueError):
    pass


class DpadDirection(Enum):
    UP = auto()
    RIGHT = auto()
    DOWN = auto()
    LEFT = auto()


class Fret(IntFlag):
    WHITE_1 = 0x01
    BLACK_1 = 0x02
    BLACK_2 = 0x04
    BLACK_3 = 0x08
    WHITE_2 = 0x10
    WHITE_3 = 0x20


class Button(IntFlag):
    HERO_POWER = 0x01
    PAUSE = 0x02
    GHTV = 0x04


GUITAR_REPORT_LENGTH = 27
FRET_OFFSET = 0
BUTTON_OFFSET = 1
DPAD_OFFSET = 2
STRUM_OFFSET = 4
WHAMMY_OFFSET = 6
TILT_OFFSET = 19

STRUM_UP_VALUE = 0x00
STRUM_DOWN_VALUE = 0xFF
WHAMMY_RELEASED = 0x80
WHAMMY_PRESSED = 0xFF

# Hat switch: 0 = up, then clockwise in 45 degree steps; odd values are diagonals, anything else is centered.
HAT_DIRECTIONS: dict[int, frozenset[DpadDirection]] = {
    0: frozenset({DpadDirection.UP}),
    1: frozenset({DpadDirection.UP, DpadDirection.RIGHT}),
    2: frozenset({DpadDirection.RIGHT}),
    3: frozenset({DpadDirection.RIGHT, DpadDirection.DOWN}),
    4: frozenset({DpadDirection.DOWN}),
    5: frozenset({DpadDirection.DOWN, DpadDirection.LEFT}),
    6: frozenset({DpadDirection.LEFT}),
    7: frozenset({DpadDirection.LEFT, DpadDirection.UP}),
}


@dataclass(frozen=True)
class GuitarState:
    black_1: bool
    black_2: bool
    black_3: bool
    white_1: bool
    white_2: bool
    white_3: bool
    strum_up: bool
    strum_down: bool
    hero_power: bool
    pause: bool
    ghtv: bool
    dpad: frozenset[DpadDirection]
    whammy: float
    tilt: int


def normalise_whammy(raw: int) -> float:
    span = WHAMMY_PRESSED - WHAMMY_RELEASED
    return min(max((raw - WHAMMY_RELEASED) / span, 0.0), 1.0)


def parse_guitar_report(payload: bytes) -> GuitarState:
    if len(payload) != GUITAR_REPORT_LENGTH:
        raise GuitarReportError(f"guitar report must be {GUITAR_REPORT_LENGTH} bytes, got {len(payload)}")
    frets = Fret(payload[FRET_OFFSET])
    buttons = Button(payload[BUTTON_OFFSET])
    return GuitarState(
        black_1=Fret.BLACK_1 in frets,
        black_2=Fret.BLACK_2 in frets,
        black_3=Fret.BLACK_3 in frets,
        white_1=Fret.WHITE_1 in frets,
        white_2=Fret.WHITE_2 in frets,
        white_3=Fret.WHITE_3 in frets,
        strum_up=payload[STRUM_OFFSET] == STRUM_UP_VALUE,
        strum_down=payload[STRUM_OFFSET] == STRUM_DOWN_VALUE,
        hero_power=Button.HERO_POWER in buttons,
        pause=Button.PAUSE in buttons,
        ghtv=Button.GHTV in buttons,
        dpad=HAT_DIRECTIONS.get(payload[DPAD_OFFSET], frozenset()),
        whammy=normalise_whammy(payload[WHAMMY_OFFSET]),
        tilt=payload[TILT_OFFSET],
    )
