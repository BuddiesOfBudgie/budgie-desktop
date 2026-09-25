# This file is part of budgie-desktop
#
# Copyright Budgie Desktop Developers
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

from __future__ import annotations

import logging
import xml.etree.ElementTree as Et
from collections.abc import Iterable

from gi.repository import Gio

from ..config import LabwcConfig
from ..settings import Settings
from .accel import calc_keybind
from .templates import Templates

log = logging.getLogger(__name__)

# Marks the static keybinds this bridge owns, so ones dropped from the template
# can be removed later without touching keybinds the user wrote themselves.
STATIC_KEYBIND_MANAGED_ATTR = "managed"
STATIC_KEYBIND_MANAGED_VALUE = "labwc-bridge"

# Each custom shortcut is an instance of this relocatable schema at its own path
CUSTOM_KEYBINDING_SCHEMA = (
    "org.buddiesofbudgie.settings-daemon.plugins.media-keys.custom-keybinding"
)

# Template attributes that pick between candidate actions; labwc does not know them
SELECTOR_ATTRIBS = ("executable", "min_labwc_version")

# budgie-wm and mutter hold ordinary settings next to their shortcuts; these are the shortcuts
MIXED_SCHEMA_SHORTCUTS = {
    "solus-project.budgie-wm": {
        "clear-notifications",
        "show-power-dialog",
        "take-full-screenshot",
        "take-region-screenshot",
        "toggle-notifications",
        "toggle-raven",
    },
    "gnome.mutter": {"overlay-key"},
}


def _is_managed(keybind: Et.Element) -> bool:
    """Whether a static keybind carries this bridge's marker."""
    return (
        keybind.attrib.get(STATIC_KEYBIND_MANAGED_ATTR) == STATIC_KEYBIND_MANAGED_VALUE
    )


def _custom_id(path: str) -> str:
    """The rc.xml bridge id of a custom shortcut: the last segment of its gsettings path, e.g. custom0."""
    return path.split("/")[-2]


def _action_attribs(keybind: Et.Element) -> dict[str, str] | None:
    """The attributes of a keybind's action, or None when it has none."""
    action = keybind.find("action")
    return dict(action.attrib) if action is not None else None


def _set_attrib(element: Et.Element, name: str, value: str) -> bool:
    """Sets one attribute; True when its value changed."""
    if element.attrib.get(name) == value:
        return False
    element.attrib[name] = value
    return True


def _set_attribs(element: Et.Element, attribs: dict[str, str]) -> bool:
    """Sets each attribute; True when any value changed."""
    changed = False
    for name, value in attribs.items():
        changed |= _set_attrib(element, name, value)
    return changed


def _set_action(keybind: Et.Element, attribs: dict[str, str]) -> bool:
    """Makes the keybind's action carry exactly `attribs`, creating it if needed; True when anything changed."""
    action = keybind.find("action")
    if action is None:
        action = Et.SubElement(keybind, "action")
        action.attrib.update(attribs)
        return True

    if dict(action.attrib) == attribs:
        return False

    action.attrib.clear()
    action.attrib.update(attribs)
    return True


def _remove_action(keybind: Et.Element) -> bool:
    """Strips the keybind's action; True when there was one."""
    action = keybind.find("action")
    if action is None:
        return False
    keybind.remove(action)
    return True


