# This file is part of budgie-desktop
#
# Copyright Budgie Desktop Developers
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

# ruff: noqa: BLE001

import logging
from collections.abc import Callable

import dbus

log = logging.getLogger(__name__)


class Locale1:
    """The org.freedesktop.locale1 system bus service: properties and change notification."""

    def __init__(self) -> None:
        try:
            self.bus = dbus.SystemBus()
        except Exception as e:
            log.warning(f"Could not setup locale1 monitoring: {e}")
            self.bus = None

    def properties(self) -> dict:
        """
        Get all properties from org.freedesktop.locale1.

        Returns:
            Dict of properties, or empty when the bus is unavailable.
        """
        if self.bus is None:
            return {}

        try:
            proxy = self.bus.get_object(
                "org.freedesktop.locale1", "/org/freedesktop/locale1"
            )

            props_iface = dbus.Interface(proxy, "org.freedesktop.DBus.Properties")

            return props_iface.GetAll("org.freedesktop.locale1")

        except dbus.DBusException as e:
            log.debug(f"Could not read locale1 properties: {e}")
            return {}

    def connect(self, callback: Callable[[str, dict, list], None]) -> None:
        """Subscribes to PropertiesChanged signals from locale1."""
        if self.bus is None:
            return

        # arg0 is the interface named inside PropertiesChanged, so other services' property changes are filtered out
        self.bus.add_signal_receiver(
            callback,
            signal_name="PropertiesChanged",
            dbus_interface="org.freedesktop.DBus.Properties",
            path="/org/freedesktop/locale1",
            arg0="org.freedesktop.locale1",
        )
