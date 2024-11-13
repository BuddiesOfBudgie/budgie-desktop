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
    const string DBUS_SCREENLOCK = "org.buddiesofbudgie.BudgieScreenlock";
	const string DBUS_SCREENLOCK_PATH = "/org/buddiesofbudgie/Screenlock";

	[DBus (name="org.buddiesofbudgie.BudgieScreenlock")]
    public class Screenlock {
        static Screenlock? instance;

        // connections to various schemas used in screenlocking
        private GLib.Settings power;
        private GLib.Settings session;
        private GLib.Settings screensaver;
        private GLib.Settings lockdown;

        // public functions should check this variable first and exit gracefully where needed
        bool all_apps = true;

        private string calculate_lockcommand() {
            // grab the background picture and strip the file prefix
            string current_wallpaper = screensaver.get_string("picture-uri").replace("file://","");

            // swaylock interprets : as a delimiter for the output name
            // recommendation by swaylock is to replace : with ::
            current_wallpaper = current_wallpaper.replace(":", "::");

            string output = "";
            File file = File.new_for_path(current_wallpaper);
            if (current_wallpaper == "" || !file.query_exists()) {
                output = "-c 000000";
            }
            else {
                output = "-i " + current_wallpaper;
            }

            return "swaylock -Fklf " + output;
        }

        private string calculate_sleep() {
            string output = "";

            // number of seconds on ac power that is inactive before action taken; 0 is never
            int sleep_inactive_ac_timeout = this.power.get_int("sleep-inactive-ac-timeout");

            // BCC sets "nothing" or "suspend" when toggled
            string sleep_inactive_ac_type = this.power.get_string("sleep-inactive-ac-type");

            // number of seconds on battery that is inactive before action taken; 0 is never
            int sleep_inactive_battery_timeout = this.power.get_int("sleep-inactive-battery-timeout");

            // BCC sets "nothing" or "suspend" when toggled
            string sleep_inactive_battery_type = this.power.get_string("sleep-inactive-battery-type");

            if (sleep_inactive_battery_type == "suspend" && sleep_inactive_battery_timeout != 0) {
                output = "timeout " + sleep_inactive_battery_timeout.to_string();
                output += " 'if upower -i $(upower -e | grep '/battery') | grep --color=never -E 'state' | grep -e 'discharging'; then systemctl suspend; fi' ";
            }

            if (sleep_inactive_ac_type == "suspend" && sleep_inactive_ac_timeout !=0) {
                output += " timeout " + sleep_inactive_ac_timeout.to_string();
                output += " 'if upower -i $(upower -e | grep '/line_power') | grep --color=never -E 'online' | grep -e 'yes'; then systemctl suspend; fi' ";
            }

            return output;
        }

        private void calculate_idle() {
            uint idle_delay = 0;

            string new_idle = "";

            bool lock_enabled = false;
            uint lock_delay = 0;

            bool disable_lock_screen = false;

            idle_delay = this.session.get_uint("idle-delay");

            lock_enabled = this.screensaver.get_boolean("lock-enabled");
            lock_delay = this.screensaver.get_uint("lock-delay");

            disable_lock_screen = this.lockdown.get_boolean("disable-lock-screen");

            new_idle = "swayidle -w ";

            if (idle_delay !=0 ) {
                new_idle += "timeout " + idle_delay.to_string() + " 'wlopm --off \\*' resume 'wlopm --on \\*' ";
            }

            if (lock_enabled && !disable_lock_screen) {
                new_idle += "timeout " + (idle_delay + lock_delay).to_string() + " '" + calculate_lockcommand() + "' ";
            }

            if (!disable_lock_screen) {
                new_idle += "before-sleep '" + calculate_lockcommand() + "'";
            }

            new_idle += " " + calculate_sleep();

            debug("%s", new_idle);
            try {
                string[] spawn_args = {"killall", "swayidle"};
                string[] spawn_env = Environ.get();

                /* sometimes swayidle exists twice - so we run the kill Process
                   to make sure before starting swayidle again
                */
                Process.spawn_sync ("/",
							spawn_args,
							spawn_env,
							SpawnFlags.SEARCH_PATH |
                            SpawnFlags.STDERR_TO_DEV_NULL |
                            SpawnFlags.STDOUT_TO_DEV_NULL,
							null,
							null,
							null,
							null);

                Process.spawn_sync ("/",
							spawn_args,
							spawn_env,
							SpawnFlags.SEARCH_PATH |
                            SpawnFlags.STDERR_TO_DEV_NULL |
                            SpawnFlags.STDOUT_TO_DEV_NULL,
							null,
							null,
							null,
							null);

                Process.spawn_command_line_async(new_idle);
            } catch (SpawnError e) {
				print("Error: %s\n", e.message);
			}
        }

        [DBus (visible = false)]
		public void setup_dbus() {
			/* Hook up screenlock dbus */
			Bus.own_name(BusType.SESSION, DBUS_SCREENLOCK, BusNameOwnerFlags.REPLACE,
				on_bus_acquired,
				() => {},
				() => {} );
		}

        void on_bus_acquired(DBusConnection conn) {
			try {
				conn.register_object(DBUS_SCREENLOCK_PATH, this);
			} catch (Error e) {
				message("Unable to register Screenlock: %s", e.message);
			}
		}

        public async void lock() throws GLib.DBusError, GLib.IOError {
            if (!all_apps) {
                yield;
                return;
            }

            try {
                Process.spawn_command_line_async(calculate_lockcommand());
            } catch (SpawnError e) {
				print("Error: %s\n", e.message);
			}

            yield;
        }

		[DBus (visible = false)]
		public static unowned Screenlock init() {
			if (instance == null)
				instance = new Screenlock();

			return instance;
		}

        private Screenlock() {
            string check_apps[] = {"wayidle", "killall", "wlopm", "swaylock", "upower", "systemctl"};

            foreach(unowned var app in check_apps) {
                if (Environment.find_program_in_path("wayidle") != null) {
                    warning(app + " is not found for screenlocking");
                    all_apps = false;
                }
            }

            if (!all_apps) {
                return;
            }

            this.power = new Settings("org.gnome.settings-daemon.plugins.power");
            this.power.changed.connect((key) => {
                string[] search = { "sleep-inactive-ac-timeout",
                                    "sleep-inactive-ac-type",
                                    "sleep-inactive-battery-timeout",
                                    "sleep-inactive-battery-type"};

                if (key in search) {
                    calculate_idle();
                }
            });

            this.session = new Settings("org.gnome.desktop.session");
            this.session.changed.connect((key) => {
                if (key == "idle-delay") {
                    calculate_idle();
                }
            });

            this.screensaver = new Settings("org.gnome.desktop.screensaver");
            this.screensaver.changed.connect((key) => {
                string[] search = {"lock-enabled", "lock-delay", "picture-uri"};

                if (key in search) {
                    calculate_idle();
                }
            });
            this.lockdown = new Settings("org.gnome.desktop.lockdown");
            this.lockdown.changed.connect((key) => {
                if (key == "disable-lock-screen") {
                    calculate_idle();
                }
            });

            calculate_idle();
        }
    }
}