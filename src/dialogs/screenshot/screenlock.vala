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
	const string POWERSCREEN_DBUS_NAME = "org.gnome.SettingsDaemon.Power";
	const string POWERSCREEN_DBUS_OBJECT_PATH = "/org/gnome/SettingsDaemon/Power";

	[DBus (name="org.gnome.SettingsDaemon.Power.Screen")]
	public interface PowerScreenRemote : GLib.Object {
		public abstract int32 Brightness { get; set; }
	}

	[DBus (name="org.buddiesofbudgie.BudgieScreenlock")]
	public class Screenlock {
		static Screenlock? instance;

		// Screen Dim capability
		PowerScreenRemote? powerscreen_proxy = null;
		bool isdimmable = false;
		int32 current_brightness = 0;
		public static bool is_dimming { get; private set; default = false; }

		// connections to various schemas used in screenlocking
		private GLib.Settings power;
		private GLib.Settings session;
		private GLib.Settings screensaver;
		private GLib.Settings lockdown;

		// public functions should check this variable first and exit gracefully where needed
		bool all_apps = true;

		// remember the locker to be used
		private string locker = "";

		/** Our upower client */
		private Up.Client client;
		private GLib.GenericArray<Up.Device> devices;
		private bool battery_mode;

		private string calculate_dim() {
			isdimmable = this.power.get_boolean("idle-dim");

			if (!isdimmable) return "";

			var dbus_call = "timeout 30 'dbus-send --type=method_call --dest=org.buddiesofbudgie.BudgieScreenlock /org/buddiesofbudgie/Screenlock org.buddiesofbudgie.BudgieScreenlock.Dim' ";
			dbus_call += "resume 'dbus-send --type=method_call --dest=org.buddiesofbudgie.BudgieScreenlock /org/buddiesofbudgie/Screenlock org.buddiesofbudgie.BudgieScreenlock.Undim' ";
			return dbus_call;
		}

		private string calculate_lockcommand() {
			string output = "";

			if (locker == "swaylock") {
				// grab the background picture and strip the file prefix
				string current_wallpaper = screensaver.get_string("picture-uri").replace("file://","");

				// swaylock interprets : as a delimiter for the output name
				// recommendation by swaylock is to replace : with ::
				current_wallpaper = current_wallpaper.replace(":", "::");

				File file = File.new_for_path(current_wallpaper);
				if (current_wallpaper == "" || !file.query_exists()) {
					// -c Turn the screen into the given color  in this case black
					output = "-c 000000";
				}
				else {
					// -i display the given image as the current wallpaper
					output = "-i " + current_wallpaper;
				}

				/*  -F Show current count of failed attempts
					-k Show the xkb layout while typing
					-l Show the Caps Lock state
					-f daemonize swaylock
				 */
				output = "swaylock -Fklf " + output;
			}
			else if (locker == "gtklock") {
				// -d daemonize gtklock
				output = "gtklock -d";

				/**
				* Try in order, and load the first one that exists:
				* - ~/.config/budgie-desktop/[gtklock.ini | gtklock.css]
				* - /etc/budgie-desktop/[gtklock.ini | gtklock.css]
				* - /usr/share/budgie-desktop/[gtklock.ini | gtklock.css]
				*/
				string[] lock_configs = {
					"file://" + Environment.get_user_config_dir() + "/budgie-desktop/gtklock.ini",
					@"file://$(Budgie.CONFDIR)/budgie-desktop/gtklock.ini",
					@"file://$(Budgie.DATADIR)/budgie-desktop/gtklock.ini"
				};

				foreach (string? filepath in lock_configs) {
					File file = File.new_for_uri(filepath);
					bool tmp = file.query_exists();
					if (tmp) {
						// -c load the config file
						output += " -c " + file.get_path();
						break;
					}
				}

				string[] style_configs = {
					"file://" + Environment.get_user_config_dir() + "/budgie-desktop/gtklock.css",
					@"file://$(Budgie.CONFDIR)/budgie-desktop/gtklock.css",
					@"file://$(Budgie.DATADIR)/budgie-desktop/gtklock.css"
				};

				foreach (string? filepath in style_configs) {
					File file = File.new_for_uri(filepath);
					bool tmp = file.query_exists();
					if (tmp) {
						// -s load the style file
						output += " -s " + file.get_path();
						break;
					}
				}
			}

			return output;
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

			string suspend = "dbus-send --system --print-reply --dest=org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager.Suspend boolean:false";
			if (sleep_inactive_battery_type == "suspend" && sleep_inactive_battery_timeout != 0) {
				output = "timeout " + sleep_inactive_battery_timeout.to_string();
				output += " 'if dbus-send --print-reply=literal --dest=org.buddiesofbudgie.BudgieScreenlock /org/buddiesofbudgie/Screenlock org.buddiesofbudgie.BudgieScreenlock.OnBattery | grep \"boolean true\" > /dev/null; then ";
				output += suspend + "; fi' ";
			}

			if (sleep_inactive_ac_type == "suspend" && sleep_inactive_ac_timeout !=0) {
				output += " timeout " + sleep_inactive_ac_timeout.to_string();
				output += " 'if dbus-send --print-reply=literal --dest=org.buddiesofbudgie.BudgieScreenlock /org/buddiesofbudgie/Screenlock org.buddiesofbudgie.BudgieScreenlock.OnBattery | grep \"boolean false\" > /dev/null; then ";
				output += suspend + "; fi' ";
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

			new_idle += calculate_dim();

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
				for (var i = 0; i <= 1; i++) {
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
				}

				Process.spawn_command_line_async(new_idle);
			} catch (SpawnError e) {
				print("Error: %s\n", e.message);
			}
		}

		/* Hold onto our PowerScreen proxy ref */
		void on_powerscreen_get(Object? o, AsyncResult? res) {
			try {
				powerscreen_proxy = Bus.get_proxy.end(res);
			} catch (Error e) {
				warning("Failed to get PowerScreen proxy: %s", e.message);
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

		public async void dim() throws GLib.DBusError, GLib.IOError {
			if (powerscreen_proxy == null) {
				return;
			}

			is_dimming = true;

			current_brightness = powerscreen_proxy.Brightness;
			int32 idle_brightness = power.get_int("idle-brightness");

			if (current_brightness > idle_brightness) {
				powerscreen_proxy.Brightness = idle_brightness;
			}
		}

		public async void undim() throws GLib.DBusError, GLib.IOError {
			if (powerscreen_proxy == null) {
				return;
			}

			powerscreen_proxy.Brightness = current_brightness;

			Timeout.add(200, ()=> {
				is_dimming = false;
				return false;
			});
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
				return;
			}

			try {
				Process.spawn_command_line_async(calculate_lockcommand());
			} catch (SpawnError e) {
				print("Error: %s\n", e.message);
			}
		}

		[DBus (visible = false)]
		public static unowned Screenlock init() {
			if (instance == null)
				instance = new Screenlock();

			return instance;
		}

		public bool on_battery() throws GLib.Error {
			return battery_mode;
		}

		private void client_daemon(GLib.Object obj, GLib.ParamSpec? sp) {
			battery_mode = client.get_on_battery();
		}

		private Screenlock() {
			string check_apps[] = {"swayidle", "killall", "wlopm", "dbus-send"};

			foreach(unowned var app in check_apps) {
				if (Environment.find_program_in_path(app) == null) {
					warning(app + " is not found for screenlocking");
					all_apps = false;
				}
			}

			string supported_lockers[] = {"gtklock", "swaylock"};


			foreach(unowned var app in supported_lockers) {
				if (Environment.find_program_in_path(app) != null) {
					locker = app;
					break;
				}
			}

			if (locker == "") {
				warning("No supported screen-locker has been found");
			}

			if (!all_apps || locker == "") {
				return;
			}

			Bus.get_proxy.begin<PowerScreenRemote>(BusType.SESSION, POWERSCREEN_DBUS_NAME, POWERSCREEN_DBUS_OBJECT_PATH, 0, null, on_powerscreen_get);

			// Connect to upower and get notifications for all batteries and power-supplies to see if on battery mode
			client = new Up.Client();
			client.notify.connect(this.client_daemon);
			devices = client.get_devices2();
			foreach (var device in devices) {
				if (device.kind == Up.DeviceKind.LINE_POWER || device.kind == Up.DeviceKind.BATTERY) {
					device.notify.connect(this.client_daemon);
				}
			}

			battery_mode = client.get_on_battery();

			this.power = new Settings("org.gnome.settings-daemon.plugins.power");
			this.power.changed.connect((key) => {
				string[] search = { "sleep-inactive-ac-timeout",
									"sleep-inactive-ac-type",
									"sleep-inactive-battery-timeout",
									"sleep-inactive-battery-type",
									"idle-dim"};

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
