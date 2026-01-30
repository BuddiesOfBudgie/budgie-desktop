/*
* This file is part of budgie-desktop
*
* Copyright Budgie Desktop Developers
*
* This program is free software; you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation; either version 2 of the License, or
* (at your option) any later version.
*/

namespace Budgie {
    /**
    * Shared brightness utilities used by both BrightnessManager and BrightnessHelper
    */
    public class BrightnessUtil : GLib.Object {
        public string? backlight_device { get; private set; default = null; }
        public string? backlight_path { get; private set; default = null; }
        public int max_brightness { get; private set; default = 0; }
        public int current_brightness { get; private set; default = 0; }

        /**
        * Find the first available backlight device
        */
        public bool find_backlight_device() {
            try {
                var backlight_dir = File.new_for_path("/sys/class/backlight");

                if (!backlight_dir.query_exists()) {
                    warning("No /sys/class/backlight directory found");
                    return false;
                }

                debug("Searching for backlight devices in /sys/class/backlight");
                var enumerator = backlight_dir.enumerate_children(
                    FileAttribute.STANDARD_NAME,
                    FileQueryInfoFlags.NONE
                );

                FileInfo? info;
                while ((info = enumerator.next_file()) != null) {
                    backlight_device = info.get_name();
                    backlight_path = Path.build_filename("/sys/class/backlight", backlight_device);
                    debug("Found backlight device: %s", backlight_device);
                    break; // Use first device found
                }

                if (backlight_device == null) {
                    warning("No backlight device found in /sys/class/backlight");
                    return false;
                }

                // Read max brightness
                var max_file = File.new_for_path(Path.build_filename(backlight_path, "max_brightness"));
                uint8[] contents;
                if (max_file.load_contents(null, out contents, null)) {
                    max_brightness = int.parse((string)contents);
                    debug("Device %s has max_brightness: %d", backlight_device, max_brightness);
                }

                // Read current brightness
                update_current_brightness();

                return true;

            } catch (Error e) {
                warning("Error finding backlight device: %s", e.message);
                return false;
            }
        }

        /**
        * Read current brightness from sysfs
        */
        public void update_current_brightness() {
            if (backlight_path == null) return;

            try {
                var brightness_file = File.new_for_path(Path.build_filename(backlight_path, "brightness"));
                uint8[] contents;
                if (brightness_file.load_contents(null, out contents, null)) {
                    current_brightness = int.parse((string)contents);
                }
            } catch (Error e) {
                warning("Error reading brightness: %s", e.message);
            }
        }

        /**
        * Get session ID from logind using the proper D-Bus API
        * This is equivalent to sd_pid_get_session()
        */
        public static string? get_session_from_logind() {
            try {
                int pid = Posix.getpid();

                var connection = Bus.get_sync(BusType.SYSTEM);
                var reply = connection.call_sync(
                    "org.freedesktop.login1",
                    "/org/freedesktop/login1",
                    "org.freedesktop.login1.Manager",
                    "GetSessionByPID",
                    new Variant("(u)", (uint32)pid),
                    new VariantType("(o)"),
                    DBusCallFlags.NONE,
                    -1
                );

                string session_object_path;
                reply.get("(o)", out session_object_path);

                // Extract session ID from object path
                // Path format: /org/freedesktop/login1/session/SESSION_ID
                string[] parts = session_object_path.split("/");
                if (parts.length > 0) {
                    return parts[parts.length - 1];
                }

            } catch (Error e) {
                warning("Failed to get session from logind: %s", e.message);
            }

            return null;
        }

        /**
        * Get session ID
        */
        public static string? get_session_id() {
            // Method 1: Use XDG_SESSION_ID environment variable
            string? session_id = Environment.get_variable("XDG_SESSION_ID");

            if (session_id != null && session_id != "") {
                debug("Using XDG_SESSION_ID: %s", session_id);
                return session_id;
            }

            // Method 2: Ask logind for our session using our PID
            debug("XDG_SESSION_ID not set, querying logind...");
            session_id = get_session_from_logind();

            if (session_id != null) {
                debug("Got session ID from logind: %s", session_id);
            } else {
                warning("Could not determine session ID");
            }

            return session_id;
        }
    }
}
