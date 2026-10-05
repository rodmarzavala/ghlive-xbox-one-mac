import io
import unittest
from contextlib import redirect_stderr
from unittest import mock

import usb.core

from ghlproto import cli
from ghlproto.cli import EXIT_DEVICE_ERROR, EXIT_OK, QUIT_OTHER_APPS_HINT, run_stream, stream_from_dongle
from ghlproto.usb_transport import DongleNotFoundError, GipInterfaceNotFoundError


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
    def open_failing_with(self, error: Exception) -> tuple[int, str]:
        stderr = io.StringIO()
        with (
            mock.patch.object(cli.DongleTransport, "open", side_effect=error),
            redirect_stderr(stderr),
        ):
            return stream_from_dongle(lambda _transport: None), stderr.getvalue()

    def test_missing_dongle_prints_the_plug_in_hint(self):
        code, message = self.open_failing_with(DongleNotFoundError("USB device not found"))
        self.assertEqual(code, EXIT_DEVICE_ERROR)
        self.assertIn("Is the dongle plugged in?", message)

    def test_missing_gip_interface_prints_its_message_only(self):
        code, message = self.open_failing_with(GipInterfaceNotFoundError("the device has no GIP interface"))
        self.assertEqual(code, EXIT_DEVICE_ERROR)
        self.assertEqual(message.strip(), "the device has no GIP interface")

    def test_usb_error_while_opening_suggests_quitting_other_apps(self):
        code, message = self.open_failing_with(usb.core.USBError("busy"))
        self.assertEqual(code, EXIT_DEVICE_ERROR)
        self.assertIn("Could not configure the dongle:", message)
        self.assertIn(QUIT_OTHER_APPS_HINT, message)

    def test_usb_error_while_streaming_is_not_reported_as_a_configuration_failure(self):
        transport = mock.MagicMock()
        transport.__enter__.return_value = transport
        stderr = io.StringIO()

        def stream(_transport: object) -> None:
            raise usb.core.USBError("gone")

        with mock.patch.object(cli.DongleTransport, "open", return_value=transport), redirect_stderr(stderr):
            code = stream_from_dongle(stream)
        self.assertEqual(code, EXIT_DEVICE_ERROR)
        self.assertEqual(stderr.getvalue().strip(), "dongle disconnected")


if __name__ == "__main__":
    unittest.main()
