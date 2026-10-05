# Prototype tools (phases 1–3)

Python + pyusb (libusb) scripts for reverse engineering the dongle. The final app is Swift; these stay as diagnostics.

## Setup

```sh
brew install libusb
cd tools
python3 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt
```

## Discovery (read-only)

```sh
.venv/bin/python discover.py            # serial masked
.venv/bin/python discover.py --show-serial
```

It only reads descriptors; it never configures or claims the device.

## Lint and tests

```sh
.venv/bin/ruff check . && .venv/bin/ruff format --check .
.venv/bin/python -m unittest discover -s tests -t .
```
