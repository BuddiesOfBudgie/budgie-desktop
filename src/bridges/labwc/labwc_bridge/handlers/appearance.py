# This file is part of budgie-desktop
#
# Copyright Budgie Desktop Developers
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

import logging

from gi.repository import Gio

from ..config import LabwcConfig
from ..settings import Settings

log = logging.getLogger(__name__)

# gsettings key -> the rc.xml element whose text it sets
THEME_ELEMENTS = {
    "gtk-theme": "./theme/name",
    "icon-theme": "./theme/icon",
}

# notification-position -> MoveToEdge directions, vertical then horizontal
NOTIFICATION_DIRECTIONS = {
    "BUDGIE_NOTIFICATION_POSITION_TOP_LEFT": ("up", "left"),
    "BUDGIE_NOTIFICATION_POSITION_TOP_RIGHT": ("up", "right"),
    "BUDGIE_NOTIFICATION_POSITION_BOTTOM_LEFT": ("down", "left"),
    "BUDGIE_NOTIFICATION_POSITION_BOTTOM_RIGHT": ("down", "right"),
}

NOTIFICATION_ACTIONS = "./windowRules/windowRule/[@identifier='budgie-daemon'][@title='BudgieNotification']/action"


class Appearance:
    """Tracks GTK theming and panel settings into rc.xml."""

    def __init__(self, config: LabwcConfig, settings: Settings) -> None:
        self.config = config
        self.settings = settings

    def interface_changed(self, settings: Gio.Settings, key: str) -> None:
        """Mirrors the GTK and icon theme names into rc.xml's theme section."""
        path = THEME_ELEMENTS.get(key)
        if path is None:
            return

        # The shipped rc.xml has both theme elements; a user who removed one opted out
        element = self.config.root.find(path)
        if element is None:
            return

        element.text = settings[key]

        self.config.write()

    def panel_changed(self, settings: Gio.Settings, key: str) -> None:
        """Points the notification window rule at the corner the panel setting names."""
        if key != "notification-position":
            return

        position = self.settings.panel["notification-position"]
        directions = NOTIFICATION_DIRECTIONS.get(position)
        if directions is None:
            log.warning("Unknown notification position %s", position)
            return

        # The rule's first MoveToEdge moves the notification vertically, the second horizontally
        moves = [
            action
            for action in self.config.root.findall(NOTIFICATION_ACTIONS)
            if action.attrib.get("name") == "MoveToEdge"
        ]
        for action, direction in zip(moves, directions):
            action.attrib["direction"] = direction

        self.config.write()

    def sync_all(self) -> None:
        """Replays the theme and panel keys the bridge follows."""
        self.interface_changed(self.settings.interface, "gtk-theme")
        self.interface_changed(self.settings.interface, "icon-theme")
        self.panel_changed(self.settings.panel, "notification-position")
