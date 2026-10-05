# Security policy

## Supported versions

Only the latest release receives fixes.

## Reporting a vulnerability

Please do not open a public issue. Use GitHub's private reporting instead: go to the repository's **Security** tab and click **Report a vulnerability**
([direct link](https://github.com/rodmarzavala/ghlive-xbox-one-mac/security/advisories/new)).

Include what you found, how to reproduce it, and the app version and macOS version. You can expect an acknowledgement within a few days; this is a volunteer project, so there is no guaranteed timeline.

## Scope

GHLive runs in user space, talks to one USB device and posts keyboard events. It has no network code and collects no data. Reports about the dongle protocol handling, the keymap file parser, the build and release pipeline, or the integrity of the release artifacts are all in scope.

Users can check a download with the published checksums and build attestations; see [Verify your download](README.md#verify-your-download).
