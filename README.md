# GHLive Xbox One for Mac

Play **Guitar Hero Live on macOS**: use the GHL guitar with its Xbox One USB dongle in Clone Hero, YARG and other games that take keyboard input.

[![CI](https://github.com/rodmarzavala/ghlive-xbox-one-mac/actions/workflows/ci.yml/badge.svg)](https://github.com/rodmarzavala/ghlive-xbox-one-mac/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/rodmarzavala/ghlive-xbox-one-mac?include_prereleases&label=release)](https://github.com/rodmarzavala/ghlive-xbox-one-mac/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-lightgrey)
![Universal: Apple Silicon and Intel](https://img.shields.io/badge/universal-Apple%20Silicon%20%2B%20Intel-informational)

macOS ships no driver for this dongle: it stays unconfigured and its LED never turns on. GHLive is a small menu-bar app that talks to the dongle directly over USB, reads the guitar, and turns every fret, strum and button into a key press. No kernel extensions, no SIP changes.

## Screenshots

<!-- TODO: add a short demo GIF (docs/images/demo.gif) showing the guitar driving the Input Monitor. -->

| Input Monitor | Menu bar |
|---|---|
| ![The Input Monitor showing live frets, strum, whammy and tilt](docs/images/monitor-active-dark.png) | ![The GHLive menu with the guitar connected](docs/images/menu-active-light.png) |

![The Settings window with the key for each control and the sensitivity sliders](docs/images/settings-light.png)

## Features

- Menu-bar app, no Dock icon. Launch at Login is optional.
- Automatic reconnection: plug or unplug the dongle at any time.
- Settings window: click a control, press a key, done. Changes save automatically, and there is a "Restore defaults" button.
- Input Monitor: live frets, strum, buttons, d-pad, whammy and tilt meters with their thresholds, plus the keys currently being sent.
- "Test my guitar": a checklist in the Input Monitor that confirms every control is read correctly.
- Adjustable tilt and whammy thresholds.
- Adds 6-fret tracks to your 5-fret Clone Hero songs, with a backup first.
- Pause and Resume from the menu.
- A command-line tool, `ghlive`, for diagnostics and headless use.
- Sends only keyboard events. No network access, no data collection.

## Requirements

- macOS 13 (Ventura) or newer, Apple Silicon or Intel (the app is universal).
- A Guitar Hero Live guitar and its **Xbox One** wireless dongle (USB ID `1430:079B`).
- A game that lets you bind keyboard keys to guitar controls (Clone Hero and YARG do).

## Install

1. Download `GHLive-<version>-macos-universal.zip` from the [latest release](https://github.com/rodmarzavala/ghlive-xbox-one-mac/releases) and unzip it.
2. Move `GHLive.app` to your `Applications` folder.
3. **First launch.** GHLive is ad-hoc signed but not notarized by Apple (see [why](#why-is-the-app-unsigned)), so macOS blocks it the first time. Open it once and dismiss the warning, then pick one of these:
   - **System Settings** -> **Privacy & Security**, scroll down to the message about GHLive and click **Open Anyway**. (Right-click -> Open no longer works on recent macOS versions.)
   - Or in Terminal: `xattr -dr com.apple.quarantine /Applications/GHLive.app`, then open the app again.
4. A guitar icon appears in the menu bar. Click it: until permission is granted, the menu shows a card, "Allow GHLive to press keys", with a **Grant Accessibility access...** button. Click it; macOS asks for permission and opens System Settings, where you switch GHLive on. This is required to send key presses.
5. Plug in the dongle. The status line goes from "Waiting for the dongle" to "Connecting to the dongle" and then "Dongle ready, turn on your guitar", and the dongle LED lights up.
6. Turn on the guitar. The status changes to "Guitar connected". If it does not connect, turn the guitar off and on again.

Want to check what you downloaded first? See [Verify your download](#verify-your-download). More install detail: [docs/install.md](docs/install.md).

### The menu

Status line, Pause / Resume, Settings..., Input Monitor..., Launch at Login, Open keymap folder, About GHLive, Quit GHLive.

**Launch at Login:** macOS may need your approval the first time. The menu then shows "Approve GHLive in System Settings > Login Items" with an **Open Login Items...** button; switch GHLive on there.

Your keymap is stored in `~/Library/Application Support/GHLive/keymap.json`.

### Default keys

| Guitar control | Key |
|---|---|
| Black 1 / 2 / 3 (top frets) | `1` / `2` / `3` |
| White 1 / 2 / 3 (bottom frets) | `Q` / `W` / `E` |
| Strum up / down | Up arrow / Down arrow |
| Hero Power | Space |
| Tilt | Space |
| Whammy bar | `X` |
| Pause | Esc |
| GHTV | Tab |
| D-pad | Arrow keys |

In Settings (controls are grouped under Frets, Strum bar, Buttons, D-pad, and Whammy bar and tilt), click a control, then press the key you want. Supported keys: A-Z, 0-9, the arrow keys, Space, Tab, Return, Escape and F1-F12.

### Presets

Settings has a **Preset** row at the top. **6-fret (GHL charts)** is the default above. **5-fret (classic charts)** maps the guitar onto five lanes (see [Playing classic 5-fret charts](#playing-classic-5-fret-charts)). Choosing a preset replaces your keys after a confirmation and keeps your tilt and whammy settings; the row shows "Custom keys" once you change a key yourself.

## Set up Clone Hero

GHLive makes the guitar look like a keyboard, so the game needs to know which key is which control. Clone Hero supports 6-fret (GHL) guitars, and its controls can be bound to keys. In the game's controller settings, bind each guitar control to the key GHLive sends for it, using the table above (or your own keys from GHLive's Settings). Keep the game as the active window while you play: macOS delivers key presses to the app in front.

[YARG](https://yarg.in/) works the same way, since it accepts keyboard input: bind the keys in its own controller settings.

The exact menu names differ between game versions, so this guide does not spell them out. The Input Monitor helps here: it shows which key each control is sending right now.

### Playing classic 5-fret charts

Many charts are 5-fret only. To play a 5-fret chart with the 6-fret guitar:

1. In GHLive's Settings, choose the **5-fret (classic charts)** preset and confirm.
2. In the game, bind the keyboard as a regular 5-fret guitar using the keys `1` to `5` for Green, Red, Yellow, Blue and Orange. The strum bar, Hero Power (Star Power), whammy and pause keys are the same as in the table above.

| Lane | Key | Guitar control |
|---|---|---|
| Green | `1` | White 1 (bottom row), or Black 1 |
| Red | `2` | White 2 (bottom row) |
| Yellow | `3` | White 3 (bottom row) |
| Blue | `4` | Black 2 (top row) |
| Orange | `5` | Black 3 (top row) |

Black 1 also sends Green so the first column is comfortable from either row. This layout is a starting point: click any control in Settings to give it another key.

![Settings with the 5-fret preset applied](docs/images/settings-preset-five-fret-light.png)

## Play 5-fret songs as 6-fret

Most Clone Hero charts have a 5-fret guitar track only. GHLive can add a 6-fret (GHL) track to them, so the song shows up under the **6-fret guitar** instrument in Clone Hero and you play it with the GHL guitar and its 6-fret keymap. The 5-fret track stays, and nothing is ever removed.

Use **Add 6-fret tracks to songs...** in the menu-bar menu, or `ghlive charts add-ghl <folder>` in a terminal. Choose your Clone Hero songs folder; GHLive handles the folders inside it too, packs included.

![The confirmation, which says where the backup will go](docs/images/chart-conversion-confirm-light.png)

The conversion is automatic and the same every time: it follows Clone Hero's own pairing of the 5-fret and 6-fret controls, so the converted chart plays like the 5-fret chart does with the same key bindings. White 3 has no 5-fret counterpart, so it is never used. It is **not** a hand-made GHL chart; a chart written for the 6-fret guitar will play more naturally.

| 5-fret lane | 6-fret lane |
|---|---|
| Green | Black 1 |
| Red | Black 2 |
| Yellow | Black 3 |
| Blue | White 1 |
| Orange | White 2 |
| Open | Open |

Force/flip and tap notes, star power and solos are kept. `.chart` and `.mid` songs are converted; `.sng` songs are skipped for now ("not supported yet"). The exact rules are in [docs/chart-conversion.md](docs/chart-conversion.md).

**Your files are backed up first.** Before a song is changed, a copy of its files goes to a new folder next to your songs folder, named like `Clone Hero Songs - backup 2025-01-31 183000`, with the same folder structure. It is deliberately outside the songs folder, because Clone Hero would otherwise scan the copies as duplicate songs. Every new file is read back and checked (the same notes, the same timing) before it replaces the original; if anything fails, the original is left as it was. Running it again adds nothing.

GHLive also adds `diff_guitarghl` to a song's `song.ini` when it is missing (copying the value of `diff_guitar`, or 0), since Clone Hero may hide the 6-fret part without it. An existing `diff_guitarghl` is never changed, and the same fix is applied to songs that already had a 6-fret track.

![The result: a summary, the backup location and the list of songs](docs/images/chart-conversion-result-dark.png)

**Then rescan your songs in Clone Hero**, so the new 6-fret parts show up.

`ghlive charts add-ghl <folder> --dry-run` only reports what would change and writes nothing, not even a backup.

## Check that your guitar works

Before you open Clone Hero, confirm in about a minute that every control is read correctly.

1. Open **Input Monitor...** from the menu and click **Test my guitar**.
2. Press every fret, both strum directions, Hero Power, Pause, GHTV and each d-pad direction once. Each one gets a green check the first time it is seen.
3. Push the whammy bar all the way down and let it go back, then raise the guitar neck past the tilt threshold and lower it again. Both rows show the range they have seen.
4. When all 17 controls are checked, the monitor says "All controls work. You're ready to play."

**Start over** clears the checks. Losing the guitar's connection does not. If a control never gets its check, see [Troubleshooting](#troubleshooting).

![The Input Monitor in test mode, part-way through](docs/images/monitor-guitar-test-light.png)

## Calibrating tilt and whammy

Keyboard keys are on or off, so the whammy bar and tilt become switches that trigger once they pass a threshold.

1. Open **Input Monitor...** from the menu. It shows live frets, strum, buttons, d-pad, whammy and tilt meters, each with its threshold, and the keys being sent.
2. Move the whammy bar and raise the guitar. The meters show the live value next to "trigger at ...".
3. Open **Settings...** and adjust:
   - **Tilt threshold**, 1 to 255 (default 150). The guitar resting flat reads around 95 to 115, so set the threshold above that and below the value you reach when you raise the neck.
   - **Whammy threshold**, 0.05 to 1.0 (default 0.5): how far to push the bar before it counts as pressed.
4. Watch the keys being sent in the Input Monitor to confirm.

## Verify your download

Each release has two artifacts, each with a `.sha256` file:

- `GHLive-<version>-macos-universal.zip` (the app)
- `ghlive-<version>-macos-universal.tar.gz` (the command-line tool)

They are built by GitHub Actions from the tagged source and carry build provenance attestations. From the folder with the downloads:

```sh
shasum -a 256 -c GHLive-<version>-macos-universal.zip.sha256
gh attestation verify GHLive-<version>-macos-universal.zip --repo rodmarzavala/ghlive-xbox-one-mac
```

The first command checks the file was not corrupted or swapped. The second (needs the [GitHub CLI](https://cli.github.com/)) proves the file was produced by this repository's release workflow. Do the same for the `.tar.gz`.

## Build from source

You need Xcode or the Command Line Tools (`xcode-select --install`), and Swift 6.

```sh
make build      # swift build
make test       # swift test; works with only the Command Line Tools thanks to a Swift Testing plugin-path workaround
make lint       # swift format lint --strict
make release    # universal (arm64 + x86_64) release build
make app        # same as scripts/build-app.sh: GHLive.app and the CLI in dist/, like CI
```

Other useful commands:

```sh
swift scripts/make-icon.swift Resources/AppIcon.icns   # regenerate the app icon
GHLIVE_DRY_RUN=1 swift run GHLiveApp                    # GUI that posts no keys
swift run GHLiveApp --export-screenshots <dir>          # render the UI states to PNG files
GHLIVE_DRY_RUN=1 swift run GHLiveApp --open-window settings   # also: monitor; opens that window at launch
```

You are encouraged to compare the contents of your locally built zip with the release. The binaries will not be bit-identical, but you can compare the file list and `Info.plist`.

### The `ghlive` command

```text
ghlive run [--dry-run] [--verbose] [--keymap PATH]   wait for the dongle and send key presses
ghlive sniff                                          print the raw GIP packets (for bug reports)
ghlive keymap --print-default                         print the default keymap as JSON
ghlive keymap --print-preset five-fret|six-fret       print a keymap preset as JSON
ghlive charts add-ghl <folder> [--dry-run]            add 6-fret tracks to the 5-fret songs in a folder
ghlive --version
```

`--dry-run` prints `key down` / `key up` lines instead of posting keys and needs no Accessibility permission. Without it, your terminal needs Accessibility access. Errors are always printed to stderr as `error: <message> (retrying)`, with or without `--verbose`.

## Troubleshooting

Short version. Full guide: [docs/troubleshooting.md](docs/troubleshooting.md).

- **The dongle LED does not turn on.** Check the status line in the menu. If it says the dongle is in use by another app, see below. Otherwise unplug and replug it.
- **The guitar does not sync.** Switch the guitar on once the status reads "Dongle ready".
- **"The dongle is in use by another app".** Quit Steam, or any other app that reads Xbox controllers. GHLive retries every few seconds.
- **A control never gets its check in "Test my guitar".** The Input Monitor does not see it: see [Check that your guitar works](#check-that-your-guitar-works) and [docs/troubleshooting.md](docs/troubleshooting.md#a-control-fails-the-guitar-test).
- **Keys do not reach the game.** Click "Grant Accessibility access..." in the menu and keep the game window focused.
- **It stopped working after an update.** Remove GHLive from the Accessibility list and add it again.
- **Intel Macs.** The build is universal and includes an Intel slice, but it has not been tested on an Intel Mac. Please report what you find.

## FAQ

**Is it safe?** The app only posts keyboard events. It has no network access and collects no data, and the source is right here to read. You can [verify](#verify-your-download) that your download was built from this repository.

### Why is the app unsigned?

Apple notarization requires a paid Apple Developer account, and this is a free hobby project without one. So the app is only ad-hoc signed and macOS shows a warning on first launch. Checksums and build attestations are the substitute: they let you confirm the file came from this repository's GitHub Actions build.

**Does it need kexts or SIP changes?** No. It runs in user space.

**Does it work with YARG?** YARG accepts keyboard input, so bind the keys the same way as in Clone Hero. This has not been tested with YARG.

**Can whammy and tilt be analog?** Not in v1. See [Limitations](#limitations).

**What about my PS3, Wii U or PS4 dongle?** Those are standard HID devices that Clone Hero reads directly, so you do not need GHLive. The Xbox 360 dongle is out of scope.

## Limitations

- v1 outputs keyboard events only, so whammy and tilt are on/off, not analog.
- Only the Xbox One GHL dongle (`1430:079B`) is supported.
- A virtual gamepad (DriverKit) is a possible future addition; the architecture already has a seam for it.
- The app is not notarized, so macOS may ask for Accessibility access again after each update.

## How it works

GHLive finds the dongle by its USB ID, configures it, runs the GIP (Gaming Input Protocol) power-on handshake, keeps it streaming with a periodic keep-alive, decodes the guitar's reports and posts matching keyboard events. Details: [docs/architecture.md](docs/architecture.md) and [docs/protocol-notes.md](docs/protocol-notes.md).

The `tools/` folder holds the Python prototype used to reverse-engineer the dongle (discovery, handshake, play). It is kept as a diagnostic; see [tools/README.md](tools/README.md).

## Contributing

Bug reports, packet logs and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) first. Security issues: [SECURITY.md](SECURITY.md). Changes per release: [CHANGELOG.md](CHANGELOG.md).

## Credits

- [PlasticBand](https://github.com/TheNathannator/PlasticBand) by TheNathannator, community documentation of rhythm game peripherals (CC BY-SA).
- [RB4InstrumentMapper](https://github.com/TheNathannator/RB4InstrumentMapper), the Windows mapper that supports this guitar.
- [MS-GIPUSB](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gipusb/e7c90904-5e21-426e-b9ad-d82adeee0dbc), Microsoft's open specification of GIP over USB.
- [xpad](https://github.com/paroj/xpad), the Linux driver, consulted only for protocol facts; no GPL code is used here.

## License

[MIT](LICENSE).

GHLive is an independent project. It is not affiliated with, endorsed by or sponsored by Activision, Microsoft or Clone Hero. "Guitar Hero", "Xbox" and "Clone Hero" belong to their respective owners.
