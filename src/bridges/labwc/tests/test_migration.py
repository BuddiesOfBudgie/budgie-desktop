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
import tempfile
import unittest
import xml.etree.ElementTree as Et
from pathlib import Path
from unittest import mock

from labwc_bridge.config import LabwcConfig
from labwc_bridge.migrations import migration
from labwc_bridge.migrations.rewrites import REWRITES, Rewrite, Target

SHIPPED_RC = Path(__file__).resolve().parent.parent / "rc.xml"

RC_XML = """<labwc_config version="1">
	<keyboard>
		<keybind bridge="wm.keybindings/maximize-horizontally" key="undefined">
			<action name="Maximize" direction="right" />
		</keybind>
		<keybind bridge="wm.keybindings/maximize-vertically" key="undefined">
			<action name="Maximize" direction="left" />
		</keybind>
	</keyboard>
</labwc_config>"""

TEMPLATE_XML = """<labwc_config version="4">
	<keyboard>
		<numlock>off</numlock>
	</keyboard>
</labwc_config>"""


def setUpModule() -> None:
    logging.disable(logging.INFO)


def tearDownModule() -> None:
    logging.disable(logging.NOTSET)


def tree(xml: str) -> Et.ElementTree[Et.Element]:
    root: Et.Element = Et.fromstring(xml)
    return Et.ElementTree(root)


def subject_for(xml: str) -> migration.RcXmlMigration:
    return migration.RcXmlMigration(LabwcConfig(tree(xml), "rc.xml"))


def find(element: Et.Element, path: str) -> Et.Element:
    """The element at `path`, failing the test rather than returning None."""
    found = element.find(path)
    if found is None:
        raise AssertionError(f"no element at '{path}'")
    return found


class RcVersionTest(unittest.TestCase):
    def test_a_config_with_no_version_reads_as_zero(self):
        subject = subject_for("<labwc_config><keyboard /></labwc_config>")

        self.assertEqual(subject.get_rc_version(subject.config.et), 0)

    def test_an_older_config_needs_migrating(self):
        self.assertTrue(subject_for(RC_XML).needs_migration())

    def test_a_current_config_does_not(self):
        current = RC_XML.replace(
            'version="1"', f'version="{migration.CURRENT_RC_VERSION}"'
        )

        self.assertFalse(subject_for(current).needs_migration())

    def test_an_unreadable_version_is_not_migrated(self):
        subject = subject_for('<labwc_config version="latest" />')

        self.assertFalse(subject.needs_migration())


class ApplyRewritesTest(unittest.TestCase):
    """The walk over the versions, driven by a table of this test's own."""

    def setUp(self):
        self.subject = subject_for(RC_XML)

    def counter(self, version: int) -> Rewrite:
        """A rewrite that advances <numlock> from the version before it to its own."""
        return Rewrite(
            source=Target(path="./keyboard/numlock"),
            stale=str(version - 1),
            value=str(version),
        )

    def counted(self, et: Et.ElementTree[Et.Element], start: str) -> Et.ElementTree[Et.Element]:
        Et.SubElement(find(et.getroot(), "./keyboard"), "numlock").text = start
        return et

    def test_runs_every_version_above_the_config_oldest_first(self):
        et = self.counted(tree(RC_XML), "1")
        table = {2: (self.counter(2),), 3: (self.counter(3),)}

        with mock.patch.object(migration, "REWRITES", table):
            self.assertTrue(self.subject.apply_rewrites(et, 1))

        # Only a 1 -> 2 -> 3 walk in order reaches 3
        self.assertEqual(et.getroot().findtext("./keyboard/numlock"), "3")

    def test_skips_versions_at_or_below_the_config(self):
        et = self.counted(tree(RC_XML), "2")
        table = {2: (self.counter(2),), 3: (self.counter(3),)}

        with mock.patch.object(migration, "REWRITES", table):
            self.assertTrue(self.subject.apply_rewrites(et, 2))

        self.assertEqual(et.getroot().findtext("./keyboard/numlock"), "3")

    def test_a_current_config_has_nothing_to_apply(self):
        et = self.counted(tree(RC_XML), "1")
        table = {2: (self.counter(2),)}

        with mock.patch.object(migration, "REWRITES", table):
            self.assertFalse(self.subject.apply_rewrites(et, 2))

        self.assertEqual(et.getroot().findtext("./keyboard/numlock"), "1")

    def test_corrects_the_maximize_directions_of_every_older_config(self):
        for version in range(migration.CURRENT_RC_VERSION):
            with self.subTest(version=version):
                et = tree(RC_XML)

                self.assertTrue(self.subject.apply_rewrites(et, version))

                directions = [
                    action.get("direction")
                    for action in et.getroot().findall("./keyboard/keybind/action")
                ]
                self.assertEqual(directions, ["horizontal", "vertical"])

    def test_a_config_already_at_the_current_version_is_left_alone(self):
        et = tree(RC_XML)

        applied = self.subject.apply_rewrites(et, migration.CURRENT_RC_VERSION)

        self.assertFalse(applied)


