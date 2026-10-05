#!/usr/bin/env python3
"""Wake up the GHL Xbox One dongle and log every GIP packet exchanged.

Configures the device, claims the GIP interface, sends the power-on sequence,
acknowledges packets that ask for it and sends the GHL keep-alive every 8 s.
Stop with Ctrl-C or --seconds.
"""

import argparse
import sys

from ghlproto.cli import stream_from_dongle
from ghlproto.packet_log import PacketLogger
from ghlproto.runner import run_session
from ghlproto.usb_transport import DongleTransport

DEFAULT_RUN_SECONDS = 60.0


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=float, default=DEFAULT_RUN_SECONDS, help="0 runs until Ctrl-C")
    parser.add_argument(
        "--show-repeats",
        action="store_true",
        help="log every guitar input report, not only the ones that changed",
    )
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()

    def stream(transport: DongleTransport) -> None:
        run_session(transport, PacketLogger(arguments.show_repeats), arguments.seconds)

    return stream_from_dongle(stream)


if __name__ == "__main__":
    sys.exit(main())
