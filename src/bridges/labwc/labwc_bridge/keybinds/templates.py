# This file is part of budgie-desktop
#
# Copyright Budgie Desktop Developers
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

from __future__ import annotations

import copy
import logging
import os
import shutil
import xml.etree.ElementTree as Et
from dataclasses import dataclass

from .. import paths

log = logging.getLogger(__name__)


@dataclass
class Templates:
    """The keybind templates a keybinds.xml ships: bridge ids and static shortcuts."""

    bridged: dict[str, list[Et.Element]]
    static: dict[str, list[Et.Element]]

    @classmethod
    def load(cls) -> Templates:
        """Reads the first keybinds.xml, or the shipped .example, found in the system data dirs."""
        search_path = paths.shipped("keybinds.xml", "keybinds.xml.example")

        # First readable candidate wins, so a distro's keybinds.xml shadows the
        # .example we ship
        template_et = None
        used_path = None
        for path in search_path:
            if not os.path.isfile(path):
                continue
            try:
                template_et = Et.parse(path)
                used_path = path
                break
            except Et.ParseError as e:
                log.warning(f"Could not parse keybinds template {path}: {e}")
            except OSError as e:
                log.warning(f"Could not read keybinds template {path}: {e}")

        if template_et is None:
            log.warning(
                "Could not find a usable keybinds template (checked: "
                + ", ".join(search_path)
                + ") - no keybinds will be managed"
            )
            return cls({}, {})

        log.info(f"Loaded keybinds template from {used_path}")

        # Several actions per keybind are allowed; resolve() later decides
        # which of them this system can run
        bridge_templates: dict[str, list[Et.Element]] = {}
        static_templates: dict[str, list[Et.Element]] = {}
        for keybind in template_et.getroot().findall("./keybind"):
            bridge_key = keybind.attrib.get("bridge")
            actions = [copy.deepcopy(a) for a in keybind.findall("action")]

            # Keyed by the gsettings key it follows
            if bridge_key:
                bridge_templates[bridge_key] = actions
                continue

            # Otherwise static, keyed by the shortcut itself
            static_key = keybind.attrib.get("key")
            if not static_key:
                continue
            static_templates[static_key] = actions

        return cls(bridge_templates, static_templates)

    def resolve(
        self, bridge_key: str, labwc_version: tuple[int, ...] | None
    ) -> Et.Element | None:
        """
        Picks the first action a template offers that this system can run:
        candidates may require a given executable or a minimum labwc version,
        which is how one template serves several distros and labwc releases.
        """
        candidates = self.bridged.get(bridge_key)
        if not candidates:
            return None

        # Template order is the preference order
        for candidate in candidates:
            # An action with no name does nothing in labwc
            if not candidate.attrib.get("name", ""):
                continue

            # The command this action runs is not installed here
            executable = candidate.attrib.get("executable")
            if executable and not shutil.which(executable):
                continue

            # labwc gained some actions over time; skip ones it is too old for
            min_version = candidate.attrib.get("min_labwc_version")
            if min_version:
                try:
                    required = tuple(int(part) for part in min_version.split("."))
                except ValueError:
                    log.warning(
                        f"Bad min_labwc_version '{min_version}' for '{bridge_key}' - ignoring candidate"
                    )
                    continue
                if labwc_version is None or labwc_version < required:
                    continue

            return candidate

        return None
