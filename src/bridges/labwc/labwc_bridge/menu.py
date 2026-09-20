# This file is part of budgie-desktop
#
# Copyright Budgie Desktop Developers
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

import gettext
import xml.etree.ElementTree as Et

from .config import save


def translate_menu_labels(source: str, destination: str) -> None:
    """Writes `source` to `destination` with every root menu item label translated."""
    menuet = Et.parse(source)

    # first scan the config file to find any custom entries.
    matches = menuet.findall("./menu/item[@label]")

    gettext.bindtextdomain("budgie-desktop", "/usr/share/locale")
    gettext.textdomain("budgie-desktop")

    # look for labels and translate them
    # we save the original translation string with the menu and use that
    # so we can retranslate if the locale changes
    for matched in matches:
        if "original" in matched.attrib:
            label = matched.attrib["original"]
        else:
            label = matched.attrib["label"]
            matched.attrib["original"] = label

        translated = gettext.gettext(label)
        matched.attrib["label"] = translated

    save(menuet, destination)
