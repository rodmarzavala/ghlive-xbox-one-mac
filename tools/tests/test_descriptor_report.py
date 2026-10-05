import unittest
from types import SimpleNamespace

from ghlproto.descriptor_report import (
    describe_endpoint,
    describe_interface,
    format_bcd,
    is_gip_interface,
    mask_serial,
)
from ghlproto.usb_ids import (
    GIP_INTERFACE_CLASS,
    GIP_INTERFACE_PROTOCOL,
    GIP_INTERFACE_SUBCLASS,
)

INTERRUPT_IN_EP1 = SimpleNamespace(bEndpointAddress=0x81, bmAttributes=0x03, wMaxPacketSize=64, bInterval=4)
BULK_OUT_EP2 = SimpleNamespace(bEndpointAddress=0x02, bmAttributes=0x02, wMaxPacketSize=512, bInterval=0)
VENDOR_CLASS = 0xFF


def make_interface(interface_class, subclass, protocol, endpoints=()):
    return SimpleNamespace(
        bInterfaceNumber=0,
        bAlternateSetting=0,
        bInterfaceClass=interface_class,
        bInterfaceSubClass=subclass,
        bInterfaceProtocol=protocol,
        bNumEndpoints=len(endpoints),
        endpoints=lambda: list(endpoints),
    )


class DescribeEndpointTest(unittest.TestCase):
    def test_interrupt_in_endpoint(self):
        self.assertEqual(
            describe_endpoint(INTERRUPT_IN_EP1),
            "EP 0x81  IN   interrupt    maxPacket=64 interval=4",
        )

    def test_bulk_out_endpoint(self):
        self.assertEqual(
            describe_endpoint(BULK_OUT_EP2),
            "EP 0x02  OUT  bulk         maxPacket=512 interval=0",
        )


class GipInterfaceTest(unittest.TestCase):
    def test_gip_triplet_is_recognized(self):
        gip = make_interface(GIP_INTERFACE_CLASS, GIP_INTERFACE_SUBCLASS, GIP_INTERFACE_PROTOCOL)
        self.assertTrue(is_gip_interface(gip))

    def test_other_vendor_interface_is_not_gip(self):
        self.assertFalse(is_gip_interface(make_interface(VENDOR_CLASS, 0x5D, 0x01)))

    def test_gip_interface_is_tagged_and_lists_endpoints(self):
        gip = make_interface(GIP_INTERFACE_CLASS, GIP_INTERFACE_SUBCLASS, GIP_INTERFACE_PROTOCOL, [INTERRUPT_IN_EP1])
        lines = describe_interface(gip)
        self.assertIn("<-- GIP", lines[0])
        self.assertIn("EP 0x81", lines[1])


class FormattingTest(unittest.TestCase):
    def test_format_bcd(self):
        self.assertEqual(format_bcd(0x0110), "1.10")
        self.assertEqual(format_bcd(0x0200), "2.00")

    def test_mask_serial_keeps_last_four(self):
        self.assertEqual(mask_serial("0000ABCD12345678"), "************5678")

    def test_mask_serial_short_value_fully_masked(self):
        self.assertEqual(mask_serial("1234"), "****")


if __name__ == "__main__":
    unittest.main()
