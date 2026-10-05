# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