class Keybinds:
    """Keeps rc.xml's keybinds in step with the gsettings schemas and the keybind template."""

    def __init__(
        self,
        config: LabwcConfig,
        settings: Settings,
        templates: Templates,
        labwc_version: tuple[int, ...] | None,
    ) -> None:
        self.config = config
        self.settings = settings
        self.templates = templates
        self.labwc_version = labwc_version
        self.custom_keys_settings: dict[Gio.Settings, int] = {}

    def _keyboard(self) -> Et.Element | None:
        """rc.xml's <keyboard>, home of every keybind."""
        return self.config.root.find("./keyboard")

    @staticmethod
    def _short_schema(settings: Gio.Settings) -> str | None:
        """How a template names a schema: its last two dotted components."""
        parts = settings.props.schema.split(".")
        if len(parts) < 2:
            return None
        return parts[-2] + "." + parts[-1]

    @staticmethod
    def _bindings(settings: Gio.Settings, key: str) -> list[str]:
        """The accelerators bound to a key, always as a list."""
        # for some reason, the mutter overlay-key is a string, while every other key, rest of mutter included, is a string array.
        # turning overlay-key into an array seems to allow it to work properly, or else it ends up as just the first character
        if key == "overlay-key":
            return [settings[key]]
        return settings[key] or []

    @staticmethod
    def _static_bindings(settings: Gio.Settings, key: str) -> list[str] | None:
        """The -static sibling's accelerators when it has any, else None."""
        static_key = key + "-static"
        # Not every media key has a -static sibling
        if static_key not in settings:
            log.info(f"No -static key found for '{key}'")
            return None

        static_bindings = settings[static_key]
        log.info(f"Main key '{key}' is empty, checking -static: {static_bindings}")
        if not static_bindings or not any(static_bindings):
            return None

        log.info(f"Using -static values for '{key}'")
        return static_bindings

    def changed(self, settings: Gio.Settings, key: str) -> None:
        """Re-syncs the rc.xml keybind behind a gsettings shortcut key that changed."""
        if key not in settings:
            return

        # The list of custom shortcuts is a key like any other, but its contents live elsewhere
        if key == "custom-keybindings":
            self.custom_changed(self.settings.media_keys, None)
            return

        short_schema = self._short_schema(settings)
        if short_schema is None:
            return

        # Schemas that hold more than shortcuts contribute only their listed keys
        supported = MIXED_SCHEMA_SHORTCUTS.get(short_schema)
        if supported is not None and key not in supported:
            return

        # A template need not bridge every key the bridge would accept
        bridge_id = short_schema + "/" + key
        if bridge_id not in self.templates.bridged:
            return

        bindings = self._bindings(settings, key)

        # media-keys pairs each shortcut with a -static sibling that holds the fixed default
        if settings == self.settings.media_keys and not any(bindings):
            bindings = self._static_bindings(settings, key) or bindings

        if self.sync(bridge_id, bindings):
            self.config.write()

    def custom_changed(self, settings: Gio.Settings, customkeypath: str | None) -> None:
        """Reconciles rc.xml's custom keybinds with the user's custom shortcuts and follows each for edits."""
        keyboard = self._keyboard()
        if keyboard is None:
            return

        paths = self.settings.media_keys.get_strv("custom-keybindings")
        current_ids = {_custom_id(path) for path in paths}

        # A shortcut the user deleted leaves its keybind behind in rc.xml
        for keybind in keyboard.findall("./keybind[@bridge]"):
            bridge_id = keybind.attrib["bridge"]
            if "custom" in bridge_id and bridge_id not in current_ids:
                keyboard.remove(keybind)

        # The subscriptions are rebuilt each time, so a deleted shortcut's schema is dropped with it
        self.custom_keys_settings = {}
        for path in paths:
            schema = Gio.Settings.new_with_path(CUSTOM_KEYBINDING_SCHEMA, path)
            self.custom_keys_settings[schema] = schema.connect(
                "changed", self.custom_changed
            )
            self._sync_custom(keyboard, _custom_id(path), schema)

        self.config.write()

    def _sync_custom(
        self, keyboard: Et.Element, bridge_id: str, schema: Gio.Settings
    ) -> None:
        """Creates or refreshes the keybind for one custom shortcut."""
        keybind = keyboard.find(f"./keybind[@bridge='{bridge_id}']")
        if keybind is None:
            keybind = Et.SubElement(keyboard, "keybind")
            keybind.attrib["bridge"] = bridge_id

        # A custom shortcut is always a command to run
        keybind.attrib["key"] = calc_keybind(schema["binding"])
        _set_action(keybind, {"name": "Execute", "command": schema["command"]})

    def sync(self, bridge_id: str, bindings: Iterable[str] | None) -> bool:
        """Creates, updates or removes the keybind elements for one bridge id; True when rc.xml changed."""
        keyboard = self._keyboard()
        if keyboard is None:
            return False

        existing = keyboard.findall(f"./keybind[@bridge='{bridge_id}']")
        template = self.templates.bridged.get(bridge_id)
        action = self.templates.resolve(bridge_id, self.labwc_version)
        bindings = [binding for binding in (bindings or []) if binding]

        # The user cleared the shortcut, or nothing in the template runs here: whatever we wrote before goes
        if template is None or action is None or not bindings:
            for keybind in existing:
                keyboard.remove(keybind)
            if existing:
                log.info(
                    f"Removed keybind(s) for '{bridge_id}' (undefined key or no valid action)"
                )
            return bool(existing)

        attribs = {k: v for k, v in action.attrib.items() if k not in SELECTOR_ATTRIBS}
        changed = False

        # gsettings allows several accelerators per shortcut; each gets its own keybind, existing ones reused in order
        for i, binding in enumerate(bindings):
            if i < len(existing):
                keybind = existing[i]
            else:
                keybind = Et.SubElement(keyboard, "keybind")
                keybind.attrib["bridge"] = bridge_id
                changed = True

            changed |= _set_attrib(keybind, "key", calc_keybind(binding))
            changed |= _set_attribs(keybind, template.attribs)
            changed |= _set_action(keybind, attribs)

        # Accelerators removed in gsettings leave surplus keybinds behind
        for keybind in existing[len(bindings) :]:
            keyboard.remove(keybind)
            changed = True

        return changed

    @staticmethod
    def _static_owners(
        keyboard: Et.Element, key: str
    ) -> tuple[Et.Element | None, Et.Element | None]:
        """The keybinds already on a static key: ours from an earlier run, and the user's own."""
        managed = None
        unmanaged = None

        # Bridged keybinds are sync()'s; only unbridged ones can be static
        for keybind in keyboard.findall("keybind"):
            if "bridge" in keybind.attrib or keybind.attrib.get("key") != key:
                continue
            if _is_managed(keybind):
                managed = keybind
            else:
                unmanaged = keybind

        return managed, unmanaged

    def sync_static(self) -> bool:
        """
        Merges the template's static keybinds; True when rc.xml changed. A user may
        already have bound the same key by hand: that one is adopted only when it
        matches the template exactly, otherwise it is left alone and no managed copy
        is added.
        """
        keyboard = self._keyboard()
        if keyboard is None:
            return False

        changed = False

        for key, template in self.templates.static.items():
            # Static templates take their first action as written, selector attributes included
            desired = dict(template.actions[0].attrib) if template.actions else None
            managed, unmanaged = self._static_owners(keyboard, key)

            # The user got here first. Claim it only if it is byte-for-byte what we
            # would have written, which means an earlier unmarked release of ours
            # put it there; anything else is theirs to keep.
            if managed is None and unmanaged is not None:
                if _action_attribs(unmanaged) != desired:
                    log.info(
                        f"Not creating static keybind for '{key}' - a user-defined keybind already uses this key"
                    )
                    continue

                unmanaged.attrib[STATIC_KEYBIND_MANAGED_ATTR] = (
                    STATIC_KEYBIND_MANAGED_VALUE
                )
                managed = unmanaged
                changed = True
                log.info(
                    f"Adopted pre-existing static keybind '{key}' (content matches template exactly)"
                )

            # Nobody has this key: write it out marked as ours
            if managed is None:
                if desired is None:
                    continue
                managed = Et.SubElement(keyboard, "keybind")
                managed.attrib["key"] = key
                managed.attrib[STATIC_KEYBIND_MANAGED_ATTR] = (
                    STATIC_KEYBIND_MANAGED_VALUE
                )
                changed = True

            # Ours: bring the action in line with the template, or strip it when nothing is viable here
            if desired is None:
                changed |= _remove_action(managed)
            else:
                changed |= _set_attribs(managed, template.attribs)
                changed |= _set_action(managed, desired)

        return changed

    def cleanup(self) -> None:
        """
        Drops keybinds the template no longer defines. Only ones this bridge wrote
        are eligible: bridged entries by their bridge= key, static ones by the
        managed marker, so a user's own keybinds survive.
        """
        keyboard = self._keyboard()
        if keyboard is None:
            return

        removed = False
        for keybind in list(keyboard.findall("keybind")):
            bridge_id = keybind.attrib.get("bridge")
            static_key = keybind.attrib.get("key")

            if bridge_id:
                # Custom shortcuts come from gsettings rather than the template, so they are never stale
                if "custom" in bridge_id or bridge_id in self.templates.bridged:
                    continue
                log.info(f"Removed keybind '{bridge_id}'")
            elif (
                _is_managed(keybind)
                and static_key
                and static_key not in self.templates.static
            ):
                # Only the marker tells our static keybinds from the user's
                log.info(f"Removed static keybind '{static_key}'")
            else:
                continue

            keyboard.remove(keybind)
            removed = True

        if removed:
            self.config.write()

    def sync_all(self) -> None:
        """Rebuilds every managed keybind from the template and the current gsettings."""
        self.cleanup()

        if self.sync_static():
            self.config.write()

        for bridge_id in self.templates.bridged:
            try:
                short_schema, key = bridge_id.split("/", 1)
            except ValueError:
                continue

            # Custom shortcuts are driven by their own schema instances below
            if "custom" in short_schema:
                continue

            settings = self.settings.for_template(short_schema)
            if settings is not None:
                self.changed(settings, key)

        self.custom_changed(self.settings.media_keys, None)
