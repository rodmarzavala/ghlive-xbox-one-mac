# GHLive Xbox One for Mac

Use the **Guitar Hero Live guitar with its Xbox One USB dongle on macOS**, for games such as [Clone Hero](https://clonehero.net/).

macOS ships no driver for this dongle: it stays unconfigured and its LED never turns on. This project is a userspace driver that talks to the dongle directly over USB using Microsoft's Gaming Input Protocol (GIP). No kernel extensions, no SIP changes, no signed drivers.

> **Status: early development.** USB discovery works. The GIP handshake, input parsing and keyboard output are in progress. See the [roadmap](#roadmap).

## Supported hardware

| Device | VID:PID |
|---|---|
| Guitar Hero Live Xbox One wireless dongle | `1430:079B` |

Apple Silicon and Intel Macs.

Only the **Xbox One** dongle is supported. The PS3, Wii U and PS4 dongles are standard HID devices that Clone Hero reads directly, and the Xbox 360 dongle is out of scope.

## How it works

1. Find the dongle by VID/PID and set USB configuration 1 (no macOS driver does it).
2. Open the GIP interface (`0xFF/0x47/0xD0`) and run the GIP power-on handshake.
3. Send the GHL keep-alive every 8 seconds, which the dongle requires to stream input.
4. Parse the guitar report into a typed state: 6 frets, strum, Hero Power, Pause, GHTV, whammy and tilt.
5. Emit keyboard events (`CGEventPost`) that Clone Hero can bind.

Protocol details are in [docs/protocol-notes.md](docs/protocol-notes.md).

## Roadmap

- [x] **Phase 1: Discovery.** Descriptor dump and macOS IORegistry inspection.
- [x] **Phase 2: Handshake.** Configure the device, power it on over GIP, dongle LED on, guitar syncs.
- [ ] **Phase 3: Sniffer.** Raw packet dump to confirm the button mapping on real hardware.
- [ ] **Phase 4: Parser and keyboard output.** Typed guitar state and configurable key mapping.
- [ ] **Phase 5: Polish.** Stable CLI or menu bar app, automatic reconnection, full user guide.

The v1 output is keyboard only, so whammy and tilt can only be digital (on/off). The output layer sits behind an interface so a virtual gamepad (DriverKit) can be added later without touching the USB or protocol code.

## Repository layout

```
tools/   Python prototype used for reverse engineering (phases 1–3)
docs/    Protocol notes and references
```

## Building from source (Swift)

```
make build     # swift build
make test      # swift test (adds the Swift Testing flag when only Command Line Tools are installed)
make lint      # swift format lint
make release   # universal arm64 + x86_64 release build
swift run ghlive run --dry-run --verbose
```

See [docs/architecture.md](docs/architecture.md) for the module layout.

## Development

See [tools/README.md](tools/README.md) for setup, lint and tests.

## References

- [MS-GIPUSB](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gipusb/e7c90904-5e21-426e-b9ad-d82adeee0dbc), Microsoft's open specification of GIP over USB.
- [PlasticBand](https://github.com/TheNathannator/PlasticBand), community documentation of rhythm game peripherals.
- [RB4InstrumentMapper](https://github.com/TheNathannator/RB4InstrumentMapper), the Windows mapper that supports this guitar.
- [xpad](https://github.com/paroj/xpad), the Linux driver that supports this dongle. It was consulted only for protocol facts; no GPL code is used here.

## License

[MIT](LICENSE). Not affiliated with Activision or Microsoft.
