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
import re
import xml.etree.ElementTree as Et
from dataclasses import dataclass

log = logging.getLogger(__name__)

_PREDICATE = re.compile(r"\[@([\w.:-]+)='([^']*)'\]")


def split_path(path: str) -> list[str]:
    """
    The steps of an rc.xml path. A bridge id carries a slash of its own, so a
    plain split would cut predicates such as [@bridge='wm.keybindings/maximize']
    in half.
    """
    steps: list[str] = []
    current = ""
    depth = 0

    for char in path:
        if char == "[":
            depth += 1
        elif char == "]":
            depth -= 1

        if char == "/" and depth == 0:
            steps.append(current)
            current = ""
        else:
            current += char

    steps.append(current)
    return [step for step in steps if step not in ("", ".")]


def parse_step(step: str) -> tuple[str, dict[str, str]]:
    """The tag a path step names, and the attributes its predicates pin it to."""
    tag, bracket, predicates = step.partition("[")
    return tag, dict(_PREDICATE.findall(bracket + predicates))


def parents(root: Et.Element) -> dict[Et.Element, Et.Element]:
    """Each element's parent; ElementTree keeps no upward links of its own."""
    return {child: parent for parent in root.iter() for child in parent}


def resolve(root: Et.Element, steps: list[str]) -> Et.Element:
    """The element `steps` names, creating any of them that are missing."""
    element = root

    for step in steps:
        found = element.find(step)
        if found is None:
            tag, attribs = parse_step(step)
            found = Et.SubElement(element, tag, attribs)
        element = found

    return element


@dataclass(frozen=True)
class Target:
    """
    Where a value lives in rc.xml. `path` addresses the element from the document
    root; `attribute` is the attribute holding the value, or the element's text
    when left out.
    """

    path: str
    attribute: str | None = None

    @property
    def steps(self) -> list[str]:
        return split_path(self.path)

    @property
    def held_in(self) -> str:
        """What holds the value, for the log."""
        return self.attribute or "text"

    def read(self, element: Et.Element) -> str:
        if self.attribute is None:
            return (element.text or "").strip()
        return element.get(self.attribute, "")

    def write(self, element: Et.Element, value: str) -> None:
        if self.attribute is None:
            element.text = value
        else:
            element.set(self.attribute, value)

    def clear(self, element: Et.Element) -> None:
        """Drop the value, for when it now lives somewhere else on the element."""
        if self.attribute is None:
            element.text = None
        else:
            element.attrib.pop(self.attribute, None)


@dataclass(frozen=True)
class Rewrite:
    """
    One rc.xml value a version replaces. `stale` is what `source` must still hold
    for the rewrite to apply, so a value the user changed themselves is left
    alone, and `value` is what replaces it.

    `destination` moves the value: leave it out, or give the same target as
    `source`, and the value is rewritten where it stands. A destination of the
    same depth and tags re-addresses the element and its ancestors, which is how
    a keybind changes its bridge id, its action or the attribute holding the
    value. Any other destination reparents the element, creating what the new
    path needs.
    """

    source: Target
    stale: str
    value: str
    destination: Target | None = None

    @property
    def moves(self) -> bool:
        return self.destination is not None and self.destination != self.source

    def apply(self, root: Et.Element) -> bool:
        """Rewrite every element `source` matches that still holds `stale`; True when any did"""
        changed = False

        for element in root.findall(self.source.path):
            # Any other value is the user's own, or a rewrite already applied
            if self.source.read(element) != self.stale:
                continue

            if self.destination is not None and self.moves:
                self.relocate(root, element, self.destination)
            else:
                self.source.write(element, self.value)

            changed = True
            log.info(self.describe())

        return changed

    def relocate(
        self, root: Et.Element, element: Et.Element, destination: Target
    ) -> None:
        """Carry `element` and its value over to `destination`."""
        source_steps = self.source.steps
        destination_steps = destination.steps
        parent_map = parents(root)

        same_shape = len(source_steps) == len(destination_steps) and all(
            parse_step(source)[0] == parse_step(target)[0]
            for source, target in zip(source_steps, destination_steps)
        )

        if same_shape:
            # Only the predicates differ, so the element and the ancestors the
            # path names are re-addressed where they already sit
            chain = [element]
            for _ in source_steps[1:]:
                chain.append(parent_map[chain[-1]])

            for node, step in zip(reversed(chain), destination_steps):
                tag, attribs = parse_step(step)
                node.tag = tag
                node.attrib.update(attribs)
        else:
            parent_map[element].remove(element)
            tag, attribs = parse_step(destination_steps[-1])
            element.tag = tag
            element.attrib.update(attribs)
            resolve(root, destination_steps[:-1]).append(element)

        # The value may have moved to another attribute on the same element
        if destination.attribute != self.source.attribute:
            self.source.clear(element)

        destination.write(element, self.value)

    def describe(self) -> str:
        where = f"{self.source.path} {self.source.held_in}"
        if self.moves and self.destination is not None:
            where += f" to {self.destination.path} {self.destination.held_in}"
            return f"Moved {where}, '{self.stale}' to '{self.value}'"
        return f"Set {where} from '{self.stale}' to '{self.value}'"


# Keyed by the rc.xml version that introduced the change; a config is brought up
# to date by applying every version above its own, oldest first
REWRITES: dict[int, tuple[Rewrite, ...]] = {
    4: (
        Rewrite(
            source=Target(
                path="./keyboard/keybind[@bridge='wm.keybindings/maximize-horizontally']"
                "/action[@name='Maximize']",
                attribute="direction",
            ),
            stale="right",
            value="horizontal",
        ),
        Rewrite(
            source=Target(
                path="./keyboard/keybind[@bridge='wm.keybindings/maximize-vertically']"
                "/action[@name='Maximize']",
                attribute="direction",
            ),
            stale="left",
            value="vertical",
        ),
    ),
}
