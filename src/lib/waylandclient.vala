/*
 * This file is part of budgie-desktop
 *
 * Copyright Budgie Desktop Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * The underlying WaylandClient does not appear to be fully thread-safe and either
 * repeated calls very quickly, or calls within the same process where the
 * reference was not release will result in mutex-locks causing and executable to spin
 * indefinitely.
 *
 * Our use in various executables is limited so we can initialise variable we use within
 * a singleton to make things thread-safe.
*/

namespace Budgie {
    public delegate bool MonitorCallback();

    [SingleInstance]
    public class WaylandClient : GLib.Object {
        private Xfw.Screen? screen = null;
        private unowned Xfw.Monitor? primary_monitor = null;
        private Gdk.Rectangle _monitor_res;
        // note _var format is being used since the var name conflicts with the
        // glib equivalent.
        private Gdk.Monitor? _gdk_monitor = null;
        private int _scale = 1;
        private bool _is_valid = false;
        private uint monitor_update_timeout = 0;
        private uint smooth_timeout = 0;
        private int initialization_attempts = 0;
        private const int MAX_INIT_ATTEMPTS = 50;
        private const uint SMOOTH_MS = 500;

        public signal void initialized();
        public signal void initialization_failed();

        public bool is_initialised() {
            return _is_valid && primary_monitor != null && _gdk_monitor != null;
        }

        public unowned Gdk.Monitor? gdk_monitor {
            get {
                if (!validate_monitor_reference()) {
                    warning("GdkMonitor reference is invalid, attempting refresh");
                    refresh_monitor_info();
                    return _gdk_monitor;
                }
                return _gdk_monitor;
            }
        }

        public Gdk.Rectangle monitor_res {
            get {
                if (!validate_monitor_reference()) {
                    warning("Monitor resolution reference is invalid, attempting refresh");
                    refresh_monitor_info();
                }
                return _monitor_res;
            }
        }

        public int scale {
            get {
                if (!validate_monitor_reference()) {
                    warning("Scale reference is invalid, attempting refresh");
                    refresh_monitor_info();
                }
                return _scale;
            }
        }

        public WaylandClient() {
            if (primary_monitor != null) return;

            screen = Xfw.Screen.get_default();
            if (screen == null) {
                critical("Failed to get default Xfw.Screen");
                // Emit failure signal on next idle
                Idle.add(() => {
                    initialization_failed();
                    return false;
                });
                return;
            }

            screen.monitors_changed.connect(on_monitors_changed_smoothed);
            initialize_monitor_info();
        }

        private void on_monitors_changed_smoothed() {
            // Immediately invalidate to prevent use of stale data
            _is_valid = false;

            // Cancel any pending smooth
            if (smooth_timeout != 0) {
                Source.remove(smooth_timeout);
            }

            // Schedule actual update after signals settle
            smooth_timeout = Timeout.add(SMOOTH_MS, () => {
                smooth_timeout = 0;
                debug("Monitor changes settled, updating...");
                on_monitors_changed();
                return false;
            });
        }

        private void initialize_monitor_info() {
            if (monitor_update_timeout != 0) {
                Source.remove(monitor_update_timeout);
                monitor_update_timeout = 0;
            }

            initialization_attempts = 0;
            monitor_update_timeout = Timeout.add(200, poll_for_monitor);
        }

        /*
          above we poll because libxfce4windowing's Wayland client may not have monitor information
          immediately available when the calling process starts. It can take a moment for the Wayland compositor
          to provide this data.
            If successful initialize our data, return false to stop polling
            If failed and haven't hit max attempts → return true to try again in 200ms
            If failed and hit max attempts → Give up, return false to stop polling
        */
        private bool poll_for_monitor() {
            initialization_attempts++;

            primary_monitor = screen.get_primary_monitor();

            if (primary_monitor != null) {
                update_monitor_data();
                monitor_update_timeout = 0;

                // Emit initialized signal if this is first successful init
                if (_is_valid) {
                    debug("WaylandClient initialized successfully");
                    initialized();
                }
                return false;
            }

            if (initialization_attempts >= MAX_INIT_ATTEMPTS) {
                critical("Failed to initialize primary monitor after %d attempts", MAX_INIT_ATTEMPTS);
                monitor_update_timeout = 0;
                initialization_failed();
                return false;
            }

            return true;
        }

        private void update_monitor_data() {
            if (primary_monitor == null) {
                _is_valid = false;
                return;
            }

            try {
                _monitor_res = primary_monitor.get_logical_geometry();
                _gdk_monitor = primary_monitor.get_gdk_monitor();
                _scale = (int) primary_monitor.get_scale();
                _is_valid = (_gdk_monitor != null);

                if (!_is_valid) {
                    warning("Failed to get valid GdkMonitor from primary monitor");
                } else {
                    debug("Monitor data updated successfully: scale=%d", _scale);
                    debug("Monitor data updated successfully: %dx%d at %d,%d",
                            _monitor_res.width, _monitor_res.height,
                            _monitor_res.x, _monitor_res.y);
                }
            } catch (Error e) {
                warning("Error updating monitor data: %s", e.message);
                _is_valid = false;
            }
        }

        private bool validate_monitor_reference() {
            if (!_is_valid || _gdk_monitor == null) {
                return false;
            }

            try {
                var display = _gdk_monitor.get_display();
                if (display == null) {
                    _is_valid = false;
                    return false;
                }

                // Verify the monitor is still in the display's monitor list
                int n_monitors = display.get_n_monitors();
                bool found = false;
                for (int i = 0; i < n_monitors; i++) {
                    if (display.get_monitor(i) == _gdk_monitor) {
                        found = true;
                        break;
                    }
                }

                if (!found) {
                    _is_valid = false;
                    return false;
                }
            } catch (Error e) {
                warning("Monitor validation failed: %s", e.message);
                _is_valid = false;
                return false;
            }

            return true;
        }

        private void refresh_monitor_info() {
            _is_valid = false;
            primary_monitor = null;

            if (screen == null) {
                screen = Xfw.Screen.get_default();
                if (screen == null) {
                    critical("Cannot refresh: Xfw.Screen is null");
                    return;
                }
            }

            initialize_monitor_info();
        }

        void on_monitors_changed() {
            _is_valid = false;
            initialize_monitor_info();
        }

        // Safe method to execute code that needs monitor info
        public bool with_valid_monitor(owned MonitorCallback callback) {
            if (!is_initialised()) {
                warning("WaylandClient not properly initialized");
                return false;
            }

            if (!validate_monitor_reference()) {
                warning("Monitor reference invalid, attempting refresh");
                refresh_monitor_info();

                if (!is_initialised()) {
                    warning("Failed to refresh monitor reference");
                    return false;
                }
            }

            return callback();
        }

        ~WaylandClient() {
            // Cleanup timeouts
            if (smooth_timeout != 0) {
                Source.remove(smooth_timeout);
            }
            if (monitor_update_timeout != 0) {
                Source.remove(monitor_update_timeout);
            }
        }
    }
}
