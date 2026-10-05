import io
import unittest
from contextlib import redirect_stderr
from unittest import mock

import usb.core

from ghlproto import cli
from ghlproto.cli import EXIT_DEVICE_ERROR, EXIT_OK, run_stream, stream_from_dongle
from ghlproto.usb_transport import DongleNotFoundError


class RunStreamTest(unittest.TestCase):
    def run_raising(self, error: BaseException | None) -> tuple[int, str]:
        def stream(_transport: object) -> None:
            if error:
                raise error

        stderr = io.StringIO()
        with redirect_stderr(stderr):
            return run_stream(stream, mock.Mock()), stderr.getvalue()

    def test_normal_end_is_ok(self):
        self.assertEqual(self.run_raising(None), (EXIT_OK, ""))

    def test_ctrl_c_is_ok(self):
        self.assertEqual(self.run_raising(KeyboardInterrupt()), (EXIT_OK, ""))

    def test_disconnect_is_a_device_error(self):
        code, message = self.run_raising(usb.core.USBError("gone"))
        self.assertEqual(code, EXIT_DEVICE_ERROR)
        self.assertIn("dongle disconnected", message)


class StreamFromDongleTest(unittest.TestCase):
    def test_missing_dongle_prints_the_plug_in_hint(self):
        stderr = io.StringIO()
        with (
            mock.patch.object(cli.DongleTransport, "open", side_effect=DongleNotFoundError("USB device not found")),
            redirect_stderr(stderr),
        ):
            code = stream_from_dongle(lambda _transport: None)
        self.assertEqual(code, EXIT_DEVICE_ERROR)
        self.assertIn("Is the dongle plugged in?", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
