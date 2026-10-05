# Install, in detail

The short version is in the [README](../README.md#install). This page covers what to expect and why.

## Why macOS blocks the first launch

GHLive is ad-hoc signed but **not notarized**: notarization needs a paid Apple Developer account, which this free project does not have. Gatekeeper therefore refuses to open the app until you explicitly allow it. You only do this once per download.

## Allowing the app

Pick one.

**System Settings.** Open the app once and dismiss the warning. Then go to System Settings -> Privacy & Security, scroll to the message about GHLive, click **Open Anyway** and confirm. Right-click -> Open no longer works on recent macOS versions.

**Terminal.** Remove the quarantine flag, then open the app:

```sh
xattr -dr com.apple.quarantine /Applications/GHLive.app
```

## Accessibility

GHLive needs Accessibility access to post key presses. Until it is granted, the menu shows a card, "Allow GHLive to press keys", with a **Grant Accessibility access...** button. Click it: macOS prompts and System Settings opens; switch GHLive on.

GHLive only posts keyboard events. It has no network access and collects no data.

Because the app is ad-hoc signed, macOS may ask again after an update. If keys stop arriving, select GHLive in the Accessibility list, remove it with the minus button, and add it again.

## Launch at Login

Turn on **Launch at Login** in the menu. macOS may need you to approve it: the menu then shows "Approve GHLive in System Settings > Login Items" with an **Open Login Items...** button. Click it and switch GHLive on in the list.

## Checking the download

See [Verify your download](../README.md#verify-your-download).

## Uninstall

Quit GHLive, delete `GHLive.app`, and optionally delete `~/Library/Application Support/GHLive/` (your keymap). Remove GHLive from the Accessibility list in System Settings.
