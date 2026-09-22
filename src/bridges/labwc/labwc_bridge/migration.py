# This file is part of budgie-desktop
#
# Copyright Budgie Desktop Developers
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

# ruff: noqa: BLE001

from __future__ import annotations

import copy
import logging
import os
import shutil
import xml.etree.ElementTree as Et
from dataclasses import dataclass

from . import paths
from .config import LabwcConfig, save

log = logging.getLogger(__name__)

CURRENT_RC_VERSION = 2


@dataclass(frozen=True)
class ActionRewrite:
    """One action attribute an rc.xml version replaces, and the value it replaces."""

    bridge: str
    action: str
    attribute: str
    stale: str
    value: str


# Keyed by the rc.xml version that introduced the change; a config is brought up to
# date by applying every version above its own, oldest first
ACTION_REWRITES: dict[int, tuple[ActionRewrite, ...]] = {
    2: (
        ActionRewrite(
            bridge="wm.keybindings/maximize-horizontally",
            action="Maximize",
            attribute="direction",
            stale="right",
            value="horizontal",
        ),
        ActionRewrite(
            bridge="wm.keybindings/maximize-vertically",
            action="Maximize",
            attribute="direction",
            stale="left",
            value="vertical",
        ),
    ),
}


class RcXmlMigration:
    """Handles migration of rc.xml to newer versions"""

    def __init__(self, config: LabwcConfig):
        self.config = config

    def get_rc_version(self, et: Et.ElementTree[Et.Element]) -> int:
        """Get the version number from rc.xml root element"""
        root = et.getroot()
        version = root.get("version")
        if version is None:
            return 0  # No version means old/original format
        return int(version)

    def needs_migration(self) -> bool:
        """Check if user's rc.xml needs migration"""
        try:
            user_version = self.get_rc_version(self.config.et)
            return user_version < CURRENT_RC_VERSION
        except ValueError:
            return False

    def backup_user_config(self) -> bool:
        """Create backup of user's current rc.xml"""
        user_path = self.config.path
        backup_path = user_path + ".backup"

        try:
            shutil.copy2(user_path, backup_path)
            log.info(f"Backed up rc.xml to {backup_path}")
            return True
        except Exception as e:
            log.error(f"Failed to backup rc.xml: {e}")
            return False

    def load_template(self) -> Et.ElementTree[Et.Element] | None:
        """Load the new template rc.xml from system data dirs"""
        # A distro's own template shadows ours within the same data dir
        for template_path in paths.shipped("distro-rc.xml", "rc.xml"):
            if not os.path.isfile(template_path):
                continue
            try:
                return Et.parse(template_path)
            except Exception as e:
                log.warning(f"Cannot parse template {template_path}: {e}")

        log.error("Could not find rc.xml template")
        return None

    def replace_keyboard_section(
        self,
        user_et: Et.ElementTree[Et.Element],
        template_et: Et.ElementTree[Et.Element],
    ) -> bool:
        """Merge the template's keyboard section"""
        user_root = user_et.getroot()
        template_root = template_et.getroot()

        # Find keyboard section in template
        template_keyboard = template_root.find("./keyboard")
        if template_keyboard is None:
            log.error("Template has no keyboard section")
            return False

        user_keyboard = user_root.find("./keyboard")

        if user_keyboard is None:
            # Nothing of the user's to preserve - insert the template's
            # keyboard section wholesale.
            new_keyboard = copy.deepcopy(template_keyboard)

            theme_element = user_root.find("./theme")
            if theme_element is not None:
                insert_index = list(user_root).index(theme_element)
                user_root.insert(insert_index, new_keyboard)
            else:
                windowrules_element = user_root.find("./windowRules")
                if windowrules_element is not None:
                    insert_index = list(user_root).index(windowrules_element)
                    user_root.insert(insert_index, new_keyboard)
                else:
                    user_root.append(new_keyboard)

            log.info("Inserted keyboard section from template")
            return True

        # Bring over any non-keybind settings (e.g. <numlock>)
        added_any = False
        for template_child in template_keyboard:
            if template_child.tag == "keybind":
                continue
            if user_keyboard.find(f"./{template_child.tag}") is None:
                user_keyboard.append(copy.deepcopy(template_child))
                added_any = True

        if added_any:
            log.info("Added missing non-keybind keyboard settings from template")
        else:
            log.info(
                "Keyboard section already has all non-keybind settings - nothing to merge"
            )

        return True

    @staticmethod
    def apply_rewrite(user_root: Et.Element, rewrite: ActionRewrite) -> bool:
        """Apply one action rewrite wherever it still holds the value we shipped; True when any did"""
        changed = False

        for keybind in user_root.findall(
            f"./keyboard/keybind[@bridge='{rewrite.bridge}']"
        ):
            action = keybind.find(f"./action[@name='{rewrite.action}']")
            # Any other value is the user's own, or a rewrite already applied
            if action is None or action.get(rewrite.attribute) != rewrite.stale:
                continue

            action.set(rewrite.attribute, rewrite.value)
            changed = True
            log.info(
                f"Set '{rewrite.bridge}' {rewrite.action} {rewrite.attribute} "
                f"from '{rewrite.stale}' to '{rewrite.value}'"
            )

        return changed

    def apply_rewrites(
        self, user_et: Et.ElementTree[Et.Element], from_version: int
    ) -> bool:
        """Apply the action rewrites of every rc.xml version above from_version; True when any did"""
        user_root = user_et.getroot()
        changed = False

        for version in sorted(ACTION_REWRITES):
            if version <= from_version:
                continue

            log.info(f"Applying rc.xml version {version} action rewrites")
            for rewrite in ACTION_REWRITES[version]:
                changed |= self.apply_rewrite(user_root, rewrite)

        return changed

    def migrate(self) -> bool:
        """Merge missing non-keybind keyboard settings from the template and apply the action rewrites"""
        user_version = self.get_rc_version(self.config.et)
        log.info(f"Starting rc.xml migration from version {user_version}")

        # Step 1: Backup current config
        if not self.backup_user_config():
            log.error("Migration aborted - backup failed")
            return False

        # Step 2: Load template
        template_et = self.load_template()
        if template_et is None:
            log.error("Migration aborted - no template found")
            return False

        # Step 3: Replace keyboard section in user's config
        user_et = self.config.et
        if not self.replace_keyboard_section(user_et, template_et):
            log.error("Migration aborted - failed to replace keyboard section")
            return False

        # Step 4: Bring actions written by older versions up to date
        self.apply_rewrites(user_et, user_version)

        # Step 5: Set version number on user config
        user_root = user_et.getroot()
        user_root.set("version", str(CURRENT_RC_VERSION))

        # Step 6: Write updated config
        save(user_et, self.config.path)

        return True
