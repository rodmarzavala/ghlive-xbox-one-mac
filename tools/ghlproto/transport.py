from typing import Protocol


class PacketTransport(Protocol):
    def write(self, data: bytes) -> None: ...

    def read(self, timeout_ms: int) -> bytes | None:
        """Returns None when nothing arrived within the timeout."""
