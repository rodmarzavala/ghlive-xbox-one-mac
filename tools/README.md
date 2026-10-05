# Prototype tools (phases 1–4)

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

## Play

Turns the guitar into keyboard events.

```sh
.venv/bin/pip install -r requirements.txt     # includes the PyObjC Quartz bindings
.venv/bin/python play.py --dry-run --verbose  # logs the keys it would press, posts nothing
.venv/bin/python play.py                      # presses real keys
```

Posting keys needs the **Accessibility** permission: System Settings > Privacy & Security > Accessibility, enable the terminal app you run it from, then restart that terminal. Without it `play.py` prints this hint and exits with code 2.

Every key is released on Ctrl-C and when the dongle is unplugged.

Options: `--keymap PATH` (default `keymaps/default.toml`), `--verbose`, `--dry-run`.

### Editing the keymap

Copy `keymaps/default.toml`, edit it and pass it with `--keymap`. `[keys]` maps a control name to a key name (`a`-`z`, `0`-`9`, `up`, `down`, `left`, `right`, `space`, `return`, `escape`, `tab`, `f1`-`f12`). Several controls may share one key; the key stays down while any of them is active. An unknown control or key is reported by name.

### Calibrating tilt

Tilt is an analog byte (about 110 at rest). `--verbose` prints the active controls whenever they change, and every time the raw tilt moves by 10 or more:

```
tilt | tilt=171
none | tilt=108
```

Raise the guitar the way you play, note the values, and set `[thresholds] tilt` in your keymap below the raised value and well above rest. Tilt releases once it drops below `tilt - tilt_hysteresis` (default 10), so jitter at the edge does not chatter. `whammy` (0.0 to 1.0) works the same way.

## Lint and tests

```sh
.venv/bin/ruff check . && .venv/bin/ruff format --check .
.venv/bin/python -m unittest discover -s tests -t .
```
