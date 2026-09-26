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

from ..config import KeyValueConfig
from ..settings import Settings
from .locale1 import Locale1

log = logging.getLogger(__name__)


def _parse_options_string(options_string: str | None) -> set[str]:
    """Parse comma-separated options into a set."""
    if not options_string:
        return set()
    return {opt.strip() for opt in options_string.split(",") if opt.strip()}


def _normalize_xkb_options(options_set: set[str]) -> set[str]:
    """
    Normalize XKB options to avoid conflicts.
    Only certain option families are mutually exclusive
    Other families like lv3:, compose: can have multiple options.

    Known mutually-exclusive families: grp, caps, ctrl, altwin

    Args:
        options_set: Set of XKB option strings

    Returns:
        Set of normalized options
    """
    if not options_set:
        return set()

    # Families where only one option should be kept
    exclusive_families = {"grp", "caps", "ctrl", "altwin"}

    seen_exclusive: dict[str, str] = {}
    normalized: set[str] = set()

    for option in sorted(options_set):  # Sort for consistent behavior
        if ":" in option:
            family = option.split(":", 1)[0]

            if family in exclusive_families:
                # Keep only first of exclusive families
                if family not in seen_exclusive:
                    seen_exclusive[family] = option
                    normalized.add(option)
                # else: skip duplicate exclusive family
            else:
                # Non-exclusive family - keep all
                normalized.add(option)
        else:
            # Options without family (rare) - keep all
            normalized.add(option)

    return normalized


def _format_keyboard_layout(layout: str | None, variant: str | None = "") -> str | None:
    """
    Convert layout and variant strings to labwc format.

    Args:
        layout: Comma-separated layout string
        variant: Comma-separated variant string

    Returns:
        Formatted layout string or None if no layout
    """
    if not layout:
        return None

    if not variant:
        return layout

    variants = variant.split(",")
    layouts = layout.split(",")

    combined = []
    for i, entry in enumerate(layouts):
        if i < len(variants) and variants[i]:
            combined.append(f"{entry}({variants[i]})")
        else:
            combined.append(entry)

    return ",".join(combined)


def _base_layout(entry: str) -> str:
    """The layout without its variant: "fi(nodeadkeys)" becomes "fi"."""
    return entry.split("(", 1)[0].strip()


