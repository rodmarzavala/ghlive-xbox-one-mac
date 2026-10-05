import sys
import unittest
from unittest import mock

import handshake
from ghlproto.cli import EXIT_OK


class HandshakeMainTest(unittest.TestCase):
    def run_main(self, *arguments: str) -> tuple[mock.Mock, mock.Mock]:
        with (
            mock.patch.object(sys, "argv", ["handshake.py", *arguments]),
            mock.patch.object(handshake, "stream_from_dongle", side_effect=lambda action: action(mock.sentinel.t)),
            mock.patch.object(handshake, "PacketLogger") as logger,
            mock.patch.object(handshake, "run_session") as run_session,
        ):
            handshake.main()
        return logger, run_session

    def test_show_repeats_flag_reaches_the_logger(self):
        logger, _ = self.run_main("--show-repeats")
        logger.assert_called_once_with(True)

    def test_repeats_are_hidden_by_default(self):
        logger, _ = self.run_main()
        logger.assert_called_once_with(False)

    def test_seconds_reach_the_session(self):
        _, run_session = self.run_main("--seconds", "5")
        self.assertEqual(run_session.call_args.args[2], 5.0)

    def test_main_returns_the_stream_exit_code(self):
        with (
            mock.patch.object(sys, "argv", ["handshake.py"]),
            mock.patch.object(handshake, "stream_from_dongle", return_value=EXIT_OK),
        ):
            self.assertEqual(handshake.main(), EXIT_OK)


if __name__ == "__main__":
    unittest.main()
