# Contributing

Thanks for helping. Bug reports with a packet log are as valuable as code.

## Dev setup

You need Xcode or the Command Line Tools (`xcode-select --install`) and Swift 6.

```sh
make build     # swift build
make test      # swift test (adds the Swift Testing plugin path on Command Line Tools-only Macs)
make lint      # swift format lint --strict -r Sources Tests Package.swift
make app       # build GHLive.app and the CLI into dist/, like CI
```

Try the app without posting keys: `GHLIVE_DRY_RUN=1 swift run GHLiveApp`, or `swift run ghlive run --dry-run --verbose`.

Module layout: [docs/architecture.md](docs/architecture.md). Protocol facts: [docs/protocol-notes.md](docs/protocol-notes.md).

### Python tools

`tools/` is the reverse-engineering prototype. If you touch it, see [tools/README.md](tools/README.md) for setup, then from `tools/`:

```sh
.venv/bin/ruff check .
.venv/bin/ruff format --check .
.venv/bin/python -m unittest discover -s tests -t .
```

## Branching

- `main`: released code.
- `develop`: integration branch. Open pull requests against it.
- `feature/<short-kebab-name>` and `fix/<short-kebab-name>`: one branch per change, created from an up-to-date `develop`.

Keep one concern per branch and per pull request.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/), English, imperative: `feat(keymap): add F13 to F15`, `fix(driver): release keys on read failure`, `docs: clarify the Accessibility step`.

## Tests first

Every feature or bug fix ships with tests. Write the failing test first, make it pass with the smallest change, then refactor. Never delete or weaken an existing test to get green. Protocol and input code is pure and easy to unit test; keep I/O behind the existing protocols.

## Pull request checklist

- [ ] Branch is up to date with `develop`.
- [ ] A test fails without the change and passes with it.
- [ ] `make lint` and `make test` pass (and the Python gates, if `tools/` changed).
- [ ] User-visible change: `CHANGELOG.md` updated under `Unreleased`.
- [ ] No personal data, device serial numbers or secrets in code, tests, docs or logs.

## Capturing a packet log

For hardware bugs (the guitar does not sync, a control is wrong), a packet log helps a lot.

1. Quit Steam and anything else that may hold the dongle. Quit GHLive too, so only one program talks to the dongle.
2. Plug in the dongle and run `ghlive sniff` (from the release tarball, or `swift run ghlive sniff`).
3. Turn on the guitar, press the control that misbehaves, then stop with Ctrl-C.
4. Paste the output into the issue (use a code block or attach a file).

Each line is `rx` or `tx`, the packet name and the raw bytes.

**Before sharing, remove serial numbers.** Packets may include the device's serial number (not verified which ones), so check the whole output. Replace those bytes (and any serial printed elsewhere in the output) with `XX`. `ghlive sniff` only watches the wire and presses no keys.

## Releasing (maintainers)

1. Bump `VERSION` and `GHLiveInfo.version` (`Sources/GHLiveCore/GHLiveInfo.swift`) together; `scripts/build-app.sh` fails if they disagree.
2. Add a `## [<version>] - <date>` section to `CHANGELOG.md`. `scripts/release-notes.sh <version>` turns it into the release notes.
3. Tag `v<version>` and push the tag. The Release workflow tests, builds, attests and publishes. A hyphenated version (for example `0.1.0-beta.1`) is published as a prerelease.

## Security

Do not open public issues for vulnerabilities; see [SECURITY.md](SECURITY.md).
