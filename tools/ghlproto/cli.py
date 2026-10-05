EXIT_OK = 0
EXIT_DEVICE_ERROR = 1
QUIT_OTHER_APPS_HINT = "Quit apps that may hold the dongle open (Steam, Plex, browser tabs using WebUSB) and retry."


def not_plugged_in_message(detail: str) -> str:
    return f"{detail}. Is the dongle plugged in?"
