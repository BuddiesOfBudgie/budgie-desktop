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
import unittest
import xml.etree.ElementTree as Et

from labwc_bridge.migrations.rewrites import (
    REWRITES,
    Rewrite,
    Target,
    parents,
    parse_step,
    resolve,
    split_path,
)

HORIZONTALLY = (
    "./keyboard/keybind[@bridge='wm.keybindings/maximize-horizontally']"
    "/action[@name='Maximize']"
)
VERTICALLY = HORIZONTALLY.replace("horizontally", "vertically")

# Shaped like the rc.xml 10.10.2 shipped, cut down to what the rewrites touch
RC_XML = """<labwc_config version="1">
	<keyboard>
		<numlock>off</numlock>
		<keybind bridge="wm.keybindings/maximize-horizontally" key="undefined">
			<action name="Maximize" direction="right" />
		</keybind>
		<keybind bridge="wm.keybindings/maximize-vertically" key="undefined">
			<action name="Maximize" direction="left" />
		</keybind>
		<keybind bridge="wm.keybindings/maximize" key="W-Up">
			<action name="Maximize" direction="both" />
		</keybind>
		<keybind key="W-Left">
			<action name="SnapToEdge" direction="left" />
		</keybind>
	</keyboard>
	<focus>
		<followMouse>no</followMouse>
	</focus>
</labwc_config>"""


def setUpModule() -> None:
    # Every applied rewrite logs a line; the tests assert on the tree instead
    logging.disable(logging.INFO)


def tearDownModule() -> None:
    logging.disable(logging.NOTSET)


def rc() -> Et.Element:
    return Et.fromstring(RC_XML)


def find(element: Et.Element, path: str) -> Et.Element:
    """The element at `path`, failing the test rather than returning None."""
    found = element.find(path)
    if found is None:
        raise AssertionError(f"no element at '{path}'")
    return found


class SplitPathTest(unittest.TestCase):
    def test_drops_the_leading_current_element(self):
        self.assertEqual(split_path("./keyboard/numlock"), ["keyboard", "numlock"])

    def test_keeps_a_slash_inside_a_predicate(self):
        self.assertEqual(
            split_path(HORIZONTALLY),
            [
                "keyboard",
                "keybind[@bridge='wm.keybindings/maximize-horizontally']",
                "action[@name='Maximize']",
            ],
        )

    def test_handles_several_predicates_on_one_step(self):
        self.assertEqual(
            split_path("./a/b[@one='x'][@two='y/z']/c"),
            ["a", "b[@one='x'][@two='y/z']", "c"],
        )


class ParseStepTest(unittest.TestCase):
    def test_bare_tag_has_no_attributes(self):
        self.assertEqual(parse_step("numlock"), ("numlock", {}))

    def test_predicate_becomes_an_attribute(self):
        self.assertEqual(
            parse_step("action[@name='Maximize']"), ("action", {"name": "Maximize"})
        )

    def test_predicate_value_may_hold_a_slash(self):
        self.assertEqual(
            parse_step("keybind[@bridge='wm.keybindings/maximize']"),
            ("keybind", {"bridge": "wm.keybindings/maximize"}),
        )

    def test_several_predicates(self):
        self.assertEqual(
            parse_step("font[@place='ActiveWindow'][@weight='Bold']"),
            ("font", {"place": "ActiveWindow", "weight": "Bold"}),
        )


class ParentsTest(unittest.TestCase):
    def test_maps_each_element_to_its_parent(self):
        root = rc()
        keyboard = find(root, "./keyboard")
        numlock = find(root, "./keyboard/numlock")

        parent_map = parents(root)

        self.assertIs(parent_map[numlock], keyboard)
        self.assertIs(parent_map[keyboard], root)
        self.assertNotIn(root, parent_map)


class ResolveTest(unittest.TestCase):
    def test_returns_an_element_that_is_already_there(self):
        root = rc()

        resolved = resolve(root, ["keyboard", "numlock"])

        self.assertIs(resolved, find(root, "./keyboard/numlock"))

    def test_creates_what_is_missing_with_its_predicate_attributes(self):
        root = rc()

        created = resolve(root, ["mouse", "context[@name='Root']"])

        self.assertEqual(created.tag, "context")
        self.assertEqual(created.get("name"), "Root")
        self.assertIsNotNone(root.find("./mouse/context[@name='Root']"))


