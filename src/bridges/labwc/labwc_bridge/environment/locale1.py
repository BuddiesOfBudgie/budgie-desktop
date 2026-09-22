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
from gi.repository import GLib

log = logging.getLogger(__name__)

# A PropertiesChanged arriving within this many seconds of our own write is the echo of it
SELF_CHANGE_WINDOW = 2


def _split_keyboard_layout(combined: str) -> tuple[str, str]:
    """
    Split an XKB layout string into the two parallel lists locale1 takes.

    "fi(nodeadkeys),us" becomes ("fi,us", "nodeadkeys,"). The variant list is
    empty when no entry carries one.
    """
    layouts = []
    variants = []

    for entry in combined.split(","):
        entry = entry.strip()

        if entry.endswith(")") and "(" in entry:
            name, _, variant = entry[:-1].partition("(")
            layouts.append(name.strip())
            variants.append(variant.strip())
        else:
            layouts.append(entry)
            variants.append("")

    if not any(variants):
        return ",".join(layouts), ""

    return ",".join(layouts), ",".join(variants)


class Locale1:
    """The org.freedesktop.locale1 system bus service: properties and change notification."""

    def __init__(self) -> None:
        try:
            self.bus = dbus.SystemBus()
        except Exception as e:
            log.warning(f"Could not setup locale1 monitoring: {e}")
            self.bus = None

        self._self_change_timeout = None

    @property
    def recently_set(self) -> bool:
        """True while a PropertiesChanged signal is still expected from our own write."""
        return self._self_change_timeout is not None

    def _mark_recently_set(self) -> None:
        if self._self_change_timeout is not None:
            GLib.source_remove(self._self_change_timeout)

        self._self_change_timeout = GLib.timeout_add_seconds(
            SELF_CHANGE_WINDOW, self._clear_recently_set
        )

    def _clear_recently_set(self) -> bool:
        self._self_change_timeout = None

        return GLib.SOURCE_REMOVE

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

    def set_x11_keyboard(self, combined: str, convert: bool = True) -> bool:
        """
        Set the system X11 keyboard layout, and the console keymap with it.

        Takes an XKB layout string such as "fi(nodeadkeys),us". The model and
        options are read back and passed through, since the call replaces all
        four at once. Non-interactive, so it fails rather than prompting: most
        distributions gate this behind polkit admin auth, and Debian and Ubuntu
        refuse it.

        Returns:
            True when locale1 accepted a change.
        """
        if self.bus is None:
            return False

        layout, variant = _split_keyboard_layout(combined)

        props = self.properties()

        # The call rewrites 00-keyboard.conf and vconsole.conf, and runs a polkit check
        if (str(props.get("X11Layout", "")), str(props.get("X11Variant", ""))) == (
            layout,
            variant,
        ):
            return False

        try:
            proxy = self.bus.get_object(
                "org.freedesktop.locale1", "/org/freedesktop/locale1"
            )

            iface = dbus.Interface(proxy, "org.freedesktop.locale1")

            iface.SetX11Keyboard(
                layout,
                str(props.get("X11Model", "")),
                variant,
                str(props.get("X11Options", "")),
                convert,
                False,
            )

        except dbus.DBusException as e:
            log.debug(f"locale1 refused SetX11Keyboard: {e}")
            return False

        self._mark_recently_set()

        log.info(f"Set locale1 X11Layout to {layout}")
        return True

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
