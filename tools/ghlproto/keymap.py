"""TOML keymap: which macOS key each guitar control presses, plus the whammy/tilt thresholds."""

import tomllib
from dataclasses import dataclass, replace
from pathlib import Path

from ghlproto.controls import Control, Thresholds

KEYS_SECTION = "keys"
THRESHOLDS_SECTION = "thresholds"

# Carbon HIToolbox Events.h (kVK_ANSI_*, kVK_Return, ...): physical key codes on an ANSI layout.
KEY_CODES: dict[str, int] = {
    "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
    "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
    "t": 0x11, "o": 0x1F, "u": 0x20, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "k": 0x28,
    "n": 0x2D, "m": 0x2E,
    "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "5": 0x17, "6": 0x16, "7": 0x1A, "8": 0x1C,
    "9": 0x19, "0": 0x1D,
    "return": 0x24, "tab": 0x30, "space": 0x31, "escape": 0x35,
    "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
    "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76, "f5": 0x60, "f6": 0x61,
    "f7": 0x62, "f8": 0x64, "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
}  # fmt: skip

KEY_NAMES: dict[int, str] = {code: name for name, code in KEY_CODES.items()}

BYTE_MAX = 0xFF
KNOWN_SECTIONS = {KEYS_SECTION, THRESHOLDS_SECTION}
FLOAT_THRESHOLDS = {"whammy", "whammy_hysteresis"}
INTEGER_THRESHOLDS = {"tilt", "tilt_hysteresis"}


class KeymapError(ValueError):
    pass


@dataclass(frozen=True)
class Keymap:
    bindings: dict[Control, int]
    thresholds: Thresholds


def section_table(document: dict[str, object], name: str) -> dict[str, object]:
    table = document.get(name, {})
    if not isinstance(table, dict):
        raise KeymapError(f"[{name}] must be a table")
    return table


def parse_bindings(table: dict[str, object]) -> dict[Control, int]:
    if not table:
        raise KeymapError(f"[{KEYS_SECTION}] is missing or empty")
    bindings: dict[Control, int] = {}
    for control_name, key_name in table.items():
        try:
            control = Control(control_name)
        except ValueError:
            raise KeymapError(f"unknown control '{control_name}' in [{KEYS_SECTION}]") from None
        if not isinstance(key_name, str):
            raise KeymapError(f"key for control '{control_name}' must be a string, got {key_name!r}")
        if key_name.lower() not in KEY_CODES:
            raise KeymapError(f"unknown key '{key_name}' for control '{control_name}'")
        bindings[control] = KEY_CODES[key_name.lower()]
    return bindings


def check_threshold_type(name: str, value: object) -> None:
    is_number = isinstance(value, int | float) and not isinstance(value, bool)
    if name in INTEGER_THRESHOLDS and not (is_number and isinstance(value, int)):
        raise KeymapError(f"threshold '{name}' must be an integer, got {value!r}")
    if name in FLOAT_THRESHOLDS and not is_number:
        raise KeymapError(f"threshold '{name}' must be a number, got {value!r}")


def check_threshold_ranges(thresholds: Thresholds) -> None:
    if not 0 < thresholds.whammy <= 1:
        raise KeymapError("threshold 'whammy' must be above 0 and at most 1")
    if not 0 <= thresholds.whammy_hysteresis < thresholds.whammy:
        raise KeymapError("threshold 'whammy_hysteresis' must be at least 0 and below 'whammy'")
    if not 0 <= thresholds.tilt <= BYTE_MAX:
        raise KeymapError(f"threshold 'tilt' must be between 0 and {BYTE_MAX}")
    if not 0 <= thresholds.tilt_hysteresis < thresholds.tilt:
        raise KeymapError("threshold 'tilt_hysteresis' must be at least 0 and below 'tilt'")


def parse_thresholds(table: dict[str, object]) -> Thresholds:
    for name, value in table.items():
        if name not in FLOAT_THRESHOLDS | INTEGER_THRESHOLDS:
            raise KeymapError(f"unknown threshold '{name}' in [{THRESHOLDS_SECTION}]")
        check_threshold_type(name, value)
    thresholds = replace(Thresholds(), **table)
    check_threshold_ranges(thresholds)
    return thresholds


def parse_keymap(text: str) -> Keymap:
    try:
        document = tomllib.loads(text)
    except tomllib.TOMLDecodeError as error:
        raise KeymapError(f"invalid TOML: {error}") from error
    unknown = sorted(set(document) - KNOWN_SECTIONS)
    if unknown:
        raise KeymapError(f"unknown section '{unknown[0]}'")
    return Keymap(
        parse_bindings(section_table(document, KEYS_SECTION)),
        parse_thresholds(section_table(document, THRESHOLDS_SECTION)),
    )


def load_keymap(path: Path) -> Keymap:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        raise KeymapError(f"cannot read keymap {path}: {error.strerror}") from error
    try:
        return parse_keymap(text)
    except KeymapError as error:
        raise KeymapError(f"{path}: {error}") from error
