# This file is part of budgie-desktop
#
# Copyright Budgie Desktop Developers
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

import logging
import os

import dbus.mainloop.glib

from . import labwc, menu, paths
from .config import LabwcConfig
from .environment.daemon import KeyboardLayoutClient
from .environment.layout import LayoutResolver
from .environment.locale1 import Locale1
from .environment.writer import EnvironmentWriter
from .handlers.appearance import Appearance
from .handlers.peripherals import Peripherals
from .handlers.window_manager import WindowManager
from .keybinds.manager import Keybinds
from .keybinds.templates import Templates
from .migrations.migration import RcXmlMigration
from .settings import Settings

log = logging.getLogger(__name__)


class Bridge:
    """Builds the components, connects gsettings to them, and runs the initial sync."""

    def __init__(self) -> None:
        # dbus-python only delivers signals through a main loop set before the first bus connection
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)

        # Ensure the path to the user config exists for when we write labwc configs
        os.makedirs(os.path.dirname(paths.user_config()), exist_ok=True)

        # Templates can require a minimum labwc version for an action
        labwc_version = labwc.version()

        # labwc reads the menu from the user dir, so the shipped one lands there with translated labels
        menu_source, menu_search_path = paths.search_for_config("menu.xml")
        menu.translate_menu_labels(menu_source, menu_search_path[0])

        # The user's rc.xml when there is one, else the shipped template written back to the user path
        rc_source, _ = paths.search_for_config("rc.xml")
        self.config = LabwcConfig.load(rc_source, paths.user_config("rc.xml"))

        # Older user configs predate the keyboard settings the template carries now
        migration = RcXmlMigration(self.config)
        if migration.needs_migration():
            log.info("Old rc.xml format detected, performing migration")
            if not migration.migrate():
                log.error("Migration failed, continuing with current config")

        self.settings = Settings()
        templates = Templates.load()

        # Each class is given what it needs here; none of them read anything back off the bridge
        locale1 = Locale1()
        self.layout = LayoutResolver(self.settings, locale1)
        self.environment = EnvironmentWriter(
            self.settings, self.layout, locale1, self.config
        )
        self.keyboard_layout = KeyboardLayoutClient(
            self.layout, self.environment, locale1, self.config
        )
        self.keybinds = Keybinds(self.config, self.settings, templates, labwc_version)
        self.peripherals = Peripherals(self.config, self.settings)
        self.window_manager = WindowManager(self.config, self.settings)
        self.appearance = Appearance(self.config, self.settings)

        self._connect()
        self.sync_all()

        # After the sync so the environment file it watches exists
        self.keyboard_layout.start()

    def _connect(self) -> None:
        settings = self.settings

        settings.panel.connect("changed", self.appearance.panel_changed)

        # Every key in these three schemas is a shortcut
        settings.media_keys.connect("changed", self.keybinds.changed)
        settings.wm_keybindings.connect("changed", self.keybinds.changed)
        settings.mutter_keybindings.connect("changed", self.keybinds.changed)

        # budgie-wm and mutter mix shortcuts with other settings; each handler ignores keys that are not its own
        settings.budgie_wm.connect("changed", self.window_manager.budgie_wm_changed)
        settings.budgie_wm.connect("changed", self.keybinds.changed)
        settings.mutter.connect("changed", self.window_manager.mutter_changed)
        settings.mutter.connect("changed", self.keybinds.changed)

        settings.wm_preferences.connect(
            "changed", self.window_manager.wm_preferences_changed
        )

        # Likewise: theme keys go to rc.xml, cursor keys to the environment file
        settings.interface.connect("changed", self.appearance.interface_changed)
        settings.interface.connect("changed", self.environment.interface_changed)

        settings.input_sources.connect(
            "changed", self.environment.input_sources_changed
        )

        settings.mouse.connect("changed", self.peripherals.changed)
        settings.touchpad.connect("changed", self.peripherals.changed)

        # GNOME has two booleans where labwc has one scrollMethod, so both keys share a handler
        settings.touchpad.connect(
            "changed::two-finger-scrolling-enabled",
            self.peripherals.scroll_method_changed,
        )
        settings.touchpad.connect(
            "changed::edge-scrolling-enabled", self.peripherals.scroll_method_changed
        )

    def sync_all(self) -> None:
        # Dozens of keys are replayed here; the batch turns that into one write and one labwc reload
        with self.config.deferred():
            self.keybinds.sync_all()
            self.window_manager.sync_all()
            self.appearance.sync_all()
            # Cursor, layout and locale all feed the one environment file, so it is written once
            self.environment.write()
            self.peripherals.sync_all()