class MigrateTest(unittest.TestCase):
    """The whole run, against a config on disk."""

    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.path = Path(directory.name) / "rc.xml"
        self.path.write_text(RC_XML)
        self.subject = migration.RcXmlMigration(LabwcConfig(tree(RC_XML), str(self.path)))

    def written(self) -> Et.Element:
        return Et.parse(self.path).getroot()

    def directions(self, root: Et.Element) -> list[str | None]:
        return [
            action.get("direction")
            for action in root.findall("./keyboard/keybind/action")
        ]

    def with_template(self, xml: str | None = TEMPLATE_XML):
        """load_template reads the system data dirs, which a test cannot rely on."""
        template = None if xml is None else tree(xml)
        return mock.patch.object(
            migration.RcXmlMigration, "load_template", return_value=template
        )

    def test_records_the_current_version(self):
        with self.with_template():
            self.assertTrue(self.subject.migrate())

        self.assertEqual(
            self.written().get("version"), str(migration.CURRENT_RC_VERSION)
        )

    def test_aborts_without_recording_a_version_when_there_is_no_template(self):
        with self.with_template(None):
            self.assertFalse(self.subject.migrate())

        # Nothing was written, so the next start finds the config as it was
        self.assertEqual(self.path.read_text(), RC_XML)

    def test_aborts_without_recording_a_version_when_the_merge_fails(self):
        with self.with_template(), mock.patch.object(
            migration.RcXmlMigration, "replace_keyboard_section", return_value=False
        ):
            self.assertFalse(self.subject.migrate())

        self.assertEqual(self.path.read_text(), RC_XML)

    def test_writes_the_rewritten_values(self):
        with self.with_template():
            self.subject.migrate()

        self.assertEqual(self.directions(self.written()), ["horizontal", "vertical"])

    def test_backs_the_config_up_before_writing(self):
        with self.with_template():
            self.subject.migrate()

        backup = Et.parse(str(self.path) + ".backup").getroot()
        self.assertEqual(backup.get("version"), "1")
        self.assertEqual(self.directions(backup), ["right", "left"])

    def test_leaves_the_config_alone_when_the_backup_fails(self):
        with mock.patch.object(
            migration.RcXmlMigration, "backup_user_config", return_value=False
        ):
            self.assertFalse(self.subject.migrate())

        self.assertEqual(self.path.read_text(), RC_XML)

    def test_a_migrated_config_no_longer_needs_migrating(self):
        with self.with_template():
            self.subject.migrate()

        self.assertFalse(self.subject.needs_migration())


class ShippedConfigTest(unittest.TestCase):
    def test_the_shipped_rc_xml_is_at_the_current_version(self):
        """
        A fresh install copies this file verbatim. A version below the constant
        would migrate configs that are already current; one above would skip every
        rewrite a later version adds.
        """
        shipped = Et.parse(SHIPPED_RC).getroot().get("version")

        self.assertEqual(shipped, str(migration.CURRENT_RC_VERSION))

    def test_every_rewrite_is_keyed_at_or_below_the_current_version(self):
        for version in REWRITES:
            with self.subTest(version=version):
                self.assertLessEqual(version, migration.CURRENT_RC_VERSION)


if __name__ == "__main__":
    unittest.main()
