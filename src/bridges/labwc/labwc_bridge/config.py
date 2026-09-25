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

import contextlib
import logging
import os
import xml.etree.ElementTree as Et
from collections.abc import Generator, Iterator, Mapping

from . import labwc

log = logging.getLogger(__name__)


def save(et: Et.ElementTree[Et.Element], path: str) -> None:
    """Writes a tree the way the shipped configs are formatted: tab-indented, no declaration."""
    Et.indent(et, space="\t", level=0)
    et.write(path)


class LabwcConfig:
    """The user's rc.xml: the parsed tree, and writing it back to labwc."""

    def __init__(self, et: Et.ElementTree[Et.Element], path: str):
        self.et = et
        self.path = path
        self._deferred = False

    @classmethod
    def load(cls, source: str, path: str) -> LabwcConfig:
        """Parses `source`, which may be a shipped template; `path` is where write() puts it."""
        return cls(Et.parse(source), path)

    @property
    def root(self) -> Et.Element:
        return self.et.getroot()

    @staticmethod
    def yes_no(value: bool) -> str:
        # labwc accepts several spellings of a boolean; the shipped rc.xml uses yes/no throughout
        return "yes" if value else "no"

    def write(self) -> None:
        """Writes rc.xml and has labwc reload it, unless a deferred() batch is open."""
        if self._deferred:
            return

        save(self.et, self.path)

        labwc.reload()

    def reload(self) -> None:
        """For changes labwc reads from elsewhere, such as the environment file."""
        if self._deferred:
            return

        labwc.reload()

    @contextlib.contextmanager
    def deferred(self) -> Generator[None]:
        """
        Turns every write() and reload() inside the block into one write, and one
        labwc reload, at the end. The initial sync touches dozens of settings and
        labwc would otherwise reload once per key.
        """
        self._deferred = True
        try:
            yield
        finally:
            # Cleared even when a handler raised, or every later write would be silently skipped
            self._deferred = False

        self.write()


class KeyValueConfig(Mapping[str, str]):
    """A KEY=value file, such as labwc's environment file or /etc/default/keyboard."""

    def __init__(self, values: dict[str, str]) -> None:
        self._values = values

    @classmethod
    def load(cls, path: str, strip_quotes: bool = False) -> KeyValueConfig:
        """Reads `path`; a file that does not exist reads as empty."""
        values: dict[str, str] = {}

        # The environment file does not exist before the bridge's first run
        if not os.path.exists(path):
            return cls(values)

        try:
            with open(path) as f:
                for raw_line in f:
                    line = raw_line.strip()
                    # Blank lines, comments and lines without a separator carry no value
                    if line and not line.startswith("#") and "=" in line:
                        key, value = line.split("=", 1)
                        # /etc/default/keyboard quotes its values; the environment file does not
                        if strip_quotes:
                            value = value.strip('"').strip("'")
                        values[key] = value
        except Exception as e:
            # values holds whatever parsed before the failure, so callers that
            # rewrite the file would drop the rest without this
            log.warning(f"Could not fully read {path}: {e}")

        return cls(values)

    def __getitem__(self, key: str) -> str:
        return self._values[key]

    def __iter__(self) -> Iterator[str]:
        return iter(self._values)

    def __len__(self) -> int:
        return len(self._values)
