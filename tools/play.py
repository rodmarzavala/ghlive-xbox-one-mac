#!/usr/bin/env python3
"""Play with the GHL Xbox One guitar: turn its controls into macOS keyboard events.

Needs the Accessibility permission for the terminal app (except with --dry-run).
Stop with Ctrl-C; every key is released on exit.
"""

import argparse
import signal
import sys
from pathlib import Path
from types import FrameType

from ghlproto.cli import EXIT_USAGE_ERROR, stream_from_dongle
from ghlproto.keymap import Keymap, KeymapError, load_keymap
from ghlproto.output import KeyboardSink, KeyEmitter, OutputSink
from ghlproto.packet_log import NullPacketLogger
from ghlproto.playback import DryRunEmitter, ReportingSink, guitar_packet_handler
from ghlproto.runner import RUN_FOREVER, run_session
from ghlproto.usb_transport import DongleTransport

DEFAULT_KEYMAP = Path(__file__).resolve().parent / "keymaps" / "default.toml"
ACCESSIBILITY_HINT = (
    "Posting keystrokes needs the Accessibility permission.\n"
    "macOS does not prompt for it: open System Settings > Privacy & Security > Accessibility, "
    "add your terminal app with the + button (or switch it on if listed), then restart it and run this again."
)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--keymap", type=Path, default=DEFAULT_KEYMAP, help="TOML keymap (default: keymaps/default.toml)"
    )
    parser.add_argument("--verbose", action="store_true", help="print active controls and the raw tilt value")
    parser.add_argument("--dry-run", action="store_true", help="log the keys that would be pressed, post nothing")
    return parser.parse_args()


def build_emitter(dry_run: bool) -> KeyEmitter | None:
    if dry_run:
        return DryRunEmitter()
    # Imported lazily so --dry-run works where the Quartz bindings are unavailable.
    from ghlproto.quartz_keyboard import QuartzKeyEmitter, accessibility_trusted

    return QuartzKeyEmitter() if accessibility_trusted() else None


def play(transport: DongleTransport, sink: OutputSink) -> None:
    try:
        run_session(transport, NullPacketLogger(), RUN_FOREVER, on_packet=guitar_packet_handler(sink))
    finally:
        sink.release_all()


def build_sink(keymap: Keymap, emitter: KeyEmitter, verbose: bool) -> OutputSink:
    sink = KeyboardSink(keymap, emitter)
    return ReportingSink(sink, keymap.thresholds) if verbose else sink


def interrupt_on_terminate() -> None:
    def raise_interrupt(_signal_number: int, _frame: FrameType | None) -> None:
        raise KeyboardInterrupt

    for signal_number in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(signal_number, raise_interrupt)


def main() -> int:
    arguments = parse_arguments()
    interrupt_on_terminate()
    try:
        keymap = load_keymap(arguments.keymap)
    except KeymapError as error:
        print(error, file=sys.stderr)
        return EXIT_USAGE_ERROR
    emitter = build_emitter(arguments.dry_run)
    if emitter is None:
        print(ACCESSIBILITY_HINT, file=sys.stderr)
        return EXIT_USAGE_ERROR
    sink = build_sink(keymap, emitter, arguments.verbose)
    return stream_from_dongle(lambda transport: play(transport, sink))


if __name__ == "__main__":
    sys.exit(main())
