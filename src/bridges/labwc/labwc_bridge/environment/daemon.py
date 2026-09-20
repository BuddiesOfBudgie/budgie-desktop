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

import dbus
from gi.repository import Gio, GLib

from .. import paths
from ..config import KeyValueConfig, LabwcConfig
from .layout import LayoutResolver
from .writer import EnvironmentWriter

log = logging.getLogger(__name__)

# Connect to budgie-daemon budgie keyboard layout proxy to handle
# requests to change the keyboard layout.
KEYBOARD_LAYOUT_DBUS_INTERFACE = "org.buddiesofbudgie.KeyboardLayout"
KEYBOARD_LAYOUT_DBUS_OBJECT_PATH = "/org/buddiesofbudgie/KeyboardLayout"
KEYBOARD_LAYOUT_DBUS_SIGNAL = "LayoutChanged"
KEYBOARD_LAYOUT_DBUS_PROPERTY = "CurrentLayout"

DBUS_PROPERTIES_INTERFACE = "org.freedesktop.DBus.Properties"


class KeyboardLayoutClient:
    """Talks to budgie-daemon's keyboard layout proxy: layout requests in, CurrentLayout out."""

    def __init__(
        self,
        layout: LayoutResolver,
        environment: EnvironmentWriter,
        config: LabwcConfig,
    ) -> None:
        self.layout = layout
        self.environment = environment
        self.config = config

        # watches the environment file so CurrentLayout follows what was written,
        # and the last value published to budgie-daemon
        self.bus = None
        self.environment_monitor = None
        self.current_layout_published = None

    def start(self) -> None:
        """
        Listen to budgie-daemon's LayoutChanged signal on
        org.buddiesofbudgie.KeyboardLayout.
        """
        try:
            session_bus = dbus.SessionBus()
            self.bus = session_bus
            session_bus.add_signal_receiver(
                self._layout_changed,
                signal_name=KEYBOARD_LAYOUT_DBUS_SIGNAL,
                dbus_interface=KEYBOARD_LAYOUT_DBUS_INTERFACE,
                path=KEYBOARD_LAYOUT_DBUS_OBJECT_PATH,
            )
            session_bus.watch_name_owner(
                KEYBOARD_LAYOUT_DBUS_INTERFACE, self._owner_changed
            )
            log.info(
                f"Subscribed to {KEYBOARD_LAYOUT_DBUS_INTERFACE}.{KEYBOARD_LAYOUT_DBUS_SIGNAL}"
            )
        except dbus.DBusException as e:
            log.warning(f"Could not subscribe to keyboard layout proxy: {e}")

        if self.environment_monitor is not None:
            return

        # Watch the environment file so CurrentLayout reflects what was written.
        path = paths.user_config("environment")

        if not os.path.exists(path):
            return

        try:
            gfile = Gio.File.new_for_path(path)
            self.environment_monitor = gfile.monitor_file(
                Gio.FileMonitorFlags.NONE, None
            )
            self.environment_monitor.connect("changed", self._environment_file_changed)
        except GLib.Error as e:
            log.warning(f"Could not monitor {path}: {e}")
            return

        log.info(f"Monitoring {path} for keyboard layout changes")

        # The file is already on disk, so nothing will fire the monitor for it
        self.publish()

    def _owner_changed(self, owner) -> None:
        """
        budgie-daemon holds CurrentLayout in memory, so a restart of it drops
        the value and we have to publish again.
        """
        if not owner:
            return

        self.current_layout_published = None
        self.publish()

    def _layout_changed(self, layout) -> None:
        """
        Handler for budgie-daemon's LayoutChanged signal. Sets a bridge-side
        override which takes priority over the normal GSettings/locale1/system file
        auto-detection in LayoutResolver.keyboard_layout(), so that later, unrelated
        environment file rewrites (triggered by e.g. a locale1
        PropertiesChanged signal or a cursor theme change) don't silently
        revert the applet's choice.
        """
        layout = str(layout).strip() if layout else ""
        if not layout:
            log.warning("Received LayoutChanged with an empty layout, ignoring")
            return

        log.info(f"Keyboard layout requested via daemon: {layout}")
        self.layout.override = layout

        self.environment.write()

        self.config.reload()

    def _environment_file_changed(self, monitor, gfile, other_file, event) -> None:
        """Republishes CurrentLayout once a rewrite of the environment file has finished."""
        # The environment file is rewritten in place, so a plain CHANGED can
        # land mid-write.
        if event not in (
            Gio.FileMonitorEvent.CHANGES_DONE_HINT,
            Gio.FileMonitorEvent.CREATED,
        ):
            return

        self.publish()

    def _read_current_layout(self) -> str | None:
        """
        The layout in use, from the environment file. XKB_DEFAULT_LAYOUT is
        ordered with the active layout first, and may carry a variant.
        """
        env = KeyValueConfig.load(paths.user_config("environment"))
        layout = env.get("XKB_DEFAULT_LAYOUT", "").strip()

        if not layout:
            return ""

        # e.g. "fi(nodeadkeys),us" -> "fi"
        return layout.split(",")[0].split("(")[0].strip()

    def publish(self) -> None:
        """Hand the layout to budgie-daemon so the applet can display it."""
        layout = self._read_current_layout()

        # A cursor or locale change rewrites the file without touching the
        # layout, so only publish when the value has moved
        if self.bus is None or not layout or layout == self.current_layout_published:
            return

        try:
            proxy = self.bus.get_object(
                KEYBOARD_LAYOUT_DBUS_INTERFACE, KEYBOARD_LAYOUT_DBUS_OBJECT_PATH
            )
            properties = dbus.Interface(proxy, DBUS_PROPERTIES_INTERFACE)
            properties.Set(
                KEYBOARD_LAYOUT_DBUS_INTERFACE,
                KEYBOARD_LAYOUT_DBUS_PROPERTY,
                dbus.String(layout),
            )
        except dbus.DBusException as e:
            log.warning(f"Could not publish {KEYBOARD_LAYOUT_DBUS_PROPERTY}: {e}")
            return

        self.current_layout_published = layout
        log.info(f"Published {KEYBOARD_LAYOUT_DBUS_PROPERTY}={layout}")
