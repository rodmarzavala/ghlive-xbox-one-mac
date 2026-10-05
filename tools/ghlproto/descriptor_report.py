import usb.util

from ghlproto.usb_ids import (
    GIP_INTERFACE_CLASS,
    GIP_INTERFACE_PROTOCOL,
    GIP_INTERFACE_SUBCLASS,
)

TRANSFER_TYPE_NAMES = {
    usb.util.ENDPOINT_TYPE_CTRL: "control",
    usb.util.ENDPOINT_TYPE_ISO: "isochronous",
    usb.util.ENDPOINT_TYPE_BULK: "bulk",
    usb.util.ENDPOINT_TYPE_INTR: "interrupt",
}
MAX_POWER_UNIT_MA = 2
SERIAL_VISIBLE_SUFFIX_LENGTH = 4
GIP_MARKER = "<-- GIP"


def format_bcd(value: int) -> str:
    return f"{value >> 8:x}.{value & 0xFF:02x}"


def mask_serial(serial: str) -> str:
    if len(serial) <= SERIAL_VISIBLE_SUFFIX_LENGTH:
        return "*" * len(serial)
    hidden_length = len(serial) - SERIAL_VISIBLE_SUFFIX_LENGTH
    return "*" * hidden_length + serial[hidden_length:]


def is_gip_interface(interface) -> bool:
    return (
        interface.bInterfaceClass == GIP_INTERFACE_CLASS
        and interface.bInterfaceSubClass == GIP_INTERFACE_SUBCLASS
        and interface.bInterfaceProtocol == GIP_INTERFACE_PROTOCOL
    )


def describe_endpoint(endpoint) -> str:
    is_in = usb.util.endpoint_direction(endpoint.bEndpointAddress) == usb.util.ENDPOINT_IN
    transfer_type = TRANSFER_TYPE_NAMES[usb.util.endpoint_type(endpoint.bmAttributes)]
    return (
        f"EP 0x{endpoint.bEndpointAddress:02x}  {'IN' if is_in else 'OUT':<4} {transfer_type:<12} "
        f"maxPacket={endpoint.wMaxPacketSize} interval={endpoint.bInterval}"
    )


def describe_interface(interface) -> list[str]:
    header = (
        f"Interface {interface.bInterfaceNumber} alt {interface.bAlternateSetting}: "
        f"class=0x{interface.bInterfaceClass:02x} subclass=0x{interface.bInterfaceSubClass:02x} "
        f"protocol=0x{interface.bInterfaceProtocol:02x} endpoints={interface.bNumEndpoints}"
    )
    if is_gip_interface(interface):
        header = f"{header}  {GIP_MARKER}"
    return [header] + [f"  {describe_endpoint(endpoint)}" for endpoint in interface.endpoints()]


def describe_configuration(configuration) -> list[str]:
    lines = [
        f"Configuration {configuration.bConfigurationValue}: "
        f"interfaces={configuration.bNumInterfaces} attributes=0x{configuration.bmAttributes:02x} "
        f"maxPower={configuration.bMaxPower * MAX_POWER_UNIT_MA}mA"
    ]
    for interface in configuration.interfaces():
        lines.extend(f"  {line}" for line in describe_interface(interface))
    return lines


def describe_device(device) -> list[str]:
    return [
        f"VID:PID          {device.idVendor:04x}:{device.idProduct:04x}",
        f"USB version      {format_bcd(device.bcdUSB)}",
        f"Device release   {format_bcd(device.bcdDevice)}",
        f"Device class     0x{device.bDeviceClass:02x}/0x{device.bDeviceSubClass:02x}/0x{device.bDeviceProtocol:02x}",
        f"EP0 max packet   {device.bMaxPacketSize0}",
        f"Configurations   {device.bNumConfigurations}",
    ]
