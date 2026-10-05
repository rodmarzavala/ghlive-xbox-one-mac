import plistlib
import unittest

from ghlproto.macos_registry import find_registry_devices, list_attached_objects

TEST_VENDOR_ID = 0x1430
TEST_PRODUCT_ID = 0x079B
OTHER_PRODUCT_ID = 0x0001

DONGLE_ENTRY = {
    "IORegistryEntryName": "Guitar Hero",
    "IOObjectClass": "IOUSBHostDevice",
    "idVendor": TEST_VENDOR_ID,
    "idProduct": TEST_PRODUCT_ID,
    "IORegistryEntryChildren": [
        {"IORegistryEntryName": "steam_osx", "IOObjectClass": "AppleUSBHostDeviceUserClient"},
        {
            "IORegistryEntryName": "IOUSBHostInterface@0",
            "IOObjectClass": "IOUSBHostInterface",
            "IORegistryEntryChildren": [
                {"IORegistryEntryName": "SomeDriver", "IOObjectClass": "SomeDriverClass"},
            ],
        },
    ],
}
OTHER_ENTRY = {
    "IORegistryEntryName": "Microphone",
    "IOObjectClass": "IOUSBHostDevice",
    "idVendor": TEST_VENDOR_ID,
    "idProduct": OTHER_PRODUCT_ID,
}


class FindRegistryDevicesTest(unittest.TestCase):
    def test_filters_by_vendor_and_product(self):
        plist = plistlib.dumps([DONGLE_ENTRY, OTHER_ENTRY])
        found = find_registry_devices(plist, TEST_VENDOR_ID, TEST_PRODUCT_ID)
        self.assertEqual([entry["IORegistryEntryName"] for entry in found], ["Guitar Hero"])

    def test_finds_device_nested_behind_a_hub(self):
        hub = {"IORegistryEntryName": "USB2.0 HUB", "IORegistryEntryChildren": [OTHER_ENTRY, DONGLE_ENTRY]}
        found = find_registry_devices(plistlib.dumps([hub]), TEST_VENDOR_ID, TEST_PRODUCT_ID)
        self.assertEqual([entry["IORegistryEntryName"] for entry in found], ["Guitar Hero"])

    def test_empty_output_yields_no_devices(self):
        self.assertEqual(find_registry_devices(b"", TEST_VENDOR_ID, TEST_PRODUCT_ID), [])


class ListAttachedObjectsTest(unittest.TestCase):
    def test_lists_children_recursively_with_depth(self):
        self.assertEqual(
            list_attached_objects(DONGLE_ENTRY),
            [
                (1, "steam_osx", "AppleUSBHostDeviceUserClient"),
                (1, "IOUSBHostInterface@0", "IOUSBHostInterface"),
                (2, "SomeDriver", "SomeDriverClass"),
            ],
        )


if __name__ == "__main__":
    unittest.main()
