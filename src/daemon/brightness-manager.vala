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
	* DBus interface for logind Session
	*/
	[DBus (name = "org.freedesktop.login1.Session")]
	interface LogindSession : GLib.Object {
		public abstract void SetBrightness(string subsystem, string name, uint32 brightness) throws DBusError, IOError;
	}

	/**
	* BrightnessManager handles monitoring and controlling system brightness
	* using kernel sysfs and logind DBus interface
	*/
	public class BrightnessManager : GLib.Object {
		private BrightnessUtil util;

		private FileMonitor? brightness_monitor = null;
		private LogindSession? logind_session = null;
		private string? session_path = null;

		private bool _is_ready = false;
		public bool is_ready {
			get { return _is_ready; }
		}

		public signal void brightness_changed(double level);
		public signal void ready();

		public BrightnessManager() {
			debug("Constructor called");
			util = new BrightnessUtil();
			util.find_backlight_device();

			setup_logind_session.begin((obj, res) => {
				setup_logind_session.end(res);

				debug("setup_logind_session completed - device=%s, session=%s",
				util.backlight_device ?? "null",
				logind_session != null ? "connected" : "null");

				// Only set up monitoring once logind is connected
				if (util.backlight_device != null && logind_session != null) {
					setup_brightness_monitor();
					_is_ready = true;
					debug("Initialization complete, firing ready signal");
					ready();
				} else {
					debug("BrightnessManager not available: device=%s, session=%s",
					util.backlight_device ?? "null",
					logind_session != null ? "connected" : "null");
				}
			});
		}

		/**
		* Set up inotify monitoring on brightness file
		*/
		private void setup_brightness_monitor() {
			if (util.backlight_path == null) {
				debug("Cannot setup brightness monitor: no backlight path");
				return;
			}

			try {
				var brightness_file = File.new_for_path(Path.build_filename(util.backlight_path, "brightness"));
				brightness_monitor = brightness_file.monitor_file(FileMonitorFlags.NONE);
				brightness_monitor.changed.connect(on_brightness_file_changed);
				debug("Monitoring brightness changes on %s/brightness", util.backlight_path);
			} catch (Error e) {
				warning("Failed to monitor brightness file: %s", e.message);
			}
		}

		/**
		* Called when brightness file changes
		*/
		private void on_brightness_file_changed(File file, File? other, FileMonitorEvent event) {
			if (event == FileMonitorEvent.CHANGED || event == FileMonitorEvent.CHANGES_DONE_HINT) {
				update_current_brightness();
			}
		}

		/**
		* Read current brightness from sysfs
		*/
		private void update_current_brightness() {
			if (util.backlight_path == null) return;

			int old_brightness = util.current_brightness;
			util.update_current_brightness();

			if (util.current_brightness != old_brightness) {
				double level = (double)util.current_brightness / (double)util.max_brightness;
				debug("Brightness changed to %d/%d (%.2f%%)",
				util.current_brightness, util.max_brightness, level * 100);
				brightness_changed(level);
			}
		}

		/**
		* Set up connection to logind session
		*/
		private async void setup_logind_session() {
			try {
				string? session_id = BrightnessUtil.get_session_id();

				if (session_id == null || session_id == "") {
					warning("Could not determine session ID");
					return;
				}

				session_path = Path.build_filename("/org/freedesktop/login1/session", session_id);
				debug("Connecting to logind session at %s...", session_path);

				logind_session = yield Bus.get_proxy(
					BusType.SYSTEM,
					"org.freedesktop.login1",
					session_path
				);

				debug("Successfully connected to logind session: %s", session_path);
			} catch (Error e) {
				warning("Failed to connect to logind session: %s", e.message);
			}
		}

		/**
		* Set brightness to absolute value (0 to max_brightness)
		*/
		public void set_brightness(uint32 value) {
			if (!_is_ready) {
				debug("Cannot set brightness: BrightnessManager not ready yet");
				return;
			}

			if (logind_session == null || util.backlight_device == null) {
				warning("Cannot set brightness: not initialized (session=%s, device=%s)",
				logind_session != null ? "ok" : "null",
				util.backlight_device ?? "null");
				return;
			}

			uint32 clamped = uint32.min(value, util.max_brightness);

			try {
				debug("Setting brightness to %u (max: %d)", clamped, util.max_brightness);
				logind_session.SetBrightness("backlight", util.backlight_device, clamped);
			} catch (Error e) {
				warning("Failed to set brightness: %s", e.message);
			}
		}

		/**
		* Set brightness as percentage (0.0 to 1.0)
		*/
		public void set_brightness_percent(double percent) {
			if (util.max_brightness == 0) {
				warning("Cannot set brightness: max_brightness is 0");
				return;
			}

			double clamped = percent.clamp(0.0, 1.0);
			uint32 value = (uint32)(clamped * util.max_brightness);
			set_brightness(value);
		}

		/**
		* Increase brightness by percentage step
		*/
		public void increase_brightness(double step = 0.05) {
			if (util.max_brightness == 0) return;

			double current_percent = (double)util.current_brightness / (double)util.max_brightness;
			double new_percent = (current_percent + step).clamp(0.0, 1.0);
			set_brightness_percent(new_percent);
		}

		/**
		* Decrease brightness by percentage step
		*/
		public void decrease_brightness(double step = 0.05) {
			if (util.max_brightness == 0) return;

			double current_percent = (double)util.current_brightness / (double)util.max_brightness;
			double new_percent = (current_percent - step).clamp(0.0, 1.0);
			set_brightness_percent(new_percent);
		}

		/**
		* Get current brightness level (0.0 to 1.0)
		*/
		public double get_brightness_level() {
			if (util.max_brightness == 0) return 0.0;
			return (double)util.current_brightness / (double)util.max_brightness;
		}

		/**
		* Get current brightness value
		*/
		public int get_brightness() {
			return util.current_brightness;
		}

		/**
		* Get max brightness value
		*/
		public int get_max_brightness() {
			return util.max_brightness;
		}

		/**
		* Check if brightness control is available
		*/
		public bool is_available() {
			return _is_ready && util.backlight_device != null && logind_session != null;
		}
	}
}
