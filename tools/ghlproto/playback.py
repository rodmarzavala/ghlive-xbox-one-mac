"""Glue between the GIP session and an OutputSink, plus the dry-run and verbose helpers of play.py."""

import sys
from typing import TextIO

from ghlproto.controls import Control, ControlDetector, Thresholds
from ghlproto.gip import GipCommand, GipPacket
from ghlproto.guitar_state import GuitarReportError, GuitarState, parse_guitar_report
from ghlproto.keymap import KEY_NAMES
from ghlproto.output import OutputSink
from ghlproto.runner import PacketHandler

# Tilt jitters by about +-3 at rest; report a raw tilt change only when it is clearly more than that.
TILT_REPORT_STEP = 10
NO_CONTROLS_LABEL = "none"


def guitar_packet_handler(sink: OutputSink, errors: TextIO = sys.stderr) -> PacketHandler:
    warned = False

    def handle(packet: GipPacket) -> None:
        nonlocal warned
        if packet.command != GipCommand.GHL_GUITAR_INPUT:
            return
        try:
            state = parse_guitar_report(packet.payload)
        except GuitarReportError as error:
            if not warned:
                print(f"ignoring malformed guitar report: {error}", file=errors, flush=True)
                warned = True
            return
        sink.apply(state)

    return handle


class DryRunEmitter:
    def __init__(self, out: TextIO = sys.stdout) -> None:
        self._out = out

    def key_down(self, keycode: int) -> None:
        print(f"key down {KEY_NAMES[keycode]}", file=self._out, flush=True)

    def key_up(self, keycode: int) -> None:
        print(f"key up {KEY_NAMES[keycode]}", file=self._out, flush=True)


class ReportingSink:
    """Wraps a sink and prints the active controls when they change, with the raw tilt for calibration."""

    def __init__(self, inner: OutputSink, thresholds: Thresholds, out: TextIO = sys.stdout) -> None:
        self._inner = inner
        self._detector = ControlDetector(thresholds)
        self._out = out
        self._last_controls: frozenset[Control] | None = None
        self._last_reported_tilt: int | None = None

    def apply(self, state: GuitarState) -> None:
        self._inner.apply(state)
        controls = self._detector.detect(state)
        if controls != self._last_controls or self._tilt_moved(state.tilt):
            self._report(controls, state.tilt)

    def release_all(self) -> None:
        self._inner.release_all()

    def _tilt_moved(self, tilt: int) -> bool:
        return self._last_reported_tilt is not None and abs(tilt - self._last_reported_tilt) >= TILT_REPORT_STEP

    def _report(self, controls: frozenset[Control], tilt: int) -> None:
        names = ", ".join(sorted(controls)) or NO_CONTROLS_LABEL
        print(f"{names} | tilt={tilt}", file=self._out, flush=True)
        self._last_controls = controls
        self._last_reported_tilt = tilt
