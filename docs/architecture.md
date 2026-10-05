# Architecture (Swift)

The Swift package splits into targets with one responsibility each. Dependencies point downwards only.

```
ghlive (CLI)        GHLiveApp (menu bar, separate)
        \            /
          GHLiveCore            GuitarDriver: the orchestrator
   /     |       |        \
GIPProtocol  GuitarInput  KeyMapping -> GuitarInput
                 KeyboardOutput -> GuitarInput, KeyMapping
USBTransport (no dependencies on the others)
```

| Target | Responsibility |
|---|---|
| `GIPProtocol` | GIP framing (varint length), `decodePackets` for bundled transfers, packet builders, `SequenceCounter`, `GipSession` (handshake packets, ACKs, 8 s keep-alive). Pure, no I/O. |
| `GuitarInput` | `parseGuitarReport` (0x21 layout), `GuitarState`, `Control`, `Thresholds`, `HysteresisDetector`, `ControlDetector`. Pure. |
| `KeyMapping` | `Keymap` (control to key, thresholds; JSON, validated), `KeyCode` table (Carbon `kVK_*`), `KeymapStore` (`~/Library/Application Support/GHLive/keymap.json`). |
| `KeyboardOutput` | `OutputSink` and `KeyEmitter` protocols, `KeyboardSink` (key diffs, shared keys, `releaseAll`), `CGEventKeyEmitter`, `DryRunKeyEmitter`, `AccessibilityPermission`. |
| `USBTransport` | `PacketTransport`, `DongleConnecting`, `DongleEventSource` protocols; IOUSBHost `DongleConnection`; IOKit `DongleMonitor`. The only target that touches IOKit. |
| `GHLiveCore` | `GuitarDriver`: monitor, connection, session, parser, detector, sink. Observable status and live input for UIs. |

## Data flow

```
DongleMonitor --arrived/removed--> GuitarDriver
GuitarDriver --connect--> DongleConnection (IOUSBHost, configuration 1, GIP interface, pipes 0x01/0x81)
GipSession.startPackets ---> write            (power on, LED, auth done)
read stream --Data--> decodePackets --GipPacket--> GipSession.handle --ACKs--> write
                                            \--0x21--> parseGuitarReport --GuitarState-->
ControlDetector --Set<Control>--> OutputSink.apply(state:controls:) --> KeyboardSink --> CGEvent
GipSession.duePackets(now:) every tick --> keep-alive write
```

## Threading

- `GuitarDriver` is `@MainActor` and an `ObservableObject`. All of its state, the sink and the emitters live on the main actor, so SwiftUI can observe `status`, `snapshot` and `isPaused` directly (`ObservableObject` rather than `@Observable`, which needs macOS 14 while the package targets macOS 13).
- IOKit callbacks (read completions, device notifications) run on private dispatch queues and only `yield` into `AsyncStream`s. The driver consumes those streams on the main actor, so no locks are needed in the logic.
- Reads are asynchronous (`enqueueIORequest`), so teardown can abort them and nothing blocks forever. Interrupt pipes require `completionTimeout: 0`.
- Per connection the driver runs a reader task and a tick task (keep-alive and guitar-silence check). Cancelling the driver task tears both down, closes the dongle and releases all keys.

## Safety guarantees

`OutputSink.releaseAll()` runs on stop, on disconnect or read failure, on pause, and when the guitar has been silent for more than one second. `KeyboardSink` marks a key as pressed before posting its key down and forgets it only after its key up, so a release arriving in between still lifts the key.

## Status

`waitingForDongle`, `connecting`, `dongleReady` (handshake sent, no guitar report yet or guitar silent), `guitarActive` (report less than 1 s old), `error(message)`. After an error the driver retries every 2 s while the dongle is plugged in, which also covers "quit Steam, then it works".

## Adding a gamepad sink later

Keyboard output cannot carry analog values: whammy and tilt are reduced to on/off by the thresholds. A virtual gamepad (DriverKit HID) can keep them.

1. Implement `OutputSink` in a new target. `apply(state:controls:)` receives the full `GuitarState` (whammy 0...1, raw tilt byte, d-pad) as well as the digitised controls.
2. `releaseAll()` must leave every button and axis neutral.
3. Hand it to `GuitarDriver(monitor:connector:sink:thresholds:)`, or swap it at runtime with `reconfigure(sink:thresholds:)`. Nothing in `GIPProtocol`, `USBTransport` or the driver changes.
