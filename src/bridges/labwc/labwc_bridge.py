#!/usr/bin/env python3
# This file is part of budgie-desktop
#
# Copyright Budgie Desktop Developers
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

import signal
import xml.etree.ElementTree as Et
import os
import shutil
import subprocess
import logging
from systemd.journal import JournalHandler
import psutil
import sys
import gettext
from enum import StrEnum
import dbus
import dbus.mainloop.glib

import gi
from gi.repository import Gio, GLib
gi.require_version('Pango', '1.0')
from gi.repository import Pango

mainloop = None

CURRENT_RC_VERSION = 1

def read_key_value_file(filepath, strip_quotes=False):
    """
    Read a key=value config file into a dict.

    Args:
        filepath: Path to config file
        strip_quotes: If True, remove surrounding quotes from values

    Returns:
        Dict of key-value pairs
    """
    config = {}

    if not os.path.exists(filepath):
        return config

    try:
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    if strip_quotes:
                        value = value.strip('"').strip("'")
                    config[key] = value
    except Exception:
        pass

    return config


def parse_options_string(options_string):
    """Parse comma-separated options into a set."""
    if not options_string:
        return set()
    return {opt.strip() for opt in options_string.split(',') if opt.strip()}


def normalize_xkb_options(options_set):
    """
    Normalize XKB options to avoid conflicts.
    Only certain option families are mutually exclusive
    Other families like lv3:, compose: can have multiple options.

    Known mutually-exclusive families: grp, caps, ctrl, altwin

    Args:
        options_set: Set of XKB option strings

    Returns:
        Set of normalized options
    """
    if not options_set:
        return set()

    # Families where only one option should be kept
    exclusive_families = {'grp', 'caps', 'ctrl', 'altwin'}

    seen_exclusive = {}
    normalized = set()

    for option in sorted(options_set):  # Sort for consistent behavior
        if ':' in option:
            family = option.split(':', 1)[0]

            if family in exclusive_families:
                # Keep only first of exclusive families
                if family not in seen_exclusive:
                    seen_exclusive[family] = option
                    normalized.add(option)
                # else: skip duplicate exclusive family
            else:
                # Non-exclusive family - keep all
                normalized.add(option)
        else:
            # Options without family (rare) - keep all
            normalized.add(option)

    return normalized


def format_keyboard_layout(layout, variant=''):
    """
    Convert layout and variant strings to labwc format.

    Args:
        layout: Comma-separated layout string
        variant: Comma-separated variant string

    Returns:
        Formatted layout string or None if no layout
    """
    if not layout:
        return None

    if not variant:
        return layout

    variants = variant.split(',')
    layouts = layout.split(',')

    combined = []
    for i, l in enumerate(layouts):
        if i < len(variants) and variants[i]:
            combined.append(f"{l}({variants[i]})")
        else:
            combined.append(l)

    return ','.join(combined)


def get_locale1_all_properties(dbus_bus, log=None):
    """
    Get all properties from org.freedesktop.locale1.

    Args:
        dbus_bus: D-Bus system bus connection
        log: Optional logger

    Returns:
        Dict of properties or None if service unavailable
    """
    if not dbus_bus:
        return None

    try:
        proxy = dbus_bus.get_object(
            'org.freedesktop.locale1',
            '/org/freedesktop/locale1'
        )

        props_iface = dbus.Interface(
            proxy,
            'org.freedesktop.DBus.Properties'
        )

        return props_iface.GetAll('org.freedesktop.locale1')

    except dbus.DBusException as e:
        if log:
            log.debug(f"Could not read locale1 properties: {e}")
        return None


class RcXmlMigration:
    """Handles migration of rc.xml to newer versions"""

    def __init__(self, bridge):
        self.bridge = bridge
        self.log = bridge.log

    def get_rc_version(self, et):
        """Get the version number from rc.xml root element"""
        root = et.getroot()
        version = root.get('version')
        if version is None:
            return 0  # No version means old/original format
        return int(version)

    def needs_migration(self):
        """Check if user's rc.xml needs migration"""
        try:
            user_version = self.get_rc_version(self.bridge.et)
            return user_version < CURRENT_RC_VERSION
        except:
            return False

    def backup_user_config(self):
        """Create backup of user's current rc.xml"""
        user_path = self.bridge.user_config()
        backup_path = user_path + ".backup"

        try:
            shutil.copy2(user_path, backup_path)
            self.log.info(f"Backed up rc.xml to {backup_path}")
            return True
        except Exception as e:
            self.log.error(f"Failed to backup rc.xml: {e}")
            return False

    def load_template(self):
        """Load the new template rc.xml from system data dirs"""
        for system_dir in GLib.get_system_data_dirs():
            # Check for distro-specific template first
            template_path = os.path.join(system_dir, "budgie-desktop", "labwc", "distro-rc.xml")
            if os.path.isfile(template_path):
                try:
                    return Et.parse(template_path)
                except Exception as e:
                    self.log.warning(f"Cannot parse distro template {template_path}: {e}")

            # Fall back to standard template
            template_path = os.path.join(system_dir, "budgie-desktop", "labwc", "rc.xml")
            if os.path.isfile(template_path):
                try:
                    return Et.parse(template_path)
                except Exception as e:
                    self.log.warning(f"Cannot parse template {template_path}: {e}")

        self.log.error("Could not find rc.xml template")
        return None

    def replace_keyboard_section(self, user_et, template_et):
        """Replace only the keyboard section from user config with template version"""
        user_root = user_et.getroot()
        template_root = template_et.getroot()

        # Find and remove old keyboard section from user config
        old_keyboard = user_root.find('./keyboard')
        if old_keyboard is not None:
            user_root.remove(old_keyboard)

        # Find keyboard section in template
        template_keyboard = template_root.find('./keyboard')
        if template_keyboard is None:
            self.log.error("Template has no keyboard section")
            return False

        # Deep copy the template keyboard section
        # We need to find the right position to insert it
        # Typically keyboard comes after desktops but before theme
        # Let's try to maintain reasonable ordering

        # Find insertion point - try to insert before theme element
        theme_element = user_root.find('./theme')
        if theme_element is not None:
            insert_index = list(user_root).index(theme_element)
            user_root.insert(insert_index, template_keyboard)
        else:
            # If no theme element, try before windowRules
            windowrules_element = user_root.find('./windowRules')
            if windowrules_element is not None:
                insert_index = list(user_root).index(windowrules_element)
                user_root.insert(insert_index, template_keyboard)
            else:
                # Just append at the end if we can't find a good spot
                user_root.append(template_keyboard)

        self.log.info("Replaced keyboard section with template version")
        return True

    def migrate(self):
        """Perform the migration - replace keyboard section only"""
        self.log.info("Starting rc.xml migration - replacing keyboard section only")

        # Step 1: Backup current config
        if not self.backup_user_config():
            self.log.error("Migration aborted - backup failed")
            return False

        # Step 2: Load template
        template_et = self.load_template()
        if template_et is None:
            self.log.error("Migration aborted - no template found")
            return False

        # Step 3: Replace keyboard section in user's config
        user_et = self.bridge.et
        if not self.replace_keyboard_section(user_et, template_et):
            self.log.error("Migration aborted - failed to replace keyboard section")
            return False

        # Step 4: Set version number on user config
        user_root = user_et.getroot()
        user_root.set('version', str(CURRENT_RC_VERSION))

        # Step 5: Write updated config
        user_path = self.bridge.user_config()

        # Ensure directory exists
        os.makedirs(os.path.dirname(user_path), exist_ok=True)

        # Write updated config
        Et.indent(user_et, space="\t", level=0)
        user_et.write(user_path)

        return True


