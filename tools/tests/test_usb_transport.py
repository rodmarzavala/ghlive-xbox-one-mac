import unittest
from types import SimpleNamespace
from unittest import mock

import usb.core
import usb.util

from ghlproto.usb_ids import GIP_INTERFACE_CLASS, GIP_INTERFACE_PROTOCOL, GIP_INTERFACE_SUBCLASS
from ghlproto.usb_transport import (
    GIP_CONFIGURATION_VALUE,
    DongleNotFoundError,
    DongleTransport,
    GipInterfaceNotFoundError,
)

VENDOR_ID = 0x1234
PRODUCT_ID = 0x5678
INTERFACE_NUMBER = 0
IN_ADDRESS = 0x81
OUT_ADDRESS = 0x01
MAX_PACKET_SIZE = 64
READ_TIMEOUT_MS = 250


class FakeInterface(list):
    """A real pyusb interface is an iterable of endpoints, so usb.util.find_descriptor works on this."""

    def __init__(self, endpoints, interface_class=GIP_INTERFACE_CLASS):
        super().__init__(endpoints)
        self.bInterfaceNumber = INTERFACE_NUMBER
        self.bInterfaceClass = interface_class
        self.bInterfaceSubClass = GIP_INTERFACE_SUBCLASS
        self.bInterfaceProtocol = GIP_INTERFACE_PROTOCOL


def endpoint(address: int, **attributes) -> SimpleNamespace:
    return SimpleNamespace(bEndpointAddress=address, wMaxPacketSize=MAX_PACKET_SIZE, **attributes)


def make_device(interface: FakeInterface) -> mock.Mock:
    device = mock.Mock()
    device.get_active_configuration.return_value = [interface]
    return device


class DongleTransportTest(unittest.TestCase):
    def setUp(self):
        self.in_endpoint = endpoint(IN_ADDRESS, read=mock.Mock(return_value=bytearray(b"\x01\x02")))
        self.out_endpoint = endpoint(OUT_ADDRESS, write=mock.Mock())
        self.device = make_device(FakeInterface([self.in_endpoint, self.out_endpoint]))
        for name in ("claim_interface", "release_interface", "dispose_resources"):
            patcher = mock.patch(f"usb.util.{name}")
            setattr(self, name, patcher.start())
            self.addCleanup(patcher.stop)

    def test_open_raises_when_the_device_is_not_found(self):
        with mock.patch("usb.core.find", return_value=None), self.assertRaises(DongleNotFoundError):
            DongleTransport.open(VENDOR_ID, PRODUCT_ID)

    def test_open_looks_the_device_up_by_ids(self):
        with mock.patch("usb.core.find", return_value=self.device) as find:
            DongleTransport.open(VENDOR_ID, PRODUCT_ID)
        find.assert_called_once_with(idVendor=VENDOR_ID, idProduct=PRODUCT_ID)

    def test_configure_sets_configuration_and_claims_the_gip_interface(self):
        DongleTransport(self.device).configure()
        self.device.set_configuration.assert_called_once_with(GIP_CONFIGURATION_VALUE)
        self.claim_interface.assert_called_once_with(self.device, INTERFACE_NUMBER)

    def test_write_goes_to_the_out_endpoint(self):
        transport = DongleTransport(self.device)
        transport.configure()
        transport.write(b"\x05")
        self.out_endpoint.write.assert_called_once_with(b"\x05")

    def test_read_returns_bytes(self):
        transport = DongleTransport(self.device)
        transport.configure()
        self.assertEqual(transport.read(READ_TIMEOUT_MS), b"\x01\x02")
        self.in_endpoint.read.assert_called_once_with(MAX_PACKET_SIZE, timeout=READ_TIMEOUT_MS)

    def test_read_maps_timeout_to_none(self):
        self.in_endpoint.read.side_effect = usb.core.USBTimeoutError("timeout")
        transport = DongleTransport(self.device)
        transport.configure()
        self.assertIsNone(transport.read(READ_TIMEOUT_MS))

    def test_io_before_configure_is_refused(self):
        transport = DongleTransport(self.device)
        with self.assertRaises(RuntimeError):
            transport.write(b"\x05")
        with self.assertRaises(RuntimeError):
            transport.read(READ_TIMEOUT_MS)

    def test_close_releases_only_after_a_claim(self):
        DongleTransport(self.device).close()
        self.release_interface.assert_not_called()
        self.dispose_resources.assert_called_once_with(self.device)

    def test_close_releases_a_claimed_interface(self):
        transport = DongleTransport(self.device)
        transport.configure()
        transport.close()
        self.release_interface.assert_called_once_with(self.device, INTERFACE_NUMBER)

    def test_closing_twice_releases_the_interface_once(self):
        transport = DongleTransport(self.device)
        transport.configure()
        transport.close()
        transport.close()
        self.release_interface.assert_called_once()

    def test_close_ignores_usb_errors_from_an_unplugged_device(self):
        self.release_interface.side_effect = usb.core.USBError("no such device")
        transport = DongleTransport(self.device)
        transport.configure()
        transport.close()
        self.dispose_resources.assert_called_once_with(self.device)

    def test_context_manager_configures_and_closes(self):
        with DongleTransport(self.device) as transport:
            transport.write(b"\x05")
        self.claim_interface.assert_called_once()
        self.release_interface.assert_called_once()

    def test_failed_configure_inside_context_manager_still_cleans_up(self):
        self.device.set_configuration.side_effect = usb.core.USBError("busy")
        with self.assertRaises(usb.core.USBError), DongleTransport(self.device):
            pass
        self.dispose_resources.assert_called_once_with(self.device)

    def test_missing_gip_interface_raises_domain_error(self):
        device = make_device(FakeInterface([self.in_endpoint, self.out_endpoint], interface_class=0x03))
        with self.assertRaises(GipInterfaceNotFoundError):
            DongleTransport(device).configure()
        self.claim_interface.assert_not_called()

    def test_missing_endpoint_raises_domain_error(self):
        device = make_device(FakeInterface([self.in_endpoint]))
        with self.assertRaises(GipInterfaceNotFoundError):
            DongleTransport(device).configure()
        self.claim_interface.assert_not_called()


if __name__ == "__main__":
    unittest.main()
