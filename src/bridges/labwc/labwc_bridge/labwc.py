# This file is part of budgie-desktop
#
# Copyright Budgie Desktop Developers
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

# The bridge has to survive a single config operation failing rather than take
# the session's keybinds and theming down with it, so the broad excepts are
# deliberate.
# ruff: noqa: BLE001

import logging
import re
import subprocess

log = logging.getLogger(__name__)


def version() -> tuple[int, ...] | None:
    """
    Query the installed labwc binary for its version.

    Returns:
        Tuple of (major, minor, patch) ints, or None if labwc is not
        found or its version could not be determined.
    """
    try:
        result = subprocess.run(
            ["labwc", "--version"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except Exception as e:
        log.warning(f"Could not determine labwc version: {e}")
        return None

    output = (result.stdout or "") + (result.stderr or "")

    match = re.search(r"labwc\s+(\d+)\.(\d+)\.(\d+)", output)
    if not match:
        log.warning(f"Could not parse labwc version from: {output.strip()}")
        return None

    return tuple(int(part) for part in match.groups())


def reload() -> None:
    """Asks the running labwc to re-read its configuration."""
    subprocess.call("labwc -r", shell=True)