class Bridge:

    # element tree to read/write
    et = None
    menuet = None

    # gsettings connections
    panel_settings = None
    gsd_media_keys_settings = None
    desktop_wm_keybindings_settings = None
    desktop_wm_preferences_settings = None
    mutter_keybindings_settings = None
    desktop_interface_settings = None
    mutter_settings = None
    budgie_wm_settings = None
    desktop_input_sources_settings = None
    custom_keys_settings = None
    default_terminal_settings= None

    # flag to indicate delaying writing the config until its true
    # this is needed where multiple bridge set config calls could potentially
    # call labwc -r multiple times

    delay_config_write = False

    # this is our logger
    log = None

    def sigint_handler(self, sig, frame):
        if sig == signal.SIGINT:
            mainloop=quit()

    def user_config(self, config_file="rc.xml"):
        return os.path.join(GLib.get_user_config_dir(), "budgie-desktop", "labwc", config_file)

    # writes the labwc rc.xml file back
    def write_config(self):
        # Write back to file
        if self.delay_config_write:
            return

        path = self.user_config()
        Et.indent(self.et, space="\t", level=0)
        self.et.write(path)

        # reload config for labwc
        subprocess.call("labwc -r", shell=True)

    def search_for_config(self, config_file):
        # Check if a local labwc config_file exists - if doesn't
        # use the budgie-desktop shared file - or the distro variant if it exists
        # to populate the local labwc config folder

        search_path = [self.user_config(config_file)]
        for system_dir in GLib.get_system_data_dirs():
            search_path.append(os.path.join(system_dir, "budgie-desktop", "distro-"+config_file))
            search_path.append(os.path.join(system_dir, "budgie-desktop", config_file))

        path = ""
        for path in search_path:
            if os.path.isfile(path):
                break

        if path == "":
            self.log.critical("Could not find an existing "+config_file+" or a shipped budgie equivalent")
            return None, None

        return path, search_path

    # starting point for the bridge
    def __init__(self):
        # Initialize dbus mainloop FIRST
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)

        self.log = logging.getLogger('labwc_bridge')
        self.log.addHandler(JournalHandler())

        path, search_path = self.search_for_config("menu.xml")
        if path == None:
            return

        try:
            self.menuet = Et.parse(source=path)
        except Exception as e:
            self.log.warning("Cannot parse " + path + ":\n")
            self.log.warning(e)
            return

        self.translate_menu_labels(search_path[0])

        path,search_path = self.search_for_config("rc.xml")
        if path == None:
            return

        try:
            self.et = Et.parse(source=path)
        except Exception as e:
            self.log.warning("Cannot parse " + path + ":\n")
            self.log.warning(e)
            return

        # Check if migration is needed
        migration = RcXmlMigration(self)
        if migration.needs_migration():
            self.log.info("Old rc.xml format detected, performing migration")
            if not migration.migrate():
                self.log.error("Migration failed, continuing with current config")

        signal.signal(signal.SIGINT, self.sigint_handler)

        # this is the heart of the bridge - connect all the recognised gsetting schemas
        # that we will listen to and respond to changes
        self.panel_settings = Gio.Settings.new('com.solus-project.budgie-panel')
        self.panel_settings.connect('changed', self.panel_settings_changed)

        self.gsd_media_keys_settings = Gio.Settings.new('org.buddiesofbudgie.settings-daemon.plugins.media-keys')
        self.gsd_media_keys_settings.connect('changed', self.keybindings_changed)

        self.desktop_wm_keybindings_settings = Gio.Settings.new('org.gnome.desktop.wm.keybindings')
        self.desktop_wm_keybindings_settings.connect('changed', self.keybindings_changed)

        self.desktop_wm_preferences_settings = Gio.Settings.new('org.gnome.desktop.wm.preferences')
        self.desktop_wm_preferences_settings.connect('changed', self.desktop_wm_preferences_changed)

        self.mutter_keybindings_settings = Gio.Settings.new('org.gnome.mutter.keybindings')
        self.mutter_keybindings_settings.connect('changed', self.keybindings_changed)

        self.desktop_interface_settings = Gio.Settings.new('org.gnome.desktop.interface')
        self.desktop_interface_settings.connect('changed', self.desktop_interface_changed)

        self.mutter_settings = Gio.Settings.new('org.gnome.mutter')
        self.mutter_settings.connect('changed', self.mutter_changed)

        self.budgie_wm_settings = Gio.Settings.new('com.solus-project.budgie-wm')
        self.budgie_wm_settings.connect('changed', self.budgie_wm_changed)

        self.desktop_input_sources_settings = Gio.Settings.new('org.gnome.desktop.input-sources')
        self.desktop_input_sources_settings.connect('changed', self.desktop_input_sources_changed)

        self.peripherals_mouse_settings = Gio.Settings.new('org.gnome.desktop.peripherals.mouse')
        self.peripherals_mouse_settings.connect('changed', self.peripherals_changed)

        self.peripherals_touchpad_settings = Gio.Settings.new('org.gnome.desktop.peripherals.touchpad')
        self.peripherals_touchpad_settings.connect('changed', self.peripherals_changed)

        self.peripherals_touchpad_settings.connect('changed::two-finger-scrolling-enabled', self.scrollmethod_changed)
        self.peripherals_touchpad_settings.connect('changed::edge-scrolling-enabled', self.scrollmethod_changed)

        self.default_terminal_settings = Gio.Settings.new('org.gnome.desktop.default-applications.terminal')
        self.default_terminal_settings.connect('changed', self.default_terminal_changed)

        # Setup locale1 monitoring for keyboard layout and locale
        self.setup_locale1_monitor()

        self.bridge_config()

    def setup_locale1_monitor(self):
        """Setup monitoring of org.freedesktop.locale1 using dbus-python"""
        try:
            # Get system bus
            bus = dbus.SystemBus()

            # Store bus for later use
            self.dbus_system_bus = bus

            # Subscribe to PropertiesChanged signals
            bus.add_signal_receiver(
                self.on_locale1_properties_changed,
                signal_name='PropertiesChanged',
                dbus_interface='org.freedesktop.DBus.Properties',
                path='/org/freedesktop/locale1',
                arg0='org.freedesktop.locale1'
            )

        except Exception as e:
            self.log.warning(f"Could not setup locale1 monitoring: {e}")

    def on_locale1_properties_changed(self, interface, changed, invalidated):
        """
        Handler for PropertiesChanged signals from locale1.
        Signature (s, a{sv}, as) -> interface name, changed dict, invalidated list
        """
        self.log.info(f"locale1 PropertiesChanged received for interface: {interface}")

        if changed:
            self.log.info("Changed properties:")
            for k, v in dict(changed).items():
                self.log.info(f"  {k}: {v}")

        if invalidated:
            self.log.info(f"Invalidated properties: {list(invalidated)}")

        # Update environment file with new locale/keyboard settings
        self.write_environment_file()

        # Reload labwc config if not delayed
        if not self.delay_config_write:
            subprocess.call("labwc -r", shell=True)

    def get_locale_from_locale1(self):
        """Get locale settings from systemd-localed via dbus-python"""
        locale_vars = {}

        if not hasattr(self, 'dbus_system_bus'):
            return locale_vars

        props = get_locale1_all_properties(self.dbus_system_bus, self.log)
        if not props:
            return locale_vars

        # The 'Locale' property is an array of strings like "LANG=en_US.UTF-8"
        if 'Locale' in props:
            locale_array = props['Locale']
            for locale_entry in locale_array:
                if '=' in locale_entry:
                    key, value = locale_entry.split('=', 1)
                    locale_vars[key] = value
                    self.log.debug(f"Got from locale1: {key}={value}")

        return locale_vars

    def get_keyboard_layout_from_locale1(self):
        """Get keyboard layout from systemd-localed"""
        layout_info = {
            'layout': None,
            'variant': None,
            'model': None,
            'options': None
        }

        if not hasattr(self, 'dbus_system_bus'):
            return layout_info

        props = get_locale1_all_properties(self.dbus_system_bus, self.log)
        if not props:
            return layout_info

        if 'X11Layout' in props:
            layout_info['layout'] = str(props['X11Layout'])
        if 'X11Variant' in props:
            layout_info['variant'] = str(props['X11Variant'])
        if 'X11Model' in props:
            layout_info['model'] = str(props['X11Model'])
        if 'X11Options' in props:
            layout_info['options'] = str(props['X11Options'])

        if layout_info['layout']:
            self.log.info(f"Got keyboard layout from locale1: {layout_info}")

        return layout_info

    def get_keyboard_layout_from_system_files(self):
        """
        Fallback: Read keyboard layout from /etc/default/keyboard
        """
        layout_info = {
            'layout': None,
            'variant': None,
            'model': None,
            'options': None
        }

        keyboard_config = read_key_value_file('/etc/default/keyboard', strip_quotes=True)

        if 'XKBLAYOUT' in keyboard_config:
            layout_info['layout'] = keyboard_config['XKBLAYOUT']
        if 'XKBVARIANT' in keyboard_config:
            layout_info['variant'] = keyboard_config['XKBVARIANT']
        if 'XKBMODEL' in keyboard_config:
            layout_info['model'] = keyboard_config['XKBMODEL']
        if 'XKBOPTIONS' in keyboard_config:
            layout_info['options'] = keyboard_config['XKBOPTIONS']

        if layout_info['layout']:
            self.log.info(f"Got keyboard layout from /etc/default/keyboard: {layout_info}")

        return layout_info

    def get_keyboard_layout(self):
        """
        Extract keyboard layout in this order:
        1. GSettings input-sources (if exists and non-empty)
        2. systemd-localed X11Layout (if exists and non-empty)
        3. /etc/default/keyboard XKBLAYOUT (if defined)
        4. Default to "us"
        """

        # GSettings input-sources (if exists and non-empty)
        if self.desktop_input_sources_settings:
            sources = self.desktop_input_sources_settings["sources"]
            layout_parts = []

            for source in sources:
                if source[0] == 'xkb':
                    extract = source[1].replace("'","")

                    if "+" in extract:
                        rhs = extract.split("+")
                        extract = f"{rhs[0]}({rhs[1]})"

                    layout_parts.append(extract)

            if layout_parts:
                layout = ','.join(layout_parts)
                self.log.info(f"Using keyboard layout from GSettings: {layout}")
                return layout

        # systemd-localed X11Layout (if exists and non-empty)
        locale1_layout = self.get_keyboard_layout_from_locale1()

        formatted = format_keyboard_layout(locale1_layout['layout'], locale1_layout['variant'])
        if formatted:
            self.log.info(f"Using keyboard layout from locale1: {formatted}")
            return formatted

        # /etc/default/keyboard XKBLAYOUT (if defined)
        system_layout = self.get_keyboard_layout_from_system_files()

        formatted = format_keyboard_layout(system_layout['layout'], system_layout['variant'])
        if formatted:
            self.log.info(f"Using keyboard layout from /etc/default/keyboard: {formatted}")
            return formatted

        # Default fallback
        self.log.info("Using default keyboard layout: us")
        return "us"

    def get_merged_xkb_options(self):
        """
        Get XKB options in this order with normalization:
        1. GSettings xkb-options (ONLY if user-modified)
        2. systemd-localed X11Options (if exists)
        3. /etc/default/keyboard XKBOPTIONS (if exists)
        4. GSettings default (if nothing else found)
        5. Empty otherwise

        Then normalize (remove duplicate families) and inject grp:alt_shift_toggle
        if multiple layouts and no grp: option exists.
        """
        options_set = set()
        gsettings_default = set()

        # GSettings xkb-options (if exists and non-empty)
        if self.desktop_input_sources_settings:
            try:
                user_value = self.desktop_input_sources_settings.get_user_value("xkb-options")

                if user_value is not None:
                    # User explicitly set it (even if empty)
                    gsettings_options = self.desktop_input_sources_settings.get_strv("xkb-options")
                    options_set = set(gsettings_options)
                    self.log.info(f"Using USER GSettings XKB options: {options_set}")
                else:
                    # Not user-modified → store default for possible fallback
                    gsettings_options = self.desktop_input_sources_settings.get_strv("xkb-options")
                    if gsettings_options:
                        gsettings_default = set(gsettings_options)
                    self.log.debug("GSettings xkb-options not user-modified")

            except Exception as e:
                self.log.debug(f"Could not read GSettings xkb-options: {e}")

        # systemd-localed X11Options (if not found in GSettings)
        if not options_set:
            locale1_layout = self.get_keyboard_layout_from_locale1()
            options_set = parse_options_string(locale1_layout.get('options', ''))
            if options_set:
                self.log.info(f"Got XKB options from locale1: {options_set}")

        # /etc/default/keyboard XKBOPTIONS (if not found above)
        if not options_set:
            system_layout = self.get_keyboard_layout_from_system_files()
            options_set = parse_options_string(system_layout.get('options', ''))
            if options_set:
                self.log.info(f"Got XKB options from /etc/default/keyboard: {options_set}")

        if not options_set and gsettings_default:
            options_set = gsettings_default
            self.log.info(f"Using DEFAULT GSettings XKB options: {options_set}")

        # Empty if nothing found
        if not options_set:
            self.log.info("No XKB options found from any source")
            options_set = set()

        # Normalize: remove duplicate option families (keep only first of each family)
        options_set = normalize_xkb_options(options_set)

        # Get current keyboard layout to check if multiple layouts
        current_layout = self.get_keyboard_layout()
        has_multiple_layouts = ',' in current_layout

        # Check if any grp: option exists
        has_grp_option = any(opt.startswith('grp:') for opt in options_set)

        # Inject default grp:alt_shift_toggle if multiple layouts and no grp: option
        if has_multiple_layouts and not has_grp_option:
            options_set.add('grp:alt_shift_toggle')
            self.log.info("Injected grp:alt_shift_toggle for multiple layouts")

        result = ','.join(sorted(options_set))
        self.log.info(f"Final XKB options: {result}")
        return result

    # this translate all menu labels if not already done
    def translate_menu_labels(self, path):
        root = self.menuet.getroot()

        # first scan the config file to find any custom entries.
        matches = self.menuet.findall('./menu/item[@label]')

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

        Et.indent(self.menuet, space="\t", level=0)
        self.menuet.write(path)

    # Helper method to ensure libinput structure exists for any peripheral
    def ensure_peripheral_element(self, category, element_name):
        """
        Ensure libinput/device/element structure exists for the given category.
        Returns the element, creating the full path if necessary.

        Args:
            category: 'touchpad' or 'non-touch'
            element_name: name of the element to find/create (e.g., 'scrollMethod', 'naturalScroll')

        Returns:
            The XML element
        """
        root = self.et.getroot()

        # Find or create libinput section
        libinput = root.find("./libinput")
        if libinput is None:
            libinput = Et.SubElement(root, "libinput")

        # Find or create device with specified category
        device = libinput.find(f"./device[@category='{category}']")
        if device is None:
            device = Et.SubElement(libinput, "device")
            device.attrib["category"] = category

        # Find or create the specific element
        element = device.find(f"./{element_name}")
        if element is None:
            element = Et.SubElement(device, element_name)

        return element

    # this manages scroll method changes for touchpad
    # we have split this into a specific method to cope with the GNOME
    # settings schema using two keys to define one scroll-method
    def scrollmethod_changed(self, settings, key):
        if key not in ["two-finger-scrolling-enabled", "edge-scrolling-enabled"]:
            return

        two_finger = settings.get_boolean("two-finger-scrolling-enabled")
        edge_scroll = settings.get_boolean("edge-scrolling-enabled")

        scroll_method = self.ensure_peripheral_element("touchpad", "scrollMethod")
        scroll_method.text = "twofinger" if two_finger else ("edge" if edge_scroll else "none")

        self.write_config()

    # this manages the default terminal updates
    def default_terminal_changed(self, settings, key):
        if key != "exec":
            return

        bridge = self.et.find("./keyboard/keybind[@bridge='plugins.media-keys/terminal']/action")
        if bridge != None:
            bridge.attrib['command'] = settings[key]

        self.write_config()

    # this manages libinput based updates - mouse and touchpad
    def peripherals_changed(self, settings, key):

        if "touchpad" in settings.props.schema:
            category = "touchpad"
        else:
            category = "non-touch"

        yesno = { "natural-scroll" : "naturalScroll",
                  "left-handed" : "leftHanded",
                  "accel-profile" : "accelProfile",
                  "tap-to-click" : "tap",
                  "tap-and-drag" : "tapAndDrag",
                  "tap-and-drag-lock" : "dragLock",
                  "middle-click-emulation" : "middleEmulation",
                  "disable-while-typing" : "disableWhileTyping"}
        match key:
            case "speed":
                schema = "pointerSpeed"
                textvalue = str(settings[key])
            case "accel-profile":
                schema = "accelProfile"
                textvalue = 'adaptive' if settings[key] == "adaptive" else 'flat' # assume "default" is flat
            case "tap-button-map":
                schema = "tapButtonMap"
                textvalue = settings[key]
            case "click-method":
                schema = "clickMethod"
                if settings[key] == "none":
                    textvalue = "none"
                elif settings[key] == "areas":
                    textvalue = "buttonAreas"
                else:
                    textvalue = "clickfinger"
            case "send-events":
                schema = "sendEventsMode"
                if settings[key] == "enabled":
                    textvalue = "yes"
                elif settings[key] == "disabled":
                    textvalue = "no"
                else:
                    textvalue = "disabledOnExternalMouse"
            case "double-click":
                textvalue = str(settings[key])
            case _:
                if key in yesno:
                    schema = yesno[key]
                    textvalue = 'yes' if settings[key] else 'no'
                else:
                    self.log.info("unknown key " + key + " for peripherals category " + category)
                    return

        if key == "double-click":
            schema = "./mouse/doubleClickTime"
            bridge = self.et.find(schema)

            if bridge is not None:
                bridge.text = textvalue
            else:
                self.log.info("cannot find schema " + schema + " to set the value " + textvalue)
        else:
            # Use the helper to ensure structure exists
            element = self.ensure_peripheral_element(category, schema)
            element.text = textvalue

        self.write_config()

    # writes the complete environment file with XKB and cursor settings
    def write_environment_file(self):
        """Write environment file with keyboard layout, XKB options, cursor, and locale settings"""
        path = self.user_config("environment")

        # Define which variables are FULLY managed by the bridge (overwritten)
        fully_managed_vars = {
            'XKB_DEFAULT_LAYOUT',
            'XKB_DEFAULT_OPTIONS',
            'XCURSOR_THEME',
            'XCURSOR_SIZE',
            'LANG',
            'LC_CTYPE',
            'LC_NUMERIC',
            'LC_TIME',
            'LC_COLLATE',
            'LC_MONETARY',
            'LC_MESSAGES',
            'LC_PAPER',
            'LC_NAME',
            'LC_ADDRESS',
            'LC_TELEPHONE',
            'LC_MEASUREMENT',
            'LC_IDENTIFICATION'
        }

        # Read existing variables to preserve user customizations
        existing_vars = read_key_value_file(path)

        # Build new managed variables
        new_vars = {}

        # Get keyboard layout
        layout = self.get_keyboard_layout()
        new_vars['XKB_DEFAULT_LAYOUT'] = layout

        # Get XKB options
        new_vars['XKB_DEFAULT_OPTIONS'] = self.get_merged_xkb_options()

        # Get cursor settings from desktop_interface_settings
        if self.desktop_interface_settings:
            cursor_theme = self.desktop_interface_settings.get_string("cursor-theme")
            if cursor_theme:
                new_vars['XCURSOR_THEME'] = cursor_theme

            cursor_size = self.desktop_interface_settings.get_int("cursor-size")
            if cursor_size:
                new_vars['XCURSOR_SIZE'] = str(cursor_size)

        # Get locale settings from locale1 D-Bus interface
        locale_from_locale1 = self.get_locale_from_locale1()
        if locale_from_locale1:
            self.log.info(f"Got {len(locale_from_locale1)} locale variables from locale1")
            new_vars.update(locale_from_locale1)
        else:
            # Fallback to current environment if locale1 not available
            self.log.info("No locale from locale1, using environment fallback")
            for var in fully_managed_vars:
                if var.startswith('LANG') or var.startswith('LC_'):
                    value = os.environ.get(var)
                    if value:
                        new_vars[var] = value

            # Ensure we have at least LANG set
            if 'LANG' not in new_vars:
                new_vars['LANG'] = 'en_US.UTF-8'

        # Merge: keep user variables, update managed ones
        final_vars = {}

        # First, add all existing variables that aren't managed
        for key, value in existing_vars.items():
            if key not in fully_managed_vars:
                final_vars[key] = value

        # Then add/update all managed variables
        final_vars.update(new_vars)

        # Write the file
        os.makedirs(os.path.dirname(path), exist_ok=True)

        lines = []
        lines.append("# Budgie Desktop - labwc environment configuration\n")
        lines.append("# Variables fully managed by budgie: XKB_DEFAULT_LAYOUT, XKB_DEFAULT_OPTIONS, XCURSOR_*, LC_*, LANG\n")
        lines.append("# Use dconf key xkb-options to add user defined values\n")
        lines.append("# Other user customizations are preserved\n\n")

        # Organize variables by category
        xkb_vars = {k: v for k, v in final_vars.items() if k.startswith('XKB_')}
        cursor_vars = {k: v for k, v in final_vars.items() if k.startswith('XCURSOR_')}
        locale_vars = {k: v for k, v in final_vars.items() if k.startswith('LC_') or k == 'LANG'}
        other_vars = {k: v for k, v in final_vars.items()
                      if not k.startswith('XKB_') and not k.startswith('XCURSOR_')
                      and not k.startswith('LC_') and k != 'LANG'}

        if xkb_vars:
            for key in sorted(xkb_vars.keys()):
                lines.append(f"{key}={xkb_vars[key]}\n")

        if cursor_vars:
            lines.append("\n")
            for key in sorted(cursor_vars.keys()):
                lines.append(f"{key}={cursor_vars[key]}\n")

        if locale_vars:
            lines.append("\n")
            for key in sorted(locale_vars.keys()):
                lines.append(f"{key}={locale_vars[key]}\n")

        if other_vars:
            lines.append("\n# User customizations\n")
            for key in sorted(other_vars.keys()):
                lines.append(f"{key}={other_vars[key]}\n")

        with open(path, "w") as file:
            file.writelines(lines)

        self.log.info(f"Updated environment file: {path}")

    # this handles cursor changes
    def cursor_changed(self, settings, key):
        match key:
            case "cursor-theme" | "cursor-size":
                # Regenerate the complete environment file
                self.write_environment_file()
            case _:
                return

        if self.delay_config_write:
            return

        # reload config for labwc
        subprocess.call("labwc -r", shell=True)

    # this handles keyboard layout and XKB options changes
    def desktop_input_sources_changed(self, settings, key):
        if key not in ["sources", "xkb-options"]:
            return

        # Regenerate the complete environment file with updated layout/options
        self.write_environment_file()

        if self.delay_config_write:
            return

        # reload config for labwc
        subprocess.call("labwc -r", shell=True)

    # changes to gsettings custom keys are managed with this method
    def customkeys_changed(self, settings, customkeypath):
        # relocatable schema is used for custom keyboard shortcuts so
        # we need to cope with updates, new shortcuts and deletion of shortcuts
        root = self.et.getroot()

        # first scan the config file to find any custom entries.
        matches = [bridge for bridge in self.et.findall('./keyboard/keybind[@bridge]') if 'custom' in bridge.attrib['bridge']]

        for matched in matches:
            customkeypath = matched.attrib["bridge"]

            result = [path for path in self.gsd_media_keys_settings.get_strv("custom-keybindings") if customkeypath in path]

            if len(result) > 0:
                customkeypath = result[0]
                schema = Gio.Settings.new_with_path("org.buddiesofbudgie.settings-daemon.plugins.media-keys.custom-keybinding", customkeypath)
                schema_command = schema["command"]
                schema_binding = schema["binding"]
                customkey = customkeypath.split("/")[-2]

                newbinding = self.calc_keybind(schema_binding)

                matched.attrib["key"] = newbinding

                path = "./keyboard/keybind[@bridge='"+customkey+"']/action"
                action = root.find(path)
                action.attrib["name"] = "Execute"
                action.attrib["command"] = schema_command
            else:
                # config file has a customkey to delete
                parent = root.find("./keyboard")
                parent.remove(matched)

        # now check that all gsettings custom keys are in the config file
        # we also need to connect to the changed signal for the relocatable schema
        # so that modifications are notified
        self.custom_keys_settings = {}
        for customkeypath in self.gsd_media_keys_settings.get_strv("custom-keybindings"):
            schema = Gio.Settings.new_with_path("org.buddiesofbudgie.settings-daemon.plugins.media-keys.custom-keybinding", customkeypath)
            schema_command = schema["command"]
            schema_binding = schema["binding"]
            customkey = customkeypath.split("/")[-2]
            self.custom_keys_settings[schema] = schema.connect('changed', self.customkeys_changed)

            newbinding = self.calc_keybind(schema_binding)
            path = "./keyboard/keybind[@bridge='"+customkey+"']"
            parent = root.find(path)
            if parent != None:
                # found the keybind in the config so lets update the keybind and
                # action with the latest values
                parent.attrib["key"] = newbinding

                path = "./keyboard/keybind[@bridge='"+customkey+"']/action"
                action = root.find(path)
                action.attrib["name"] = "Execute"
                action.attrib["command"] = schema_command
            else:
                # we need to create keybind and action elements
                bridge = root.find("./keyboard")
                keyelement = Et.SubElement(bridge, "keybind")
                keyelement.attrib["bridge"] = customkey
                keyelement.attrib["key"] = newbinding
                child = Et.SubElement(keyelement,"action")
                child.attrib["name"] = "Execute"
                child.attrib["command"] = schema_command

        self.write_config()

    # this forces a resync of all recognised gsettings and outputs to the labwc config files
    def bridge_config(self):
        self.delay_config_write = True

        root = self.et.getroot()
        path = "./keyboard/"
        for bridge in root.findall(path):
            if "bridge" in bridge.attrib:
                try:
                    short_schemakey = bridge.attrib["bridge"]
                    if "custom" in short_schemakey:
                        continue

                    short_schema = short_schemakey.split("/")[0]
                    key = short_schemakey.split("/")[1]

                    if short_schema in "org.buddiesofbudgie.settings-daemon.plugins.media-keys":
                        self.keybindings_changed(self.gsd_media_keys_settings, key)
                    if short_schema in "org.gnome.desktop.wm.keybindings":
                        self.keybindings_changed(self.desktop_wm_keybindings_settings, key)
                    if short_schema in "com.solus-project.budgie-wm":
                        self.keybindings_changed(self.budgie_wm_settings, key)
                    if short_schema in "org.gnome.mutter":
                        self.keybindings_changed(self.mutter_settings, key)
                    elif short_schema in "org.gnome.mutter.keybindings":
                        self.keybindings_changed(self.mutter_keybindings_settings, key)
                except IndexError:
                    pass

        budgie_wmkeys = {"window-focus-mode",
                         "show-all-windows-tabswitcher",
                         "edge-tiling",
                         "take-full-screenshot",
                         "take-region-screenshot",
                         "clear-notifications",
                         "toggle-raven",
                         "toggle-notifications"}
        for key in budgie_wmkeys:
            self.budgie_wm_changed(self.budgie_wm_settings, key)

        self.mutter_changed(self.mutter_settings, "center-new-windows")
        self.mutter_changed(self.mutter_settings, "overlay-key")
        self.desktop_wm_preferences_changed(self.desktop_wm_preferences_settings, "titlebar-font")
        self.desktop_wm_preferences_changed(self.desktop_wm_preferences_settings, "button-layout")
        self.desktop_wm_preferences_changed(self.desktop_wm_preferences_settings, "num-workspaces")
        self.desktop_interface_changed(self.desktop_interface_settings, "gtk-theme")
        self.desktop_interface_changed(self.desktop_interface_settings, "icon-theme")
        self.desktop_interface_changed(self.desktop_interface_settings, "cursor-theme")
        self.desktop_interface_changed(self.desktop_interface_settings, "cursor-size")
        self.panel_settings_changed(self.panel_settings, "notification-position")
        self.desktop_input_sources_changed(self.desktop_input_sources_settings, "sources")
        self.desktop_input_sources_changed(self.desktop_input_sources_settings, "xkb-options")

        self.customkeys_changed(self.gsd_media_keys_settings, None)

        self.default_terminal_changed(self.default_terminal_settings, "exec")

        touchpadkeys = {"natural-scroll",
                        "left-handed",
                        "accel-profile",
                        "tap-to-click",
                        "tap-and-drag",
                        "tap-and-drag-lock",
                        "middle-click-emulation",
                        "disable-while-typing",
                        "speed",
                        "accel-profile",
                        "tap-button-map",
                        "click-method",
                        "send-events" }
        for key in touchpadkeys:
            self.peripherals_changed(self.peripherals_touchpad_settings, key)

        mousekeys = {   "natural-scroll",
                        "left-handed",
                        "speed",
                        "accel-profile",
                        "middle-click-emulation",
                        "double-click" }

        for key in mousekeys:
            self.peripherals_changed(self.peripherals_mouse_settings, key)

        # Sync scroll method settings
        try:
            self.scrollmethod_changed(self.peripherals_touchpad_settings, "two-finger-scrolling-enabled")
        except Exception as e:
            self.log.warning(f"Could not sync scroll method: {e}")

        self.delay_config_write = False
        self.write_config()

    # all solus-project budgie-wm gsettings changes are managed
    def budgie_wm_changed(self, settings, key):
        root = self.et.getroot()

        updated = False

        if key == "window-focus-mode":
            path = "./focus/followMouse"
            bridge = root.find(path)

            if bridge == None:
                return

            class Mode(StrEnum):
                CLICK = 'click'
                SLOPPY = 'sloppy'
                MOUSE = 'mouse'

            focus_mode = settings[key]

            if focus_mode != Mode.CLICK:
                bridge.text = "yes"
            else:
                bridge.text = "no"

            updated = True

            pathraise = "./focus/raiseOnFocus"
            bridgeraise = root.find(pathraise)

            if bridgeraise == None:
                return

            if focus_mode == Mode.MOUSE:
                bridgeraise.text = "yes"
            else:
                bridgeraise.text = "no"

        if key == "show-all-windows-tabswitcher":
            path = "./windowSwitcher"
            bridge = root.find(path)

            if bridge == None:
                return

            if settings[key]:
                bridge.attrib["allWorkspaces"] = "yes"
            else:
                bridge.attrib["allWorkspaces"] = "no"

            updated = True

        if key == "edge-tiling":
            path = "./snapping/range"
            bridge = root.find(path)

            if bridge == None:
                return

            if settings[key]:
                bridge.text = "10"
            else:
                bridge.text = "0"

            updated = True

        if key in ["toggle-notifications",
                   "clear-notifications",
                   "take-full-screenshot",
                   "take-region-screenshot",
                   "toggle-raven",
                   "show-power-dialog"]:
            self.keybindings_changed(settings, key)

        if updated:
            self.write_config()

    # all gnome mutter gsettings changes are managed
    def mutter_changed(self, settings, key):

        if key == "overlay-key":
            self.keybindings_changed(settings, key)
            return

        if key != "center-new-windows":
            return

        root = self.et.getroot()

        path = "./placement/policy"
        bridge = root.find(path)

        if bridge == None:
            return

        if settings[key]:
            bridge.text = "center"
        else:
            bridge.text = "automatic"

        self.write_config()

    # all gnome desktop-wm gsettings changes are managed
    def desktop_wm_preferences_changed(self, settings, key):

        root = self.et.getroot()

        updated = False
        if key == "titlebar-font":
            pango = Pango.FontDescription.from_string(settings[key])
            family = pango.get_family()
            weight = "Normal" if pango.get_weight() <= Pango.Weight.NORMAL else "Bold"
            slant = "Normal" if pango.get_style() == Pango.Style.NORMAL else "Italic"

            for bridge in root.findall("./theme/font"):
                updated = True
                bridge.attrib["name"] = family
                bridge.attrib["weight"] = weight
                bridge.attrib["slant"] = slant
                bridge.attrib["size"] = str(int(pango.get_size()/ Pango.SCALE))

            if not updated:
                return

        if key == "button-layout":
            path = "./theme/titlebar/layout"
            bridge = root.find(path)

            if bridge == None:
                return

            if settings[key].startswith('close'):
                bridge.text = "close,iconify,max:"
            else:
                bridge.text = ":iconify,max,close:"

            updated = True

        if key == "num-workspaces":
            path = "./desktops"
            bridge = root.find(path)

            if bridge == None:
                return

            bridge.attrib["number"] = str(settings[key])

            updated = True

        if updated:
            self.write_config()

    # all gnome desktop interface gsettings changes are managed
    def desktop_interface_changed(self, settings, key):
        search = ""
        match key:
            case "gtk-theme":
                search = "./theme/name"
            case "icon-theme":
                search = "./theme/icon"
            case "cursor-size":
                self.cursor_changed(settings, key)
                return
            case "cursor-theme":
                self.cursor_changed(settings, key)
                return
            case _:
                return

        interface = settings[key]
        root = self.et.getroot()

        bridge = root.find(search)
        if bridge == None:
            return

        bridge.text = interface

        self.write_config()

    # method to calculate the labwc keybind equivalents of gnome gsetting keybinds
    def calc_keybind(self, gkey):
        substitute = {
                "<Alt>" : "A-",
                "<Super>" : "W-",
                "<Control>" : "C-",
                "<Primary>" : "C-",
                "<Ctrl>" : "C-",
                "<Shift>" : "S-",
                "Calculator" : "XF86Calculator",
                "Battery" : "XF86Battery",
                "Tools" : "XF86Tools",
                "Eject" : "XF86Eject",
                "Mail" : "XF86Mail",
                "Suspend" : "XF86Suspend",
                "Hibernate" : "XF86Hibernate",
                "Explorer" : "XF86Explorer",
                "KbdBrightnessDown" : "XF86KbdBrightnessDown",
                "KbdLightOnOff" : "XF86KbdLightOnOff",
                "KbdBrightnessUp" : "XF86KbdBrightnessUp",
                "AudioMedia" : "XF86AudioMedia",
                "AudioNext" : "XF86AudioNext",
                "AudioMicMute" : "XF86AudioMicMute",
                "AudioPause" : "XF86AudioPause",
                "AudioRandomPlay" : "XF86AudioRandomPlay",
                "AudioForward" : "XF86AudioForward",
                "AudioRandomPlay" : "XF86AudioRandomPlay",
                "AudioRepeat" : "XF86AudioRepeat",
                "AudioPlay" : "XF86AudioPlay",
                "AudioRewind" : "XF86AudioRewind",
                "PowerOff" : "XF86PowerOff",
                "AudioPrev" : "XF86AudioPrev",
                "Bluetooth" : "XF86Bluetooth",
                "WLAN" : "XF86WLAN",
                "UWB" : "XF86UWB",
                "RFKill" : "XF86RFKill",
                "RotationLockToggle" : "XF86RotationLockToggle",
                "MonBrightnessCycle" : "XF86MonBrightnessCycle",
                "MonBrightnessDown" : "XF86MonBrightnessDown",
                "MonBrightnessUp" : "XF86MonBrightnessUp",
                "Screensaver" : "XF86ScreenSaver",
                "Search" : "XF86Search",
                "AudioStop" : "XF86AudioStop",
                "Sleep" : "XF86Sleep",
                "TouchpadOff" : "XF86TouchpadOff",
                "TouchpadOn" : "XF86TouchpadOn",
                "TouchpadToggle" : "XF86TouchpadToggle",
                "AudioLowerVolume" : "XF86AudioLowerVolume",
                "AudioMute" : "XF86AudioMute",
                "AudioRaiseVolume" : "XF86AudioRaiseVolume",
                "WWW" : "XF86WWW"}

        if not gkey or gkey == "":
            replacement = "undefined"
        else:
            replacement = gkey

            for sub in substitute:
                replacement = replacement.replace(sub, substitute[sub])

            if replacement[-1] == "-":
                replacement = replacement[:-1]

            replacement = replacement.replace("XF86XF86", "XF86")

            # Convert the final key (non-modifier) to lowercase
            if "-" in replacement:
                parts = replacement.rsplit("-", 1)
                if len(parts) == 2:
                    modifiers = parts[0]
                    key = parts[1]
                    # Only lowercase if it's not an XF86 key or special key
                    if not key.startswith("XF86") and len(key) == 1:
                        key = key.lower()
                    replacement = modifiers + "-" + key
            else:
                # No modifiers, just a single key
                if len(replacement) == 1:
                    replacement = replacement.lower()

        return replacement

    # all keybinds from various gsettings schemas are managed
    def keybindings_changed(self, settings, key):

        # do validation checks for the key
        if key not in settings:
            return

        if key == "custom-keybindings":
            self.customkeys_changed(self.gsd_media_keys_settings, None)
            return

        # for some reason, the mutter overlay-key is a string, while every other key, rest of mutter included, is a string array.
        # turning overlay-key into an array seems to allow it to work properly, or else it ends up as just the first character
        if key == "overlay-key":
            keybind = [settings[key]]
        else:
            keybind = settings[key]

        if keybind == None:
            keybind = []

        root = self.et.getroot()

        partial = settings.props.schema.split(".")

        if partial == None or len(partial) < 2:
            return

        partial = partial[-2] + "." + partial[-1] + "/" + key

        # Find all existing keybind elements for this bridge key
        path = "./keyboard/keybind[@bridge='" + partial + "']"
        existing_keybinds = root.findall(path)

        # If no existing keybinds found, nothing to update
        if len(existing_keybinds) == 0:
            return

        # For media keys, check if we should use -static values
        effective_keybind = keybind
        if settings == self.gsd_media_keys_settings:
            # Check if main key is empty but -static key has values
            main_is_empty = len(keybind) == 0 or all(not binding for binding in keybind)

            if main_is_empty:
                try:
                    static_key = key + "-static"
                    static_keybind = settings[static_key]
                    self.log.info(f"Main key '{key}' is empty, checking -static: {static_keybind}")

                    # If -static has values, use those instead
                    if static_keybind and len(static_keybind) > 0:
                        has_values = any(binding for binding in static_keybind)
                        if has_values:
                            self.log.info(f"Using -static values for '{key}'")
                            effective_keybind = static_keybind
                            main_is_empty = False
                except KeyError:
                    # No -static key exists
                    self.log.info(f"No -static key found for '{key}'")
                    pass

        # Handle empty keybind array - keep one element with "undefined"
        is_empty = False
        if len(effective_keybind) == 0:
            is_empty = True
        else:
            # Check if all bindings are empty or None
            all_empty = True
            for binding in effective_keybind:
                if binding:  # If any binding is not empty
                    all_empty = False
                    break
            is_empty = all_empty

        if is_empty:
            # Remove all but the first keybind element
            keyboard_element = root.find("./keyboard")
            for i, bridge in enumerate(existing_keybinds):
                if i == 0:
                    # Keep first element but set to undefined
                    bridge.attrib["key"] = "undefined"
                else:
                    # Remove extra elements
                    keyboard_element.remove(bridge)

            self.write_config()
            return

        # Process each keybinding in the array
        for i, binding in enumerate(effective_keybind):
            calculated_key = self.calc_keybind(binding)

            self.log.info(f"Processing keybind '{key}' index {i}: binding='{binding}' -> calculated='{calculated_key}'")

            # Note: if we're using effective_keybind from -static,
            # we don't need the fallback logic below since we already have the static values

            # Update existing keybind or create new one
            if i < len(existing_keybinds):
                # Update existing element
                existing_keybinds[i].attrib["key"] = calculated_key
            else:
                # Create new keybind element
                # First, get the action structure from the first keybind
                if len(existing_keybinds) > 0:
                    # Clone the action element from the first keybind
                    keyboard_element = root.find("./keyboard")
                    new_keybind = Et.Element("keybind")
                    new_keybind.attrib["bridge"] = partial
                    new_keybind.attrib["key"] = calculated_key

                    # Copy the action element(s) from the first keybind
                    for action in existing_keybinds[0].findall("action"):
                        new_action = Et.Element("action")
                        new_action.attrib.update(action.attrib)
                        new_action.text = action.text
                        new_keybind.append(new_action)

                    # Insert after the last existing keybind for this bridge
                    insert_index = list(keyboard_element).index(existing_keybinds[-1]) + 1
                    keyboard_element.insert(insert_index, new_keybind)

        # Remove excess keybind elements if array shrank
        if len(existing_keybinds) > len(keybind):
            keyboard_element = root.find("./keyboard")
            for bridge in existing_keybinds[len(keybind):]:
                keyboard_element.remove(bridge)

        self.write_config()

    # all solus-project panel gsettings changes are managed
    def panel_settings_changed(self, settings, key):
        #find all action XML elements for the notification window

        if key != "notification-position":
            return

        root = self.et.getroot()

        position = self.panel_settings['notification-position']

        newdirection = []

        match position:
            case "BUDGIE_NOTIFICATION_POSITION_TOP_LEFT":
                newdirection = ['up','left']
            case "BUDGIE_NOTIFICATION_POSITION_TOP_RIGHT":
                newdirection = ['up','right']
            case "BUDGIE_NOTIFICATION_POSITION_BOTTOM_LEFT":
                newdirection = ['down','left']
            case "BUDGIE_NOTIFICATION_POSITION_BOTTOM_RIGHT":
                newdirection = ['down','right']
            case _:
                self.log.warning("Unknown notification position %s", position)
                return

        count = 0
        for element in root.findall("./windowRules/windowRule/[@identifier='budgie-daemon'][@title='BudgieNotification']/action"):
            if element.attrib['name'] == 'MoveToEdge':
                element.attrib['direction'] = newdirection[count]
                count = count + 1
            if count > 1:
                break

        self.write_config()

if __name__== '__main__':
    # check if labwc is actually running otherwise this bridge is not required to runs
    pid=os.getpid()
    username = psutil.Process(pid).username()
    pids = []
    try:
        pids=[process.pid for process in psutil.process_iter() if process.username() == username and 'labwc' in process.name()]

        if len(pids) == 0:
            sys.exit()
    except (psutil.AccessDenied, psutil.NoSuchProcess):
        sys.exit()

    bridge = Bridge()

    mainloop = GLib.MainLoop()
    mainloop.run()
