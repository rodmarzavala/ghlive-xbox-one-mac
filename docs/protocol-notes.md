# GHL Xbox One dongle: protocol notes

Working notes, written in our own words. Sources:

- [MS-GIPUSB](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gipusb/e7c90904-5e21-426e-b9ad-d82adeee0dbc): Microsoft's open specification of GIP over USB. Primary reference for framing and handshake.
- [PlasticBand](https://github.com/TheNathannator/PlasticBand): `Docs/Instruments/6-Fret Guitar/Xbox One.md` and `Docs/Descriptor Dumps/Xbox One/Guitar Hero Live Guitar Dongle.txt` (CC BY-SA 4.0: cited, not copied).
- [RB4InstrumentMapper](https://github.com/TheNathannator/RB4InstrumentMapper) (MIT): `Parsing/Packets/GHLGuitar/*`.
- Linux xpad (GPL-2.0+): consulted for facts only (GIP interface triplet, LED and auth-done payloads, start order, keep-alive bytes). No code taken from it.

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

## Handshake (phase 2, implemented in `tools/handshake.py`, confirmed on hardware)

1. Set configuration 1 and claim interface 0.
2. Send POWER (`0x05`, payload `00`), LED (`0x0A`, payload `00 01 14`) and AUTHENTICATE (`0x06`, payload `01 00`), sequences 1-3, then the GHL keep-alive (`0x22`, sequence 0). The host does not wait for an announce.
3. Resend the keep-alive every 8 s. Acknowledge any packet with the acknowledge-required flag, keeping its sequence and client id.

Observed: the dongle answers with STATUS (flags `0x20`, payload `83`) and an ACKNOWLEDGE of the LED packet. The dongle LED turns on and the guitar syncs. No ANNOUNCE was seen.

The guitar then streams `0x21` (27 bytes, about every 12 ms). Idle payload:
`00 00 0f 80 80 80 80 00 00 00 00 00 00 00 00 00 00 00 00 70 00 80 01 00 02 00 02`.
Byte 19 (tilt) jitters by about +-3 at rest. This matches PlasticBand's layout.

STATUS (`0x03`, payload `83`) arrives about every 20 s. A single USB IN transfer may bundle several GIP messages back to back (seen: STATUS followed by a `0x21` report), so a transfer must be decoded message by message.

Chunked GIP packets (flag `0x80`) are not supported: they are logged and not acknowledged.

## Guitar report `0x21` (confirmed on hardware)

- Byte 0: frets: White 1 `0x01`, Black 1 `0x02`, Black 2 `0x04`, Black 3 `0x08`, White 2 `0x10`, White 3 `0x20`.
- Byte 1: Hero Power `0x01`, Pause `0x02`, GHTV `0x04`.
- Byte 2: d-pad as a hat value (0 = up, clockwise to 7, 15 = centered; odd values are diagonals).
- Byte 4: strum bar: `0x80` idle, `0x00` up, `0xFF` down.
- Byte 6: whammy, `0x80` released → `0xFF` fully pressed, smooth analog.
- Byte 19: tilt, analog: about 110 at rest (+-3 jitter), 171 and 67 at the extremes. The "tilt extreme" flags documented by PlasticBand (byte 5, bytes 21–22) never triggered on this guitar, so tilt is derived from byte 19 with a threshold.
