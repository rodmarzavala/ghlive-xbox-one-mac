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

## Handshake

```sh
.venv/bin/python handshake.py --seconds 10
```

Configures the dongle, powers it on over GIP and logs every packet. `--seconds` limits the run (default 60, 0 runs until Ctrl-C). `--show-repeats` prints every guitar input report instead of only the ones that changed.

It holds the device exclusively: quit apps that may have it open (Steam, Plex, browser tabs using WebUSB) first.

## Lint and tests

```sh
.venv/bin/ruff check . && .venv/bin/ruff format --check .
.venv/bin/python -m unittest discover -s tests -t .
```
