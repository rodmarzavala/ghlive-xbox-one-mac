# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- GHLive now writes its events to the macOS system log (subsystem `io.github.rodmarzavala.ghlive`), so a problem reported days later leaves evidence: dongle arrival and removal, status changes, connection and USB errors, the guitar going silent, how many keys were released and why, pause and resume, Accessibility changes, and launch and quit. It logs events only, never which keys or controls you press. See [Collecting logs](docs/troubleshooting.md#collecting-logs).

## [1.0.1] - 2026-10-06

### Fixed

- Card shadows in the Settings and Input Monitor windows are no longer cut off at the edges, and the faint lighter box around the content is gone. The windows only scroll when they cannot fit the screen.

## [1.0.0] - 2026-10-06

First stable release: play the Guitar Hero Live guitar with its Xbox One dongle on macOS, in Clone Hero and other games that take keyboard input.

### Highlights

- Menu-bar app for macOS 13 or newer, universal (Apple Silicon and Intel), with no kernel extension, no SIP change and no driver to install.
- Every fret, the strum bar, Hero Power, Pause, GHTV, the d-pad, whammy and tilt become key presses, released safely on pause, disconnect and quit.
- Automatic reconnection, Settings to rebind keys with 6-fret and 5-fret presets, the Input Monitor and "Test my guitar".
- Liquid Glass on macOS 26 and later.
- A [Clone Hero setup guide](https://github.com/rodmarzavala/ghlive-xbox-one-mac/blob/main/docs/clone-hero-setup.md), including the step that shows black-and-white notes: set your player profile's instrument to the 6-fret guitar.

### Changed

- The Clone Hero guide and troubleshooting now explain that black-and-white notes need the player profile's 6-fret guitar instrument.

### Known limitations

- Not yet tested on an Intel Mac or on macOS 13-15; reports are welcome in the [beta testers issue](https://github.com/rodmarzavala/ghlive-xbox-one-mac/issues/1).
- Keyboard output only: whammy and tilt act as on/off keys, not analog.
- The app is ad-hoc signed, not notarized, so the first launch needs "Open Anyway".

## [0.1.0-beta.4] - 2026-10-06

### Added

- A step-by-step [Clone Hero setup guide](docs/clone-hero-setup.md): bindings, adding songs, and 6-fret vs. 5-fret charts.
- A "Beta test report" issue form.

### Removed

- The 5-fret to 6-fret chart converter ("Add 6-fret tracks to songs..." and `ghlive charts add-ghl`), to keep GHLive focused on the guitar for 1.0. It remains available in 0.1.0-beta.3 and may return as a separate project.

## [0.1.0-beta.3] - 2026-10-05

### Added

- "Add 6-fret tracks to songs..." in the menu and `ghlive charts add-ghl <folder> [--dry-run]`: adds a 6-fret (GHL) guitar track to the 5-fret `.chart` and `.mid` songs of a Clone Hero folder, following Clone Hero's control pairing. Originals are backed up to a folder next to the songs folder first, every result is verified before it replaces the original, `diff_guitarghl` is added to `song.ini` when missing, and `.sng` songs are skipped. Charts keep their byte-order mark, a chart with duplicated sections is refused, and old-style Star Power on note 103 is converted to 116.

## [0.1.0-beta.2] - 2026-10-05

### Fixed

- The menu now shrinks when a card disappears (for example after granting Accessibility) instead of leaving blank space.

### Added

- A "5-fret (classic charts)" keymap preset next to the default 6-fret one, so the guitar can play classic five-lane charts with keys 1-5. Settings shows which preset is active (or "Custom keys"), and `ghlive keymap --print-preset five-fret|six-fret` prints either as JSON.
- "Test my guitar" in the Input Monitor: a checklist of every fret, strum direction, button, d-pad direction, the whammy bar and tilt, with the range seen for the analog ones, a progress line, "Start over", and a message when everything works.

### Changed

- On macOS 26 and later the menu, Settings and Input Monitor use Liquid Glass; older systems keep the current look.
- Settings and the Input Monitor scroll instead of growing past the screen, and keep their footer in view.

## [0.1.0-beta.1] - 2026-10-05

First public beta.

### Added

- Menu-bar app `GHLive.app` (no Dock icon), universal for Apple Silicon and Intel, macOS 13 or newer.
- Native Swift userspace driver for the Guitar Hero Live Xbox One dongle (`1430:079B`): USB configuration, GIP power-on handshake and keep-alive, with no kernel extension or SIP change.
- Keyboard output: frets, strum, Hero Power, Pause, GHTV, d-pad, whammy and tilt are sent as key presses, with release of all keys on pause, disconnect and quit.
- Settings window: click a control, then press a key (A-Z, 0-9, arrows, Space, Tab, Return, Escape, F1-F12), tilt threshold (1-255, default 150) and whammy threshold (0.05-1.0, default 0.5), automatic saving and "Restore defaults".
- Input Monitor: live frets, strum, buttons, d-pad, whammy and tilt meters with thresholds, and the keys being sent.
- Menu: status line, Pause/Resume, Settings, Input Monitor, Launch at Login, Open keymap folder, About, Quit.
- Automatic reconnection when the dongle is plugged in or unplugged, and a clear message when another app (for example Steam) holds the dongle.
- Keymap stored in `~/Library/Application Support/GHLive/keymap.json`.
- `ghlive` command-line tool: `run [--dry-run] [--verbose] [--keymap PATH]`, `sniff`, `keymap --print-default`, `--version`.
- Release artifacts `GHLive-<version>-macos-universal.zip` and `ghlive-<version>-macos-universal.tar.gz`, each with a `.sha256`, built by GitHub Actions with build provenance attestations.
- Python prototype in `tools/` (discovery, handshake, play) kept as diagnostics.

### Known limitations

- Keyboard output only, so whammy and tilt are on/off rather than analog.
- Only the Xbox One GHL dongle is supported.
- The app is ad-hoc signed and not notarized: the first launch needs "Open Anyway" (or removing the quarantine attribute), and macOS may ask for Accessibility access again after an update.
