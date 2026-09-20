# This file is part of budgie-desktop
#
# Copyright Budgie Desktop Developers
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

import time
import xml.etree.ElementTree as Et
from enum import StrEnum

import gi
from gi.repository import Gio

gi.require_version("Pango", "1.0")
from gi.repository import Pango

from ..config import LabwcConfig
from ..settings import Settings


class WindowManager:
    """Tracks budgie-wm, mutter and wm-preferences settings into rc.xml."""

    def __init__(self, config: LabwcConfig, settings: Settings) -> None:
        self.config = config
        self.settings = settings

    def budgie_wm_changed(self, settings: Gio.Settings, key: str) -> None:
        """Mirrors budgie-wm's focus mode, window switcher scope and edge tiling into rc.xml."""
        root = self.config.root

        # Only a key that reached an element earns a write
        updated = False

        if key == "window-focus-mode" and self._apply_focus_mode():
            updated = True

        if key == "show-all-windows-tabswitcher":
            path = "./windowSwitcher"
            bridge = root.find(path)

            # The shipped rc.xml has this element; a user who removed it opted out, same for the ones below
            if bridge is None:
                return

            bridge.attrib["allWorkspaces"] = self.config.yes_no(settings[key])

            updated = True

        if key == "edge-tiling":
            path = "./snapping/range"
            bridge = root.find(path)

            if bridge is None:
                return

            # labwc's snapping range is a distance in pixels; 0 turns it off
            bridge.text = "10" if settings[key] else "0"

            updated = True

        if updated:
            self.config.write()

    def mutter_changed(self, settings: Gio.Settings, key: str) -> None:
        """Mirrors mutter's center-new-windows into rc.xml's placement policy."""
        if key != "center-new-windows":
            return

        root = self.config.root

        path = "./placement/policy"
        bridge = root.find(path)

        if bridge is None:
            return

        # labwc's own placement heuristic is what it calls automatic
        bridge.text = "center" if settings[key] else "automatic"

        self.config.write()

    def wm_preferences_changed(self, settings: Gio.Settings, key: str) -> None:
        """Mirrors the titlebar font and button layout, workspace count and raise delay into rc.xml."""
        root = self.config.root

        updated = False
        if key == "titlebar-font":
            # labwc knows two weights and two slants, so Pango's finer scale is thresholded
            pango = Pango.FontDescription.from_string(settings[key])
            family = pango.get_family()
            weight = "Normal" if pango.get_weight() <= Pango.Weight.NORMAL else "Bold"
            slant = "Normal" if pango.get_style() == Pango.Style.NORMAL else "Italic"

            # Both the active and the inactive window font follow the one setting
            for bridge in root.findall("./theme/font"):
                updated = True
                # a font string carrying no family, say "Bold 11", parses to
                # None, which ElementTree refuses to serialize
                if family is not None:
                    bridge.attrib["name"] = family
                bridge.attrib["weight"] = weight
                bridge.attrib["slant"] = slant
                bridge.attrib["size"] = str(int(pango.get_size() / Pango.SCALE))

            if not updated:
                return

        if key == "button-layout":
            path = "./theme/titlebar/layout"
            bridge = root.find(path)

            if bridge is None:
                return

            # GNOME's layout string is free-form; labwc gets one of two fixed layouts, by the side close sits on
            bridge.text = (
                "close,iconify,max:"
                if settings[key].startswith("close")
                else ":iconify,max,close:"
            )

            updated = True

        if key == "num-workspaces":
            path = "./desktops"
            bridge = root.find(path)

            if bridge is None:
                return

            # labwc calls workspaces desktops
            bridge.attrib["number"] = str(settings[key])

            updated = True

        if key == "auto-raise-delay" and self._apply_focus_mode():
            updated = True

        if updated:
            time.sleep(0.5)
            self.config.write()

    def _apply_focus_mode(self) -> bool:
        """
        Maps the single budgie-wm window-focus-mode setting onto labwc's three
        separate focus elements. Shared by the focus-mode and auto-raise-delay
        handlers, since both have to rewrite the same section.
        """
        root = self.config.root

        focus = root.find("./focus")

        if focus is None:
            return False

        bridge = focus.find("followMouse")

        if bridge is None:
            return False

        class Mode(StrEnum):
            CLICK = "click"
            SLOPPY = "sloppy"
            MOUSE = "mouse"

        focus_mode = self.settings.budgie_wm["window-focus-mode"]

        # sloppy and mouse both focus under the pointer; only mouse also raises the window
        bridge.text = self.config.yes_no(focus_mode != Mode.CLICK)

        bridgeraise = focus.find("raiseOnFocus")

        if bridgeraise is None:
            return False

        bridgeraise.text = self.config.yes_no(focus_mode == Mode.MOUSE)

        auto_raise_delay = self.settings.wm_preferences["auto-raise-delay"]

        # Not in the shipped rc.xml, so it is created the first time round
        bridgeraisedelay = focus.find("raiseOnFocusDelay")

        if bridgeraisedelay is None:
            bridgeraisedelay = Et.SubElement(focus, "raiseOnFocusDelay")

        bridgeraisedelay.text = str(auto_raise_delay)

        return True

    def sync_all(self) -> None:
        """Replays the window-manager keys the bridge follows."""
        budgie_wm_keys = {
            "window-focus-mode",
            "show-all-windows-tabswitcher",
            "edge-tiling",
        }
        for key in budgie_wm_keys:
            self.budgie_wm_changed(self.settings.budgie_wm, key)

        self.mutter_changed(self.settings.mutter, "center-new-windows")
        self.wm_preferences_changed(self.settings.wm_preferences, "titlebar-font")
        self.wm_preferences_changed(self.settings.wm_preferences, "button-layout")
        self.wm_preferences_changed(self.settings.wm_preferences, "num-workspaces")
        self.wm_preferences_changed(self.settings.wm_preferences, "auto-raise-delay")
