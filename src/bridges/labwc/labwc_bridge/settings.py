# This file is part of budgie-desktop
#
# Copyright Budgie Desktop Developers
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

from gi.repository import Gio


class Settings:
    """The gsettings schemas the bridge follows."""

    def __init__(self) -> None:
        # Gio aborts the process on a schema that is not installed, so a broken install fails here
        self.panel = Gio.Settings.new("com.solus-project.budgie-panel")
        self.media_keys = Gio.Settings.new(
            "org.buddiesofbudgie.settings-daemon.plugins.media-keys"
        )
        self.wm_keybindings = Gio.Settings.new("org.gnome.desktop.wm.keybindings")
        self.wm_preferences = Gio.Settings.new("org.gnome.desktop.wm.preferences")
        self.mutter_keybindings = Gio.Settings.new("org.gnome.mutter.keybindings")
        self.interface = Gio.Settings.new("org.gnome.desktop.interface")
        self.mutter = Gio.Settings.new("org.gnome.mutter")
        self.budgie_wm = Gio.Settings.new("com.solus-project.budgie-wm")
        self.input_sources = Gio.Settings.new("org.gnome.desktop.input-sources")
        self.mouse = Gio.Settings.new("org.gnome.desktop.peripherals.mouse")
        self.touchpad = Gio.Settings.new("org.gnome.desktop.peripherals.touchpad")

    def for_template(self, short_schema: str) -> Gio.Settings | None:
        """The schema a keybinds.xml bridge id names by its last two components."""
        return {
            "plugins.media-keys": self.media_keys,
            "wm.keybindings": self.wm_keybindings,
            "solus-project.budgie-wm": self.budgie_wm,
            "mutter.keybindings": self.mutter_keybindings,
            "gnome.mutter": self.mutter,
        }.get(short_schema)
