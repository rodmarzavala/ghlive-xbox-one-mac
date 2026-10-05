#!/usr/bin/env python3
"""Wake up the GHL Xbox One dongle and log every GIP packet exchanged.

Configures the device, claims the GIP interface, sends the power-on sequence,
acknowledges packets that ask for it and sends the GHL keep-alive every 8 s.
Stop with Ctrl-C or --seconds.
"""

import argparse
import sys

import usb.core

from ghlproto.cli import EXIT_DEVICE_ERROR, EXIT_OK, QUIT_OTHER_APPS_HINT, not_plugged_in_message
from ghlproto.packet_log import PacketLogger
from ghlproto.runner import run_session
from ghlproto.usb_ids import GHL_DONGLE_PRODUCT_ID, GHL_DONGLE_VENDOR_ID
from ghlproto.usb_transport import DongleNotFoundError, DongleTransport, GipInterfaceNotFoundError

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


def stream(transport: DongleTransport, arguments: argparse.Namespace) -> int:
    try:
        run_session(transport, PacketLogger(arguments.show_repeats), arguments.seconds)
    except KeyboardInterrupt:
        return EXIT_OK
    except usb.core.USBError:
        print("dongle disconnected", file=sys.stderr)
        return EXIT_DEVICE_ERROR
    return EXIT_OK


def main() -> int:
    arguments = parse_arguments()
    try:
        with DongleTransport.open(GHL_DONGLE_VENDOR_ID, GHL_DONGLE_PRODUCT_ID) as transport:
            return stream(transport, arguments)
    except GipInterfaceNotFoundError as error:
        print(error, file=sys.stderr)
    except DongleNotFoundError as error:
        print(not_plugged_in_message(str(error)), file=sys.stderr)
    except usb.core.USBError as error:
        print(f"Could not configure the dongle: {error}", file=sys.stderr)
        print(QUIT_OTHER_APPS_HINT, file=sys.stderr)
    return EXIT_DEVICE_ERROR


if __name__ == "__main__":
    sys.exit(main())