class LayoutResolver:
    """Resolves the keyboard layout and XKB options to write to the environment file."""

    def __init__(self, settings: Settings, locale1: Locale1) -> None:
        self.settings = settings
        self.locale1 = locale1

        # keyboard layout override for requests via budgie-daemon keyboard
        # dbus calls to give priority to this call to set the keyboard layout.
        self.override: str | None = None

    def _from_locale1(self) -> dict[str, str | None]:
        """Get keyboard layout from systemd-localed"""
        layout_info: dict[str, str | None] = {
            "layout": None,
            "variant": None,
            "model": None,
            "options": None,
        }

        props = self.locale1.properties()
        if not props:
            return layout_info

        if "X11Layout" in props:
            layout_info["layout"] = str(props["X11Layout"])
        if "X11Variant" in props:
            layout_info["variant"] = str(props["X11Variant"])
        if "X11Model" in props:
            layout_info["model"] = str(props["X11Model"])
        if "X11Options" in props:
            layout_info["options"] = str(props["X11Options"])

        if layout_info["layout"]:
            log.info(f"Got keyboard layout from locale1: {layout_info}")

        return layout_info

    def _from_default_keyboard(self) -> dict[str, str | None]:
        """
        Fallback: Read keyboard layout from /etc/default/keyboard
        """
        layout_info: dict[str, str | None] = {
            "layout": None,
            "variant": None,
            "model": None,
            "options": None,
        }

        keyboard_config = KeyValueConfig.load(
            "/etc/default/keyboard", strip_quotes=True
        )

        if "XKBLAYOUT" in keyboard_config:
            layout_info["layout"] = keyboard_config["XKBLAYOUT"]
        if "XKBVARIANT" in keyboard_config:
            layout_info["variant"] = keyboard_config["XKBVARIANT"]
        if "XKBMODEL" in keyboard_config:
            layout_info["model"] = keyboard_config["XKBMODEL"]
        if "XKBOPTIONS" in keyboard_config:
            layout_info["options"] = keyboard_config["XKBOPTIONS"]

        if layout_info["layout"]:
            log.info(f"Got keyboard layout from /etc/default/keyboard: {layout_info}")

        return layout_info

    def keyboard_layout(self) -> str:
        """
        Extract keyboard layout in this order:
        0. Applet-set override (via SetKeyboardLayout D-Bus call), if set
        1. GSettings input-sources (if exists and non-empty)
        2. systemd-localed X11Layout (if exists and non-empty)
        3. /etc/default/keyboard XKBLAYOUT (if defined)
        4. Default to "us"
        """

        # Applet-set override takes priority over everything else
        if self.override:
            log.info(f"Using applet-set keyboard layout override: {self.override}")
            return self.override

        # GSettings input-sources (if exists and non-empty)
        if self.settings.input_sources:
            sources = self.settings.input_sources["sources"]
            layout_parts = []

            for source in sources:
                if source[0] == "xkb":
                    extract = source[1].replace("'", "")

                    if "+" in extract:
                        rhs = extract.split("+")
                        extract = f"{rhs[0]}({rhs[1]})"

                    layout_parts.append(extract)

            if layout_parts:
                layout = ",".join(layout_parts)
                log.info(f"Using keyboard layout from GSettings: {layout}")
                return layout

        # systemd-localed X11Layout (if exists and non-empty)
        locale1_layout = self._from_locale1()

        formatted = _format_keyboard_layout(
            locale1_layout["layout"], locale1_layout["variant"]
        )
        if formatted:
            log.info(f"Using keyboard layout from locale1: {formatted}")
            return formatted

        # /etc/default/keyboard XKBLAYOUT (if defined)
        system_layout = self._from_default_keyboard()

        formatted = _format_keyboard_layout(
            system_layout["layout"], system_layout["variant"]
        )
        if formatted:
            log.info(f"Using keyboard layout from /etc/default/keyboard: {formatted}")
            return formatted

        # Default fallback
        log.info("Using default keyboard layout: us")
        return "us"

    def reconcile_override(self) -> None:
        """Bring the override in line with the configured layouts after they change."""
        if not self.override:
            return

        # The first entry is the layout in use
        previous = [entry.strip() for entry in self.override.split(",")]

        # keyboard_layout() returns the override when one is set, so clear it to read the configured layouts
        self.override = None
        current = [entry.strip() for entry in self.keyboard_layout().split(",")]

        # Each configured layout matches at most one previous entry, and any left unmatched were newly added
        unmatched = list(current)
        kept: list[str | None] = []

        for entry in previous:
            # Exact match first, so "fi" and "fi(nodeadkeys)" configured together each keep their own entry
            match = entry if entry in unmatched else None

            # A variant change in Control Center still counts as the same layout
            if match is None:
                base = _base_layout(entry)
                match = next((c for c in unmatched if _base_layout(c) == base), None)  # first unmatched layout with the same base, or None

            if match is not None:  # remove it so no later entry can match the same layout
                unmatched.remove(match)

            # None marks a layout that is no longer configured, and it is dropped below
            kept.append(match)

        # The layout in use was removed, so the first configured one takes over
        if kept[0] is None:
            log.info(f"Active layout {previous[0]} was removed, clearing the override")
            return

        # Keep the existing order, which a layout shortcut may have rotated, and add new layouts last
        self.override = ",".join([entry for entry in kept if entry] + unmatched)
        log.info(f"Keyboard layout override reconciled to: {self.override}")

    def xkb_options(self) -> str:
        """
        Get XKB options in this order with normalization:
        1. GSettings xkb-options (ONLY if user-modified)
        2. systemd-localed X11Options (if exists)
        3. /etc/default/keyboard XKBOPTIONS (if exists)
        4. GSettings default (if nothing else found)
        5. Empty otherwise

        Then normalize, removing duplicate families.

        A grp: option is not added here. It would let xkb move the active group
        without telling us, and the layout order we write assumes group 0.
        """
        options_set = set()
        gsettings_default = set()

        # GSettings xkb-options (if exists and non-empty)
        if self.settings.input_sources:
            try:
                user_value = self.settings.input_sources.get_user_value("xkb-options")

                if user_value is not None:
                    # User explicitly set it (even if empty)
                    gsettings_options = self.settings.input_sources.get_strv(
                        "xkb-options"
                    )
                    options_set = set(gsettings_options)
                    log.info(f"Using USER GSettings XKB options: {options_set}")
                else:
                    # Not user-modified → store default for possible fallback
                    gsettings_options = self.settings.input_sources.get_strv(
                        "xkb-options"
                    )
                    if gsettings_options:
                        gsettings_default = set(gsettings_options)
                    log.debug("GSettings xkb-options not user-modified")

            except Exception as e:
                log.debug(f"Could not read GSettings xkb-options: {e}")

        # systemd-localed X11Options (if not found in GSettings)
        if not options_set:
            locale1_layout = self._from_locale1()
            options_set = _parse_options_string(locale1_layout.get("options", ""))
            if options_set:
                log.info(f"Got XKB options from locale1: {options_set}")

        # /etc/default/keyboard XKBOPTIONS (if not found above)
        if not options_set:
            system_layout = self._from_default_keyboard()
            options_set = _parse_options_string(system_layout.get("options", ""))
            if options_set:
                log.info(f"Got XKB options from /etc/default/keyboard: {options_set}")

        if not options_set and gsettings_default:
            options_set = gsettings_default
            log.info(f"Using DEFAULT GSettings XKB options: {options_set}")

        # Empty if nothing found
        if not options_set:
            log.info("No XKB options found from any source")
            options_set = set()

        # Normalize: remove duplicate option families (keep only first of each family)
        options_set = _normalize_xkb_options(options_set)

        result = ",".join(sorted(options_set))
        log.info(f"Final XKB options: {result}")
        return result
