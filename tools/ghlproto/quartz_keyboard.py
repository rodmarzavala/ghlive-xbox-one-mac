from ApplicationServices import AXIsProcessTrusted
from Quartz import CGEventCreateKeyboardEvent, CGEventPost, kCGHIDEventTap

DEFAULT_EVENT_SOURCE = None


class QuartzKeyEmitter:
    def key_down(self, keycode: int) -> None:
        self._post(keycode, key_down=True)

    def key_up(self, keycode: int) -> None:
        self._post(keycode, key_down=False)

    def _post(self, keycode: int, key_down: bool) -> None:
        event = CGEventCreateKeyboardEvent(DEFAULT_EVENT_SOURCE, keycode, key_down)
        CGEventPost(kCGHIDEventTap, event)


def accessibility_trusted() -> bool:
    return bool(AXIsProcessTrusted())
