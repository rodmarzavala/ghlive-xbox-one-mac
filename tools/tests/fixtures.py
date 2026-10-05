from ghlproto.guitar_state import GuitarState, parse_guitar_report

# Idle capture documented in docs/protocol-notes.md (tilt byte 19 = 0x70)
IDLE_PAYLOAD = bytes.fromhex("00000f808080800000000000000000000000007000800100020002")
IDLE_TILT = 0x70

IDLE: GuitarState = parse_guitar_report(IDLE_PAYLOAD)


def payload_with(**changes: int) -> bytes:
    """Idle payload with byte overrides given as b<offset>=value."""
    data = bytearray(IDLE_PAYLOAD)
    for name, value in changes.items():
        data[int(name[1:])] = value
    return bytes(data)


class FakeEmitter:
    def __init__(self) -> None:
        self.events: list[tuple[str, int]] = []

    def key_down(self, keycode: int) -> None:
        self.events.append(("down", keycode))

    def key_up(self, keycode: int) -> None:
        self.events.append(("up", keycode))


class RecordingSink:
    def __init__(self) -> None:
        self.states: list[GuitarState] = []
        self.released = 0

    def apply(self, state: GuitarState) -> None:
        self.states.append(state)

    def release_all(self) -> None:
        self.released += 1