class TargetTest(unittest.TestCase):
    def test_reads_an_attribute(self):
        action = find(rc(), HORIZONTALLY)

        target = Target(path=HORIZONTALLY, attribute="direction")

        self.assertEqual(target.read(action), "right")

    def test_reads_a_missing_attribute_as_empty(self):
        action = find(rc(), HORIZONTALLY)

        target = Target(path=HORIZONTALLY, attribute="axis")

        self.assertEqual(target.read(action), "")

    def test_reads_element_text_without_surrounding_whitespace(self):
        numlock = Et.fromstring("<numlock>\n\toff\n</numlock>")

        self.assertEqual(Target(path="./keyboard/numlock").read(numlock), "off")

    def test_writes_an_attribute_and_text(self):
        root = rc()
        action = find(root, HORIZONTALLY)
        numlock = find(root, "./keyboard/numlock")

        Target(path=HORIZONTALLY, attribute="direction").write(action, "horizontal")
        Target(path="./keyboard/numlock").write(numlock, "on")

        self.assertEqual(action.get("direction"), "horizontal")
        self.assertEqual(numlock.text, "on")

    def test_clear_drops_the_attribute_and_the_text(self):
        root = rc()
        action = find(root, HORIZONTALLY)
        numlock = find(root, "./keyboard/numlock")

        Target(path=HORIZONTALLY, attribute="direction").clear(action)
        Target(path="./keyboard/numlock").clear(numlock)

        self.assertNotIn("direction", action.attrib)
        self.assertIsNone(numlock.text)


class RewriteInPlaceTest(unittest.TestCase):
    def rewrite(self, stale: str = "right", value: str = "horizontal") -> Rewrite:
        return Rewrite(
            source=Target(path=HORIZONTALLY, attribute="direction"),
            stale=stale,
            value=value,
        )

    def test_replaces_the_stale_value(self):
        root = rc()

        self.assertTrue(self.rewrite().apply(root))
        self.assertEqual(find(root, HORIZONTALLY).get("direction"), "horizontal")

    def test_is_a_no_op_once_applied(self):
        root = rc()
        self.rewrite().apply(root)

        self.assertFalse(self.rewrite().apply(root))
        self.assertEqual(find(root, HORIZONTALLY).get("direction"), "horizontal")

    def test_leaves_a_value_the_user_chose_alone(self):
        root = rc()
        find(root, HORIZONTALLY).set("direction", "both")

        self.assertFalse(self.rewrite().apply(root))
        self.assertEqual(find(root, HORIZONTALLY).get("direction"), "both")

    def test_reports_nothing_when_the_path_matches_nothing(self):
        root = rc()
        before = Et.tostring(root)

        rewrite = Rewrite(
            source=Target(path="./snapping/range", attribute="inner"),
            stale="10",
            value="20",
        )

        self.assertFalse(rewrite.apply(root))
        self.assertEqual(Et.tostring(root), before)

    def test_applies_to_every_element_the_path_matches(self):
        root = rc()

        rewrite = Rewrite(
            source=Target(
                path="./keyboard/keybind/action[@name='Maximize']",
                attribute="direction",
            ),
            stale="both",
            value="all",
        )

        self.assertTrue(rewrite.apply(root))
        directions = [
            action.get("direction")
            for action in root.findall("./keyboard/keybind/action[@name='Maximize']")
        ]
        self.assertEqual(directions, ["right", "left", "all"])

    def test_rewrites_element_text(self):
        root = rc()

        rewrite = Rewrite(
            source=Target(path="./keyboard/numlock"), stale="off", value="on"
        )

        self.assertTrue(rewrite.apply(root))
        self.assertEqual(root.findtext("./keyboard/numlock"), "on")


