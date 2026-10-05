import plistlib
import subprocess
from collections.abc import Iterator
from typing import NamedTuple

IOREG_COMMAND = ["ioreg", "-a", "-l", "-r", "-c", "IOUSBHostDevice"]
CHILDREN_KEY = "IORegistryEntryChildren"
NAME_KEY = "IORegistryEntryName"
CLASS_KEY = "IOObjectClass"


class RegistryObject(NamedTuple):
    depth: int
    name: str
    object_class: str


def read_usb_registry() -> bytes:
    return subprocess.run(IOREG_COMMAND, capture_output=True, check=True).stdout


def find_registry_devices(ioreg_plist: bytes, vendor_id: int, product_id: int) -> list[dict]:
    if not ioreg_plist.strip():
        return []
    return [
        entry
        for entry in walk_entries(plistlib.loads(ioreg_plist))
        if entry.get("idVendor") == vendor_id and entry.get("idProduct") == product_id
    ]


def walk_entries(entries: list[dict]) -> Iterator[dict]:
    for entry in entries:
        yield entry
        yield from walk_entries(entry.get(CHILDREN_KEY, []))


def list_attached_objects(entry: dict, depth: int = 1) -> list[RegistryObject]:
    attached = []
    for child in entry.get(CHILDREN_KEY, []):
        attached.append(RegistryObject(depth, child.get(NAME_KEY, "?"), child.get(CLASS_KEY, "?")))
        attached.extend(list_attached_objects(child, depth + 1))
    return attached
