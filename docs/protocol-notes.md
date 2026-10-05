# GHL Xbox One dongle: protocol notes

Working notes, written in our own words. Sources:

- [MS-GIPUSB](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gipusb/e7c90904-5e21-426e-b9ad-d82adeee0dbc): Microsoft's open specification of GIP over USB. Primary reference for framing and handshake.
- [PlasticBand](https://github.com/TheNathannator/PlasticBand): `Docs/Instruments/6-Fret Guitar/Xbox One.md` and `Docs/Descriptor Dumps/Xbox One/Guitar Hero Live Guitar Dongle.txt` (CC BY-SA 4.0: cited, not copied).
- [RB4InstrumentMapper](https://github.com/TheNathannator/RB4InstrumentMapper) (MIT): `Parsing/Packets/GHLGuitar/*`.
- Linux xpad (GPL-2.0+): only read to confirm the GIP interface triplet. No code taken from it.

## USB layout (confirmed on hardware, phase 1)

| Field | Value |
|---|---|
| VID:PID | `1430:079B` (Activision) |
| Device class | `0xFF/0xFF/0xFF` (vendor) |
| Configurations | 1, bus-powered, 100 mA |
| Interface 0 | class `0xFF`, subclass `0x47`, protocol `0xD0` (GIP) |
| EP `0x81` | interrupt IN, 64 B, interval 4 |
| EP `0x01` | interrupt OUT, 64 B, interval 4 |

On macOS no kernel driver matches the device, so it stays **unconfigured** (no `IOUSBHostInterface` in the registry). The host must set configuration 1 before it can open interface 0. That is why the LED stays off: nobody configures it or answers its GIP announce.

## GIP messages expected from the dongle (from the PlasticBand descriptor dump)

| ID | Direction | Length | Meaning |
|---|---|---|---|
| `0x02` | device → host | – | Arrival/announce. Host replies to start the handshake. |
| `0x20` | device → host | 14 | Gamepad-style navigation report (subset of buttons + strum as int16). |
| `0x21` | device → host | 27 | Full guitar report, PS3/Wii U GHL layout, sent at a fixed poll rate. |
| `0x22` | host → device | 8 | PS3-style output. Sub-command `0x02` is a keep-alive that **must be sent every 8 s** for input to flow. Sub-command `0x01` sets the player LEDs. |

Phase 2 will implement: set configuration → open interface 0 → read the announce → send GIP power-on (command `0x05`) per MS-GIPUSB → start the 8 s keep-alive.

## Guitar report `0x21` (to be verified in phase 3)

- Byte 0: frets: White 1, Black 1, Black 2, Black 3, White 2, White 3 (bits 0–5).
- Byte 1: Hero Power (bit 0), Pause (bit 1), GHTV (bit 2).
- Byte 2: d-pad as a hat value (0 = up, clockwise to 7, 15 = centered).
- Byte 4: strum bar: `0x80` idle, `0x00` up, `0xFF` down.
- Byte 6: whammy, `0x80` released → `0xFF` fully pressed.
- Bytes 19–20: tilt (little-endian, effectively 8-bit).
