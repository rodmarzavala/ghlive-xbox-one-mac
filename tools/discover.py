#!/usr/bin/env python3
"""Read-only discovery of the Guitar Hero Live Xbox One dongle.

Prints USB descriptors (via libusb) and the macOS IORegistry objects attached
to the device. Only standard GET_DESCRIPTOR requests are sent; the device is
never configured or claimed.
"""

import argparse
import sys

import usb.core
import usb.util

from ghlproto.descriptor_report import describe_configuration, describe_device, mask_serial
from ghlproto.macos_registry import find_registry_devices, list_attached_objects, read_usb_registry
from ghlproto.usb_ids import GHL_DONGLE_PRODUCT_ID, GHL_DONGLE_VENDOR_ID

EXIT_FOUND = 0
EXIT_NOT_FOUND = 1
INDENT = "  "


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vid", type=lambda value: int(value, 16), default=GHL_DONGLE_VENDOR_ID)
    parser.add_argument("--pid", type=lambda value: int(value, 16), default=GHL_DONGLE_PRODUCT_ID)
    parser.add_argument("--show-serial", action="store_true", help="print the serial number unmasked")
    return parser.parse_args()


def read_string_descriptor(device, index: int) -> str:
    if index == 0:
        return "<none>"
    try:
        return usb.util.get_string(device, index) or "<empty>"
    except (usb.core.USBError, ValueError, NotImplementedError) as error:
        return f"<unavailable: {error}>"


def describe_strings(device, show_serial: bool) -> list[str]:
    serial = read_string_descriptor(device, device.iSerialNumber)
    if not show_serial and not serial.startswith("<"):
        serial = mask_serial(serial)
    return [
        f"Manufacturer     {read_string_descriptor(device, device.iManufacturer)}",
        f"Product          {read_string_descriptor(device, device.iProduct)}",
        f"Serial           {serial}",
    ]


def describe_active_configuration(device) -> str:
    try:
        return f"Active config    {device.get_active_configuration().bConfigurationValue}"
    except usb.core.USBError as error:
        return f"Active config    none ({error}) -> no driver has configured the device"


def describe_kernel_driver_state(device) -> list[str]:
    lines = []
    for configuration in device:
        for interface in configuration.interfaces():
            number = interface.bInterfaceNumber
            try:
                state = "claimed by a kernel driver" if device.is_kernel_driver_active(number) else "free"
            except (usb.core.USBError, NotImplementedError) as error:
                state = f"unknown ({error})"
            lines.append(f"Interface {number}      {state}")
    return lines


def print_libusb_view(device, show_serial: bool) -> None:
    print("== libusb view ==")
    for line in describe_device(device) + describe_strings(device, show_serial):
        print(INDENT + line)
    print(INDENT + describe_active_configuration(device))
    for line in describe_kernel_driver_state(device):
        print(INDENT + line)
    for configuration in device:
        for line in describe_configuration(configuration):
            print(INDENT + line)


def print_registry_view(vendor_id: int, product_id: int) -> None:
    print("== macOS IORegistry view ==")
    entries = find_registry_devices(read_usb_registry(), vendor_id, product_id)
    if not entries:
        print(INDENT + "device not present in IORegistry")
    for entry in entries:
        print(f"{INDENT}{entry.get('IORegistryEntryName')} ({entry.get('IOObjectClass')})")
        attached = list_attached_objects(entry)
        if not attached:
            print(INDENT * 2 + "nothing attached")
        for registry_object in attached:
            print(f"{INDENT * (registry_object.depth + 1)}{registry_object.name} ({registry_object.object_class})")


def main() -> int:
    arguments = parse_arguments()
    # Before libusb enumerates: its own user client would otherwise show up as attached.
    print_registry_view(arguments.vid, arguments.pid)
    devices = list(usb.core.find(find_all=True, idVendor=arguments.vid, idProduct=arguments.pid))
    if not devices:
        print(f"No USB device {arguments.vid:04x}:{arguments.pid:04x} found. Is the dongle plugged in?")
        return EXIT_NOT_FOUND
    for device in devices:
        print_libusb_view(device, arguments.show_serial)
        usb.util.dispose_resources(device)
    return EXIT_FOUND


if __name__ == "__main__":
    sys.exit(main())