class RewriteMoveTest(unittest.TestCase):
    def test_a_destination_equal_to_the_source_does_not_move(self):
        root = rc()
        source = Target(path=HORIZONTALLY, attribute="direction")

        rewrite = Rewrite(
            source=source, destination=source, stale="right", value="horizontal"
        )

        self.assertFalse(rewrite.moves)
        self.assertTrue(rewrite.apply(root))
        self.assertEqual(find(root, HORIZONTALLY).get("direction"), "horizontal")

    def test_moves_the_value_to_another_attribute_on_the_same_element(self):
        root = rc()

        rewrite = Rewrite(
            source=Target(path=HORIZONTALLY, attribute="direction"),
            destination=Target(path=HORIZONTALLY, attribute="axis"),
            stale="right",
            value="horizontal",
        )

        self.assertTrue(rewrite.apply(root))
        action = find(root, HORIZONTALLY)
        self.assertEqual(action.get("axis"), "horizontal")
        self.assertNotIn("direction", action.attrib)

    def test_moves_to_a_new_action_name_and_attribute(self):
        root = rc()
        renamed = HORIZONTALLY.replace("'Maximize'", "'MaximizeAxis'")

        rewrite = Rewrite(
            source=Target(path=HORIZONTALLY, attribute="direction"),
            destination=Target(path=renamed, attribute="axis"),
            stale="right",
            value="horizontal",
        )

        self.assertTrue(rewrite.apply(root))
        self.assertIsNone(root.find(HORIZONTALLY))
        action = find(root, renamed)
        self.assertEqual(action.get("axis"), "horizontal")
        self.assertNotIn("direction", action.attrib)

    def test_moves_a_keybind_to_a_new_bridge_id(self):
        root = rc()
        rebridged = HORIZONTALLY.replace("maximize-horizontally", "maximize-horizontal")

        rewrite = Rewrite(
            source=Target(path=HORIZONTALLY, attribute="direction"),
            destination=Target(path=rebridged, attribute="direction"),
            stale="right",
            value="horizontal",
        )

        self.assertTrue(rewrite.apply(root))
        self.assertIsNone(root.find(HORIZONTALLY))
        self.assertEqual(find(root, rebridged).get("direction"), "horizontal")

        # The key the user had bound rides along with the keybind
        keybind = find(
            root, "./keyboard/keybind[@bridge='wm.keybindings/maximize-horizontal']"
        )
        self.assertEqual(keybind.get("key"), "undefined")

    def test_reparents_into_a_section_that_does_not_exist_yet(self):
        root = rc()

        rewrite = Rewrite(
            source=Target(path="./focus/followMouse"),
            destination=Target(path="./mouse/followMouse"),
            stale="no",
            value="yes",
        )

        self.assertTrue(rewrite.apply(root))
        self.assertIsNone(root.find("./focus/followMouse"))
        self.assertEqual(root.findtext("./mouse/followMouse"), "yes")

    def test_moves_element_text_onto_an_attribute(self):
        root = rc()

        rewrite = Rewrite(
            source=Target(path="./keyboard/numlock"),
            destination=Target(path="./keyboard/numlock", attribute="state"),
            stale="off",
            value="on",
        )

        self.assertTrue(rewrite.apply(root))
        numlock = find(root, "./keyboard/numlock")
        self.assertEqual(numlock.get("state"), "on")
        self.assertIsNone(numlock.text)

    def test_does_not_move_when_the_value_is_not_stale(self):
        root = rc()
        before = Et.tostring(root)

        rewrite = Rewrite(
            source=Target(path=HORIZONTALLY, attribute="direction"),
            destination=Target(path=HORIZONTALLY, attribute="axis"),
            stale="left",
            value="vertical",
        )

        self.assertFalse(rewrite.apply(root))
        self.assertEqual(Et.tostring(root), before)


class RewriteTableTest(unittest.TestCase):
    """The rewrites this release actually ships."""

    def apply_all(self, root: Et.Element) -> bool:
        applied = False
        for version in sorted(REWRITES):
            for rewrite in REWRITES[version]:
                applied |= rewrite.apply(root)
        return applied

    def test_corrects_both_maximize_directions(self):
        root = rc()

        self.assertTrue(self.apply_all(root))
        self.assertEqual(find(root, HORIZONTALLY).get("direction"), "horizontal")
        self.assertEqual(find(root, VERTICALLY).get("direction"), "vertical")

    def test_leaves_maximize_both_and_other_actions_alone(self):
        root = rc()
        self.apply_all(root)

        both = find(root, "./keyboard/keybind[@bridge='wm.keybindings/maximize']/action")
        snap = find(root, "./keyboard/keybind[@key='W-Left']/action")

        self.assertEqual(both.get("direction"), "both")
        self.assertEqual(snap.get("direction"), "left")

    def test_is_idempotent(self):
        root = rc()
        self.apply_all(root)

        self.assertFalse(self.apply_all(root))


if __name__ == "__main__":
    unittest.main()
