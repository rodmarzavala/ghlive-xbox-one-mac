import unittest
from unittest import mock

from ghlproto import quartz_keyboard
from ghlproto.quartz_keyboard import QuartzKeyEmitter, accessibility_trusted

KEYCODE = 0x31
FAKE_EVENT = object()


class QuartzKeyEmitterTest(unittest.TestCase):
    def emit(self, method: str) -> tuple[mock.Mock, mock.Mock]:
        with (
            mock.patch.object(quartz_keyboard, "CGEventCreateKeyboardEvent", return_value=FAKE_EVENT) as create,
            mock.patch.object(quartz_keyboard, "CGEventPost") as post,
        ):
            getattr(QuartzKeyEmitter(), method)(KEYCODE)
        return create, post

    def test_key_down_posts_a_key_down_event_to_the_hid_tap(self):
        create, post = self.emit("key_down")
        create.assert_called_once_with(None, KEYCODE, True)
        post.assert_called_once_with(quartz_keyboard.kCGHIDEventTap, FAKE_EVENT)

    def test_key_up_posts_a_key_up_event_to_the_hid_tap(self):
        create, post = self.emit("key_up")
        create.assert_called_once_with(None, KEYCODE, False)
        post.assert_called_once_with(quartz_keyboard.kCGHIDEventTap, FAKE_EVENT)


class AccessibilityTrustedTest(unittest.TestCase):
    def test_reflects_ax_is_process_trusted(self):
        for trusted in (True, False):
            with (
                self.subTest(trusted=trusted),
                mock.patch.object(quartz_keyboard, "AXIsProcessTrusted", return_value=trusted),
            ):
                self.assertIs(accessibility_trusted(), trusted)


if __name__ == "__main__":
    unittest.main()
