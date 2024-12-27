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

import gi
from gi.repository import Gio, GLib
gi.require_version('Pango', '1.0')
from gi.repository import Pango

mainloop = None

class Bridge:

    # element tree to read/write
    et = None

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

    # writes the labwc rc.xml file back
    def write_config(self):
        # Write back to file
        if self.delay_config_write:
            return

        path = os.path.join(
            os.environ["HOME"], ".config", "labwc", "rc.xml"
        )
        Et.indent(self.et, space="\t", level=0)
        self.et.write(path)

        # reload config for labwc
        subprocess.call("labwc -r", shell=True)

    # starting point for the bridge
    def __init__(self):

        self.log = logging.getLogger('labwc_bridge')
        self.log.addHandler(JournalHandler())

        # Check if a local labwc environment file exists - if doesn't
        # use the budgie-desktop shared file - or the distro variant if it exists
        # to populate the local labwc environment file

        search_path = [
            os.path.join(os.environ["HOME"], ".config", "labwc", "environment"),
            os.path.join("/usr", "share", "budgie-desktop", "distro-environment"),
            os.path.join("/usr", "share", "budgie-desktop", "environment")
        ]

        path = ""
        for path in search_path:
            if os.path.isfile(path):
                break

        if path == "":
            self.log.critical("Could not find an existing environment or a shipped budgie equivalent")
            return

        try:
            if path != search_path[0]:
                folder = os.path.join(os.environ["HOME"], ".config", "labwc")
                os.makedirs(folder, exist_ok=True)
                shutil.copy(path, search_path[0])
        except Exception as e:
            self.log.critical("Failed to copy " + path + " to " + search_path[0])
            self.log.critical(e)
            return

        # Check if a local labwc config file exists - if so use it
        # otherwise use the budgie-desktop shared file - or the distro variant if it exists
        # to populate the local labwc config

        search_path = [
            os.path.join(os.environ["HOME"], ".config", "labwc", "rc.xml"),
            os.path.join("/usr", "share", "budgie-desktop", "distro-rc.xml"),
            os.path.join("/usr", "share", "budgie-desktop", "rc.xml")
        ]

        path = ""
        for path in search_path:
            if os.path.isfile(path):
                break

        if path == "":
            self.log.critical("Could not find an existing rc.xml or a shipped budgie equivalent")
            return

        try:
            self.et = Et.parse(source=path)
        except Exception as e:
            self.log.warning("Cannot parse " + path + ":\n")
            self.log.warning(e)
            return

        signal.signal(signal.SIGINT, self.sigint_handler)

        # this is the heart of the bridge - connect all the recognised gsetting schemas
        # that we will listen to and respond to changes
        self.panel_settings = Gio.Settings.new('com.solus-project.budgie-panel')
        self.panel_settings.connect('changed', self.panel_settings_changed)

        self.gsd_media_keys_settings = Gio.Settings.new('org.gnome.settings-daemon.plugins.media-keys')
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

        self.default_terminal_settings = Gio.Settings.new('org.gnome.desktop.default-applications.terminal')
        self.default_terminal_settings.connect('changed', self.default_terminal_changed)

        self.bridge_config()

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
        else:
            schema = "./libinput/device[@category='" + category + "']/" + schema
        bridge = self.et.find(schema)

        if bridge is not None:
            bridge.text = textvalue
        else:
            self.log.info("cannot find schema " + schema + " to set the value " + value)

        self.write_config()

    # this handles keyboard layout changes
    def desktop_input_sources_changed(self, settings, key):
        if key != "sources":
            return

        # grab the settings sources and reformat it
        # i.e. variants expressed as "+variant" need to be
        # converted to (variant)
        # and we ignore ibus keyboard layouts since the
        # window manager expects only xkb
        layout = ""
        for source in settings[key]:
            if source[0] == 'xkb':
                extract = source[1].replace("'","")

                if "+" in extract:
                    rhs = extract.split("+")
                    extract = rhs[0] + "(" + rhs[1] + ")"

                if layout == "":
                    layout = extract
                else:
                    layout += "," + extract

        if layout == "":
            layout = "us" # default to at least a known keyboard layout

        path = os.path.join(os.environ["HOME"], ".config", "labwc", "environment")
        subprocess.call("sed -i 's/^XKB_DEFAULT_LAYOUT=.*/XKB_DEFAULT_LAYOUT="+layout+"/g' " + path, shell=True)

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
                schema = Gio.Settings.new_with_path("org.gnome.settings-daemon.plugins.media-keys.custom-keybinding", customkeypath)
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
            schema = Gio.Settings.new_with_path("org.gnome.settings-daemon.plugins.media-keys.custom-keybinding", customkeypath)
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

                    if short_schema in "org.gnome.settings-daemon.plugins.media-keys":
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

        self.budgie_wm_changed(self.budgie_wm_settings, "focus-mode")
        self.budgie_wm_changed(self.budgie_wm_settings, "show-all-windows-tabswitcher")
        self.mutter_changed(self.mutter_settings, "center-new-windows")
        self.desktop_wm_preferences_changed(self.desktop_wm_preferences_settings, "titlebar-font")
        self.desktop_wm_preferences_changed(self.desktop_wm_preferences_settings, "button-layout")
        self.desktop_wm_preferences_changed(self.desktop_wm_preferences_settings, "num-workspaces")
        self.desktop_interface_changed(self.desktop_interface_settings, "gtk-theme")
        self.panel_settings_changed(self.panel_settings, "notification-position")
        self.desktop_input_sources_changed(self.desktop_input_sources_settings, "sources")

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
                        "send-events"}
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

        self.delay_config_write = False
        self.write_config()

    # all solus-project budgie-wm gsettings changes are managed
    def budgie_wm_changed(self, settings, key):
        root = self.et.getroot()

        updated = False

        if key == "focus-mode":
            path = "./focus/followMouse"
            bridge = root.find(path)

            if bridge == None:
                return

            if settings[key]:
                bridge.text = "yes"
            else:
                bridge.text = "no"

            updated = True

            pathraise = "./focus/raiseOnFocus"
            bridgeraise = root.find(pathraise)

            if bridgeraise == None:
                return

            if settings[key]:
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

        if key != "gtk-theme":
            return

        interface = settings[key]
        root = self.et.getroot()

        bridge = root.find("./theme/name")
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

        return replacement

    # all keybinds from various gsettings schemas are managed
    def keybindings_changed(self, settings, key):

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
            return

        root = self.et.getroot()

        partial = settings.props.schema.split(".")

        if partial == None or len(partial) < 2:
            return

        partial = partial[-2] + "." + partial[-1] + "/" + key
        path = "./keyboard/keybind/[@bridge='" + partial + "']"
        for bridge in root.findall(path):
            bridge.attrib["key"] = self.calc_keybind(keybind[0])

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
