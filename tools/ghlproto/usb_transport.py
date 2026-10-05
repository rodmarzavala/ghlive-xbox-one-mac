import contextlib
from types import TracebackType

import usb.core
import usb.util

from ghlproto.descriptor_report import is_gip_interface

GIP_CONFIGURATION_VALUE = 1


class DongleNotFoundError(RuntimeError):
    pass


class GipInterfaceNotFoundError(DongleNotFoundError):
    pass


class DongleTransport:
    """Owns the USB device: configuration, interface claim and interrupt I/O. Use as a context manager."""

    def __init__(self, device: usb.core.Device) -> None:
        self._device = device
        self._interface: usb.core.Interface | None = None
        self._in_endpoint: usb.core.Endpoint | None = None
        self._out_endpoint: usb.core.Endpoint | None = None

    @classmethod
    def open(cls, vendor_id: int, product_id: int) -> "DongleTransport":
        device = usb.core.find(idVendor=vendor_id, idProduct=product_id)
        if device is None:
            raise DongleNotFoundError(f"USB device {vendor_id:04x}:{product_id:04x} not found")
        return cls(device)

    def __enter__(self) -> "DongleTransport":
        try:
            self.configure()
        except BaseException:
            self.close()
            raise
        return self

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc_value: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        self.close()

    def configure(self) -> None:
        # macOS leaves the dongle unconfigured because no driver matches it.
        self._device.set_configuration(GIP_CONFIGURATION_VALUE)
        interface = next(
            (candidate for candidate in self._device.get_active_configuration() if is_gip_interface(candidate)),
            None,
        )
        if interface is None:
            raise GipInterfaceNotFoundError("the device has no GIP interface")
        in_endpoint = self._find_endpoint(interface, usb.util.ENDPOINT_IN)
        out_endpoint = self._find_endpoint(interface, usb.util.ENDPOINT_OUT)
        if in_endpoint is None or out_endpoint is None:
            raise GipInterfaceNotFoundError("the GIP interface lacks an IN or OUT endpoint")
        usb.util.claim_interface(self._device, interface.bInterfaceNumber)
        self._interface = interface
        self._in_endpoint = in_endpoint
        self._out_endpoint = out_endpoint

    def write(self, data: bytes) -> None:
        if self._out_endpoint is None:
            raise RuntimeError("transport is not configured")
        self._out_endpoint.write(data)

    def read(self, timeout_ms: int) -> bytes | None:
        if self._in_endpoint is None:
            raise RuntimeError("transport is not configured")
        try:
            return bytes(self._in_endpoint.read(self._in_endpoint.wMaxPacketSize, timeout=timeout_ms))
        except usb.core.USBTimeoutError:
            return None

    def close(self) -> None:
        if self._interface is not None:
            # An unplugged device can no longer release anything.
            with contextlib.suppress(usb.core.USBError):
                usb.util.release_interface(self._device, self._interface.bInterfaceNumber)
            self._interface = None
        usb.util.dispose_resources(self._device)

    @staticmethod
    def _find_endpoint(interface: usb.core.Interface, direction: int) -> usb.core.Endpoint | None:
        return usb.util.find_descriptor(
            interface,
            custom_match=lambda endpoint: usb.util.endpoint_direction(endpoint.bEndpointAddress) == direction,
        )
