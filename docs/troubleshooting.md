# Troubleshooting

Start with the status line at the top of the GHLive menu. It tells you where in the chain things stopped.

| Status line | Meaning |
|---|---|
| Waiting for the dongle | No dongle seen. "Plug in the Xbox One wireless adapter." |
| Connecting to the dongle | "This takes a few seconds." |
| Dongle ready, turn on your guitar | The dongle is up; switch the guitar on. "If it doesn't connect, turn the guitar off and on again." |
| Guitar connected | Everything works. |
| Paused | No keys are sent until you resume. |
| The dongle is in use by another app | See [the dongle is busy](#the-dongle-is-busy). |
| Any other error message | GHLive retries every few seconds. |

The **Input Monitor...** window shows what the app sees, which separates "the guitar is not read" from "the game does not get the keys".

## The dongle LED does not turn on

- Check the status line. "Waiting for the dongle" means macOS does not see the device: try another USB port or cable, then replug.
- If the status is an error about another program having the dongle, see [the dongle is busy](#the-dongle-is-busy).
- Make sure it is the **Xbox One** dongle (`1430:079B`). Other dongles are not supported.
- Still stuck? Collect a [packet log](../CONTRIBUTING.md#capturing-a-packet-log) and open an issue.

## The guitar does not sync

- Switch the guitar on once the status reads "Dongle ready, turn on your guitar".
- Turn the guitar off and on again; GHLive reconnects on its own.
- If the dongle is ready but the status never reaches "Guitar connected", capture a packet log.

## The dongle is busy

The status line reads "The dongle is in use by another app", with the hint "Quit Steam or any other app that reads Xbox controllers. GHLive retries every few seconds."

Steam is a likely cause, but other apps can hold the dongle too. Quit them. GHLive retries every few seconds, so it connects as soon as the dongle is free.

With the `ghlive` command, the same condition is printed to stderr as `error: <message> (retrying)`, even without `--verbose`.

## Keys do not reach the game

1. **Accessibility.** While it is missing, the menu shows the card "Allow GHLive to press keys" with a **Grant Accessibility access...** button. Click it and enable GHLive.
2. **Game focus.** Key presses go to the app in front. Keep the game window active.
3. **Bindings.** Open the Input Monitor and press frets: it lists the keys being sent. Make sure the game has those same keys bound.
4. **Paused.** The status says "Paused". Choose Resume.
5. **Keymap.** Check `~/Library/Application Support/GHLive/keymap.json` (menu: Open keymap folder). Settings -> Restore defaults resets it.

## A control fails the guitar test

Open the Input Monitor and click **Test my guitar** (see [Check that your guitar works](../README.md#check-that-your-guitar-works)). A control that never gets its green check is not being read by GHLive:

- **A fret, strum direction, button or d-pad direction.** Press it again while watching the picture above the checklist. If it does not light up there, the guitar is not sending it; try fresh batteries and re-sync the guitar. If it lights up but is not checked, tell us in an issue.
- **Whammy bar.** It needs a full press and a release. If the range stays small, check the whammy bar on the guitar itself.
- **Tilt.** Raise the neck past the Tilt threshold, then lower it below the release level (10 under the threshold by default). If it never gets there, lower the threshold in Settings, see [Tilt triggers constantly, or never](#tilt-triggers-constantly-or-never).

## It stopped working after an update

The app is ad-hoc signed, so macOS may drop its Accessibility permission when it is updated. Open System Settings -> Privacy & Security -> Accessibility, select GHLive, remove it with the minus button, then add it again (or click "Grant Accessibility access..." in the menu). Then quit and reopen GHLive.

## Tilt triggers constantly, or never

The guitar rests around 95 to 115 on the tilt scale. Open the Input Monitor, raise and lower the neck, and set the Tilt threshold in Settings between the resting value and the raised value. See [Calibrating tilt and whammy](../README.md#calibrating-tilt-and-whammy).

## macOS will not open the app

See [Install](install.md#allowing-the-app): use **Open Anyway** in Privacy & Security, or run `xattr -dr com.apple.quarantine /Applications/GHLive.app`.

## Intel Macs

The app and CLI are universal (arm64 and x86_64), but they have not been tested on an Intel Mac. If something fails there, open an issue with your macOS version and a packet log.

## I only see colored notes, not black and white

Your guitar's black-and-white notes only appear when your Clone Hero **player profile uses the 6-fret guitar instrument**, in songs that include a 6-fret (GHL) chart. Most community charts are 5-fret only and show colored notes; they still play with the default bindings. If a song should have a 6-fret chart but the instrument isn't offered, rescan your songs and check that the chart has a 6-fret part (an `[ExpertGHLGuitar]` section in `notes.chart`, or a `PART GUITAR GHL` track in `notes.mid`). See [Setting up Clone Hero](clone-hero-setup.md#4-6-fret-charts-vs-5-fret-charts).

## Still stuck

Open a [bug report](https://github.com/rodmarzavala/ghlive-xbox-one-mac/issues/new/choose). Include your macOS version, chip, app version and, if you can, `ghlive sniff` output (see [CONTRIBUTING](../CONTRIBUTING.md#capturing-a-packet-log)).
