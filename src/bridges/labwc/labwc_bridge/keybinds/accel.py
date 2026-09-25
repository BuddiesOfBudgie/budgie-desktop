# This file is part of budgie-desktop
#
# Copyright Budgie Desktop Developers
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.


# GTK accelerator fragments -> labwc's spelling; order matters, the replacements run one after another over the whole string
SUBSTITUTIONS = {
    "<Alt>": "A-",
    "<Super>": "W-",
    "<Control>": "C-",
    "<Primary>": "C-",
    "<Ctrl>": "C-",
    "<Shift>": "S-",
    "Calculator": "XF86Calculator",
    "Battery": "XF86Battery",
    "Tools": "XF86Tools",
    "Eject": "XF86Eject",
    "Mail": "XF86Mail",
    "Suspend": "XF86Suspend",
    "Hibernate": "XF86Hibernate",
    "Explorer": "XF86Explorer",
    "KbdBrightnessDown": "XF86KbdBrightnessDown",
    "KbdLightOnOff": "XF86KbdLightOnOff",
    "KbdBrightnessUp": "XF86KbdBrightnessUp",
    "AudioMedia": "XF86AudioMedia",
    "AudioNext": "XF86AudioNext",
    "AudioMicMute": "XF86AudioMicMute",
    "AudioPause": "XF86AudioPause",
    "AudioRandomPlay": "XF86AudioRandomPlay",
    "AudioForward": "XF86AudioForward",
    "AudioRepeat": "XF86AudioRepeat",
    "AudioPlay": "XF86AudioPlay",
    "AudioRewind": "XF86AudioRewind",
    "PowerOff": "XF86PowerOff",
    "AudioPrev": "XF86AudioPrev",
    "Bluetooth": "XF86Bluetooth",
    "WLAN": "XF86WLAN",
    "UWB": "XF86UWB",
    "RFKill": "XF86RFKill",
    "RotationLockToggle": "XF86RotationLockToggle",
    "MonBrightnessCycle": "XF86MonBrightnessCycle",
    "MonBrightnessDown": "XF86MonBrightnessDown",
    "MonBrightnessUp": "XF86MonBrightnessUp",
    "Screensaver": "XF86ScreenSaver",
    "Search": "XF86Search",
    "AudioStop": "XF86AudioStop",
    "Sleep": "XF86Sleep",
    "TouchpadOff": "XF86TouchpadOff",
    "TouchpadOn": "XF86TouchpadOn",
    "TouchpadToggle": "XF86TouchpadToggle",
    "AudioLowerVolume": "XF86AudioLowerVolume",
    "AudioMute": "XF86AudioMute",
    "AudioRaiseVolume": "XF86AudioRaiseVolume",
    "WWW": "XF86WWW",
}


def calc_keybind(gkey: str) -> str:
    """Translates a GTK accelerator such as <Super><Shift>p into labwc's W-S-p."""
    # An empty accelerator is gsettings' unbound; "undefined" is no keysym, so labwc binds nothing to it
    if not gkey or gkey == "":
        replacement = "undefined"
    else:
        replacement = gkey

        for sub, value in SUBSTITUTIONS.items():
            replacement = replacement.replace(sub, value)

        # A modifier-only accelerator leaves a dangling separator
        if replacement[-1] == "-":
            replacement = replacement[:-1]

        # A key that already carried the XF86 prefix got a second one from the table
        replacement = replacement.replace("XF86XF86", "XF86")

        # Convert the final key (non-modifier) to lowercase
        if "-" in replacement:
            parts = replacement.rsplit("-", 1)
            if len(parts) == 2:
                modifiers = parts[0]
                key = parts[1]
                # Only lowercase if it's not an XF86 key or special key
                if not key.startswith("XF86") and len(key) == 1:
                    key = key.lower()
                replacement = modifiers + "-" + key
        else:
            # No modifiers, just a single key
            if len(replacement) == 1:
                replacement = replacement.lower()

    return replacement
