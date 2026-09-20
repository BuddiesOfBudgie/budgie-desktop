# This file is part of budgie-desktop
#
# Copyright Budgie Desktop Developers
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

import os

from gi.repository import GLib


def user_config(config_file: str = "rc.xml") -> str:
    """The path of a file in the user's labwc config dir."""
    return os.path.join(
        GLib.get_user_config_dir(), "budgie-desktop", "labwc", config_file
    )


def shipped(*names: str) -> list[str]:
    """
    Where budgie installs `names` under budgie-desktop/labwc, per system data
    dir, earlier names first within each dir.
    """
    return [
        os.path.join(system_dir, "budgie-desktop", "labwc", name)
        for system_dir in GLib.get_system_data_dirs()
        for name in names
    ]


def search_for_config(config_file: str) -> tuple[str, list[str]]:
    """
    The user's copy first, then the distro variant, then what budgie ships,
    per system data dir. Returns the first that exists along with the whole
    search path, whose head is where the user's copy belongs.
    """
    search_path = [user_config(config_file)]
    for system_dir in GLib.get_system_data_dirs():
        search_path.append(
            os.path.join(system_dir, "budgie-desktop", "distro-" + config_file)
        )
        search_path.append(os.path.join(system_dir, "budgie-desktop", config_file))

    for path in search_path:
        if os.path.isfile(path):
            return path, search_path

    raise FileNotFoundError(
        f"Could not find an existing {config_file} or a shipped budgie equivalent"
    )
