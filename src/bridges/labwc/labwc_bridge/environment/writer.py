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

from gi.repository import Gio

from .. import paths
from ..config import KeyValueConfig, LabwcConfig
from ..settings import Settings
from .layout import LayoutResolver
from .locale1 import Locale1

log = logging.getLogger(__name__)

# The interface schema keys that live in the environment file rather than rc.xml
CURSOR_KEYS = {"cursor-theme", "cursor-size"}

# Variables the bridge owns outright: each write replaces them, and anything else in the file is the user's
FULLY_MANAGED_VARS = {
    "XKB_DEFAULT_LAYOUT",
    "XKB_DEFAULT_OPTIONS",
    "XCURSOR_THEME",
    "XCURSOR_SIZE",
    "LANG",
    "LC_CTYPE",
    "LC_NUMERIC",
    "LC_TIME",
    "LC_COLLATE",
    "LC_MONETARY",
    "LC_MESSAGES",
    "LC_PAPER",
    "LC_NAME",
    "LC_ADDRESS",
    "LC_TELEPHONE",
    "LC_MEASUREMENT",
    "LC_IDENTIFICATION",
}


class EnvironmentWriter:
    """Writes the labwc environment file: keyboard layout, XKB options, cursor, and locale."""

    def __init__(
        self,
        settings: Settings,
        layout: LayoutResolver,
        locale1: Locale1,
        config: LabwcConfig,
    ) -> None:
        self.settings = settings
        self.layout = layout
        self.locale1 = locale1
        self.config = config

        self.locale1.connect(self._locale1_changed)

    def _locale_vars(self) -> dict[str, str]:
        """Get locale settings from systemd-localed via dbus-python"""
        locale_vars: dict[str, str] = {}

        props = self.locale1.properties()
        if not props:
            return locale_vars

        # The 'Locale' property is an array of strings like "LANG=en_US.UTF-8"
        if "Locale" in props:
            locale_array = props["Locale"]
            for locale_entry in locale_array:
                if "=" in locale_entry:
                    key, value = locale_entry.split("=", 1)
                    locale_vars[key] = value
                    log.debug(f"Got from locale1: {key}={value}")

        return locale_vars

    def write(self) -> bool:
        """
        Write environment file with keyboard layout, XKB options, cursor, and locale settings

        Returns:
            True when the file changed, so the caller knows whether to reload labwc.
        """
        path = paths.user_config("environment")

        # Read existing variables to preserve user customizations
        existing_vars = KeyValueConfig.load(path)

        # Build new managed variables
        new_vars: dict[str, str] = {}

        # Get keyboard layout
        layout = self.layout.keyboard_layout()
        new_vars["XKB_DEFAULT_LAYOUT"] = layout

        # Get XKB options
        new_vars["XKB_DEFAULT_OPTIONS"] = self.layout.xkb_options()

        # Get cursor settings from desktop_interface_settings
        if self.settings.interface:
            cursor_theme = self.settings.interface.get_string("cursor-theme")
            if cursor_theme:
                new_vars["XCURSOR_THEME"] = cursor_theme

            cursor_size = self.settings.interface.get_int("cursor-size")
            if cursor_size:
                new_vars["XCURSOR_SIZE"] = str(cursor_size)

        # Get locale settings from locale1 D-Bus interface
        locale_from_locale1 = self._locale_vars()
        if locale_from_locale1:
            log.info(f"Got {len(locale_from_locale1)} locale variables from locale1")
            new_vars.update(locale_from_locale1)
        else:
            # Fallback to current environment if locale1 not available
            log.info("No locale from locale1, using environment fallback")
            for var in FULLY_MANAGED_VARS:
                if var.startswith(("LANG", "LC_")):
                    value = os.environ.get(var)
                    if value:
                        new_vars[var] = value

            # Ensure we have at least LANG set
            if "LANG" not in new_vars:
                new_vars["LANG"] = "en_US.UTF-8"

        # Merge: keep user variables, update managed ones
        final_vars: dict[str, str] = {}

        # First, add all existing variables that aren't managed
        for key, value in existing_vars.items():
            if key not in FULLY_MANAGED_VARS:
                final_vars[key] = value

        # Then add/update all managed variables
        final_vars.update(new_vars)

        # Write the file
        os.makedirs(os.path.dirname(path), exist_ok=True)

        lines = []
        lines.append("# Budgie Desktop - labwc environment configuration\n")
        lines.append(
            "# Variables fully managed by budgie: XKB_DEFAULT_LAYOUT, XKB_DEFAULT_OPTIONS, XCURSOR_*, LC_*, LANG\n"
        )
        lines.append("# Use dconf key xkb-options to add user defined values\n")
        lines.append("# Other user customizations are preserved\n\n")

        # Organize variables by category
        xkb_vars = {k: v for k, v in final_vars.items() if k.startswith("XKB_")}
        cursor_vars = {k: v for k, v in final_vars.items() if k.startswith("XCURSOR_")}
        locale_vars = {
            k: v for k, v in final_vars.items() if k.startswith("LC_") or k == "LANG"
        }
        other_vars = {
            k: v
            for k, v in final_vars.items()
            if not k.startswith("XKB_")
            and not k.startswith("XCURSOR_")
            and not k.startswith("LC_")
            and k != "LANG"
        }

        if xkb_vars:
            for key in sorted(xkb_vars.keys()):
                lines.append(f"{key}={xkb_vars[key]}\n")

        if cursor_vars:
            lines.append("\n")
            for key in sorted(cursor_vars.keys()):
                lines.append(f"{key}={cursor_vars[key]}\n")

        if locale_vars:
            lines.append("\n")
            for key in sorted(locale_vars.keys()):
                lines.append(f"{key}={locale_vars[key]}\n")

        if other_vars:
            lines.append("\n# User customizations\n")
            for key in sorted(other_vars.keys()):
                lines.append(f"{key}={other_vars[key]}\n")

        content = "".join(lines)

        try:
            with open(path) as file:
                unchanged = file.read() == content
        except OSError:
            unchanged = False

        # An identical rewrite fires the file monitor and reloads labwc for nothing
        if unchanged:
            return False

        with open(path, "w") as file:
            file.write(content)

        log.info(f"Updated environment file: {path}")
        return True

    def interface_changed(self, settings: Gio.Settings, key: str) -> None:
        """Rewrites the environment file when the cursor theme or size changes."""
        if key not in CURSOR_KEYS:
            return

        if self.write():
            self.config.reload()

    def input_sources_changed(self, settings: Gio.Settings, key: str) -> None:
        """Rewrites the environment file when the layouts or XKB options change."""
        if key not in ["sources", "xkb-options"]:
            return

        if key == "sources":
            self.layout.reconcile_override()

        if self.write():
            self.config.reload()

    def _locale1_changed(self, interface, changed, invalidated) -> None:
        """
        Handler for PropertiesChanged signals from locale1.
        Signature (s, a{sv}, as) -> interface name, changed dict, invalidated list
        """
        if self.locale1.recently_set:
            log.debug("Ignoring the locale1 PropertiesChanged for our own write")
            return

        log.info(f"locale1 PropertiesChanged received for interface: {interface}")

        if changed:
            log.info("Changed properties:")
            for k, v in dict(changed).items():
                log.info(f"  {k}: {v}")

        if invalidated:
            log.info(f"Invalidated properties: {list(invalidated)}")

        # Only a layout change should touch the override, so a locale change keeps the applet's pick
        layout_properties = {"X11Layout", "X11Variant"}

        # PropertiesChanged can carry a property with its new value or list it as invalidated, so check both
        if layout_properties & (set(dict(changed or {})) | set(invalidated or [])):
            self.layout.reconcile_override()

        if self.write():
            self.config.reload()
