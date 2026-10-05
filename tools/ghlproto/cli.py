import sys
from collections.abc import Callable

import usb.core

from ghlproto.usb_ids import GHL_DONGLE_PRODUCT_ID, GHL_DONGLE_VENDOR_ID
from ghlproto.usb_transport import DongleNotFoundError, DongleTransport, GipInterfaceNotFoundError

EXIT_OK = 0
EXIT_DEVICE_ERROR = 1
EXIT_USAGE_ERROR = 2
QUIT_OTHER_APPS_HINT = "Quit apps that may hold the dongle open (Steam, Plex, browser tabs using WebUSB) and retry."


def not_plugged_in_message(detail: str) -> str:
    return f"{detail}. Is the dongle plugged in?"


def stream_from_dongle(stream: Callable[[DongleTransport], None]) -> int:
    """Opens the dongle, runs `stream` on it and maps every expected failure to a message and an exit code."""
    try:
        with DongleTransport.open(GHL_DONGLE_VENDOR_ID, GHL_DONGLE_PRODUCT_ID) as transport:
            return run_stream(stream, transport)
    except GipInterfaceNotFoundError as error:
        print(error, file=sys.stderr)
    except DongleNotFoundError as error:
        print(not_plugged_in_message(str(error)), file=sys.stderr)
    except usb.core.USBError as error:
        print(f"Could not configure the dongle: {error}", file=sys.stderr)
        print(QUIT_OTHER_APPS_HINT, file=sys.stderr)
    return EXIT_DEVICE_ERROR


def run_stream(stream: Callable[[DongleTransport], None], transport: DongleTransport) -> int:
    try:
        stream(transport)
    except KeyboardInterrupt:
        return EXIT_OK
    except usb.core.USBError:
        print("dongle disconnected", file=sys.stderr)
        return EXIT_DEVICE_ERROR
    return EXIT_OK
