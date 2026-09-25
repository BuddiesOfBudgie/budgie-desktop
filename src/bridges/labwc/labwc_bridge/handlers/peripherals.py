# This file is part of budgie-desktop
#
# Copyright Budgie Desktop Developers
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

# The bridge has to survive a single config operation failing rather than take
# the session's keybinds and theming down with it, so the broad excepts are
# deliberate.
# ruff: noqa: BLE001

import logging
import xml.etree.ElementTree as Et
from collections.abc import Callable
from typing import Any

from gi.repository import Gio

from ..config import LabwcConfig
from ..settings import Settings

log = logging.getLogger(__name__)


def _text(value: object) -> str:
    """A number or string as labwc reads it, unchanged."""
    return str(value)


def _accel_profile(value: str) -> str:
    """GNOME's accel-profile as labwc's accelProfile."""
    # GNOME's "default" leaves the choice to libinput; labwc has no such value
    return "adaptive" if value == "adaptive" else "flat"


def _click_method(value: str) -> str:
    """GNOME's click-method as labwc's clickMethod."""
    # GNOME's "default" and "fingers" both come out as labwc's clickfinger
    return {"none": "none", "areas": "buttonAreas"}.get(value, "clickfinger")


def _send_events(value: str) -> str:
    """GNOME's send-events as labwc's sendEventsMode."""
    # The only GNOME value that is neither on nor off is "disabled-on-external-mouse"
    return {"enabled": "yes", "disabled": "no"}.get(value, "disabledOnExternalMouse")


# gsettings key -> the libinput element it sets, and how its value reads as that element's text
DEVICE_SETTINGS_BY_KEY: dict[str, tuple[str, Callable[[Any], str]]] = {
    "natural-scroll": ("naturalScroll", LabwcConfig.yes_no),
    "tap-to-click": ("tap", LabwcConfig.yes_no),
    "tap-and-drag": ("tapAndDrag", LabwcConfig.yes_no),
    "tap-and-drag-lock": ("dragLock", LabwcConfig.yes_no),
    "middle-click-emulation": ("middleEmulation", LabwcConfig.yes_no),
    "disable-while-typing": ("disableWhileTyping", LabwcConfig.yes_no),
    "speed": ("pointerSpeed", _text),
    "accel-profile": ("accelProfile", _accel_profile),
    "tap-button-map": ("tapButtonMap", _text),
    "click-method": ("clickMethod", _click_method),
    "send-events": ("sendEventsMode", _send_events),
}

# The touchpad's left-handed key is an enum; anything else means 'mouse', follow the mouse
TOUCHPAD_HANDEDNESS = {"left": "yes", "right": "no"}

# The keys of each schema the bridge follows; they differ because labwc's touchpad and mouse devices take different settings
TOUCHPAD_KEYS = (
    "natural-scroll",
    "left-handed",
    "accel-profile",
    "tap-to-click",
    "tap-and-drag",
    "tap-and-drag-lock",
    "middle-click-emulation",
    "disable-while-typing",
    "speed",
    "tap-button-map",
    "click-method",
    "send-events",
)

MOUSE_KEYS = (
    "natural-scroll",
    "left-handed",
    "speed",
    "accel-profile",
    "middle-click-emulation",
    "double-click",
)


class Peripherals:
    """Tracks libinput mouse and touchpad settings into rc.xml."""

    def __init__(self, config: LabwcConfig, settings: Settings) -> None:
        self.config = config
        self.settings = settings

    def changed(self, settings: Gio.Settings, key: str) -> None:
        """Mirrors one mouse or touchpad key into the matching libinput setting."""
        # The mouse and touchpad schemas share this handler; rc.xml keeps a device per category
        category = "touchpad" if "touchpad" in settings.props.schema else "non-touch"

        # Two keys do not map onto one element of the device that changed
        if key == "left-handed":
            self._left_handed_changed(settings, category)
        elif key == "double-click":
            self._double_click_changed(settings)
        else:
            # Keys outside the table are ones labwc has no setting for
            entry = DEVICE_SETTINGS_BY_KEY.get(key)
            if entry is None:
                return
            element_name, convert = entry
            self._find_or_create_device_setting(category, element_name).text = convert(
                settings[key]
            )

        self.config.write()

    def _left_handed_changed(self, settings: Gio.Settings, category: str) -> None:
        """Handedness for the device that changed, and for a touchpad that follows the mouse."""
        if category == "touchpad":
            value = TOUCHPAD_HANDEDNESS.get(settings["left-handed"])
            # "mouse": the touchpad has no handedness of its own and takes the mouse's
            if value is None:
                value = LabwcConfig.yes_no(
                    self.settings.mouse.get_boolean("left-handed")
                )
        else:
            # The mouse's key is a plain boolean
            value = LabwcConfig.yes_no(settings["left-handed"])
            # A touchpad set to follow the mouse changes along with it
            if self.settings.touchpad.get_string("left-handed") == "mouse":
                self._find_or_create_device_setting(
                    "touchpad", "leftHanded"
                ).text = value

        self._find_or_create_device_setting(category, "leftHanded").text = value

    def _double_click_changed(self, settings: Gio.Settings) -> None:
        """Double-click time, which labwc keeps under <mouse> rather than per device."""
        # Double-click time is not a per-device setting in labwc
        element = self.config.root.find("./mouse/doubleClickTime")
        if element is None:
            log.info(
                "cannot find ./mouse/doubleClickTime to set the value "
                + str(settings["double-click"])
            )
            return

        element.text = str(settings["double-click"])

    def scroll_method_changed(self, settings: Gio.Settings, key: str) -> None:
        """Mirrors GNOME's two scrolling booleans into the touchpad's single scrollMethod."""
        if key not in ["two-finger-scrolling-enabled", "edge-scrolling-enabled"]:
            return

        # Whichever key changed, the method is recomputed from both
        two_finger = settings.get_boolean("two-finger-scrolling-enabled")
        edge_scroll = settings.get_boolean("edge-scrolling-enabled")

        # Both can be enabled at once; two-finger takes precedence
        scroll_method = self._find_or_create_device_setting("touchpad", "scrollMethod")
        scroll_method.text = (
            "twofinger" if two_finger else ("edge" if edge_scroll else "none")
        )

        self.config.write()

    def _find_or_create_device_setting(self, category: str, setting: str) -> Et.Element:
        """The setting's element under libinput/device[@category], created with its parents when absent."""
        root = self.config.root

        # A user's rc.xml may lack the section, the device, or the setting; each is created on demand
        libinput = root.find("./libinput")
        if libinput is None:
            libinput = Et.SubElement(root, "libinput")

        # labwc keeps one <device> per category, so a touchpad and a mouse setting of the same name do not collide
        device = libinput.find(f"./device[@category='{category}']")
        if device is None:
            device = Et.SubElement(libinput, "device")
            device.attrib["category"] = category

        # Created empty: labwc reads the value from the element's text, which the caller fills in
        element = device.find(f"./{setting}")
        if element is None:
            element = Et.SubElement(device, setting)

        return element

    def sync_all(self) -> None:
        """Replays every mouse and touchpad key the bridge follows."""
        for key in TOUCHPAD_KEYS:
            self.changed(self.settings.touchpad, key)

        for key in MOUSE_KEYS:
            self.changed(self.settings.mouse, key)

        # Sync scroll method settings
        try:
            self.scroll_method_changed(
                self.settings.touchpad, "two-finger-scrolling-enabled"
            )
        except Exception as e:
            log.warning(f"Could not sync scroll method: {e}")
