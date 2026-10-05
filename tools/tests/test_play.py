import io
import subprocess
import sys
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

import usb.core

import play
from ghlproto.cli import EXIT_OK, EXIT_USAGE_ERROR
from ghlproto.controls import Thresholds
from ghlproto.keymap import Keymap
from ghlproto.output import KeyboardSink
from ghlproto.playback import DryRunEmitter, ReportingSink
from tests.fixtures import FakeEmitter, RecordingSink

TOOLS_DIRECTORY = Path(__file__).resolve().parents[1]


class RaisingTransport:
    def __init__(self, error: BaseException) -> None:
        self._error = error

    def write(self, data: bytes) -> None:
        raise self._error

    def read(self, timeout_ms: int) -> bytes | None:
        raise self._error


class PlayTest(unittest.TestCase):
    def test_keys_are_released_once_however_the_session_ends(self):
        for error in (KeyboardInterrupt(), usb.core.USBError("gone"), RuntimeError("boom")):
            with self.subTest(error=type(error).__name__):
                sink = RecordingSink()
                with self.assertRaises(type(error)):
                    play.play(RaisingTransport(error), sink)
                self.assertEqual(sink.released, 1)


class BuildSinkTest(unittest.TestCase):
    def test_verbose_wraps_the_keyboard_sink_in_a_reporting_sink(self):
        keymap = Keymap({}, Thresholds())
        self.assertIsInstance(play.build_sink(keymap, FakeEmitter(), verbose=True), ReportingSink)

    def test_quiet_uses_the_keyboard_sink_directly(self):
        keymap = Keymap({}, Thresholds())
        self.assertIsInstance(play.build_sink(keymap, FakeEmitter(), verbose=False), KeyboardSink)


class MainTest(unittest.TestCase):
    def run_main(self, *arguments: str, trusted: bool = True) -> tuple[int, SimpleNamespace]:
        calls = SimpleNamespace(handlers={}, sinks=[], streamed=False)

        def stream(action):
            calls.streamed = True
            action(mock.sentinel.transport)
            return EXIT_OK

        with (
            mock.patch.object(sys, "argv", ["play.py", *arguments]),
            mock.patch.object(play, "stream_from_dongle", side_effect=stream),
            mock.patch.object(play, "play", side_effect=lambda _transport, sink: calls.sinks.append(sink)),
            mock.patch.object(play.signal, "signal", side_effect=calls.handlers.__setitem__),
            mock.patch("ghlproto.quartz_keyboard.accessibility_trusted", return_value=trusted),
            mock.patch("ghlproto.quartz_keyboard.QuartzKeyEmitter"),
            redirect_stderr(io.StringIO()),
        ):
            return play.main(), calls

    def test_sigterm_and_sighup_are_turned_into_keyboard_interrupts(self):
        _, calls = self.run_main("--dry-run")
        self.assertEqual(set(calls.handlers), {play.signal.SIGTERM, play.signal.SIGHUP})
        for handler in calls.handlers.values():
            with self.assertRaises(KeyboardInterrupt):
                handler(0, None)

    def test_untrusted_accessibility_exits_with_usage_error_without_opening_the_dongle(self):
        code, calls = self.run_main(trusted=False)
        self.assertEqual(code, EXIT_USAGE_ERROR)
        self.assertFalse(calls.streamed)

    def test_dry_run_does_not_need_accessibility(self):
        code, calls = self.run_main("--dry-run", trusted=False)
        self.assertEqual(code, EXIT_OK)
        self.assertTrue(calls.streamed)

    def test_verbose_flag_selects_the_reporting_sink(self):
        _, verbose = self.run_main("--dry-run", "--verbose")
        _, quiet = self.run_main("--dry-run")
        self.assertIsInstance(verbose.sinks[0], ReportingSink)
        self.assertIsInstance(quiet.sinks[0], KeyboardSink)

    def test_bad_keymap_exits_with_usage_error_without_opening_the_dongle(self):
        code, calls = self.run_main("--dry-run", "--keymap", str(TOOLS_DIRECTORY / "nope.toml"))
        self.assertEqual(code, EXIT_USAGE_ERROR)
        self.assertFalse(calls.streamed)


class BuildEmitterTest(unittest.TestCase):
    def test_dry_run_returns_the_logging_emitter(self):
        self.assertIsInstance(play.build_emitter(dry_run=True), DryRunEmitter)

    def test_dry_run_works_without_the_quartz_bindings(self):
        script = (
            "import sys\n"
            "sys.modules['Quartz'] = None\n"
            "sys.modules['ApplicationServices'] = None\n"
            "import play\n"
            "play.build_emitter(dry_run=True)\n"
        )
        result = subprocess.run([sys.executable, "-c", script], cwd=TOOLS_DIRECTORY, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
