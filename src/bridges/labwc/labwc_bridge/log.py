# This file is part of budgie-desktop
#
# Copyright Budgie Desktop Developers
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

import logging
import sys

# python-systemd is optional; without it logging falls back to stdout
try:
    from systemd.journal import JournalHandler
except ImportError:
    JournalHandler = None


def setup(debug: bool) -> logging.Logger:
    """Configures the package logger every module's getLogger(__name__) feeds into."""
    log = logging.getLogger("labwc_bridge")
    # without this the logger inherits root's WARNING and every info()
    # is discarded before it reaches a handler
    log.setLevel(logging.DEBUG if debug else logging.INFO)

    if JournalHandler is not None:
        log.addHandler(JournalHandler())

    # stdout is the only sink when python-systemd is missing, and the extra
    # one when running by hand with --debug
    if JournalHandler is None or debug:
        log.addHandler(logging.StreamHandler(sys.stdout))

    return log
