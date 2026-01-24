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
* Note: the following projects were consulted as inspiration for the
* logic decisions
* Obtaining XDG_SESSION_ID  - systemd project documentation
* How to use loginD SetBrightness - wlroot library
* brightnessctl on how to obtain the backlight devices
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
		private string? backlight_device = null;
		private string? backlight_path = null;
		private int max_brightness = 0;
		private int current_brightness = 0;
		
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
			find_backlight_device();
			setup_logind_session.begin((obj, res) => {
				setup_logind_session.end(res);
				
				debug("setup_logind_session completed - device=%s, session=%s",
				backlight_device ?? "null",
				logind_session != null ? "connected" : "null");
				
				// Only set up monitoring once logind is connected
				if (backlight_device != null && logind_session != null) {
					setup_brightness_monitor();
					_is_ready = true;
					debug("Initialization complete, firing ready signal");
					ready();
				} else {
					debug("BrightnessManager not available: device=%s, session=%s",
					backlight_device ?? "null",
					logind_session != null ? "connected" : "null");
				}
			});
		}
		
		/**
		* Find the first available backlight device
		*/
		private void find_backlight_device() {
			try {
				var backlight_dir = File.new_for_path("/sys/class/backlight");
				
				if (!backlight_dir.query_exists()) {
					warning("No /sys/class/backlight directory found");
					return;
				}
				
				debug("Searching for backlight devices in /sys/class/backlight");
				var enumerator = backlight_dir.enumerate_children(
					FileAttribute.STANDARD_NAME,
					FileQueryInfoFlags.NONE
				);
				
				FileInfo? info;
				while ((info = enumerator.next_file()) != null) {
					backlight_device = info.get_name();
					backlight_path = "/sys/class/backlight/" + backlight_device;
					debug("Found backlight device: %s", backlight_device);
					break; // Use first device found
				}
				
				if (backlight_device == null) {
					debug("No backlight device found in /sys/class/backlight");
					return;
				}
				
				// Read max brightness
				var max_file = File.new_for_path(backlight_path + "/max_brightness");
				uint8[] contents;
				if (max_file.load_contents(null, out contents, null)) {
					max_brightness = int.parse((string)contents);
					debug("Device %s has max_brightness: %d", backlight_device, max_brightness);
				}
				
				// Read current brightness
				update_current_brightness();
				
			} catch (Error e) {
				warning("Error finding backlight device: %s", e.message);
			}
		}
		
		/**
		* Set up inotify monitoring on brightness file
		*/
		private void setup_brightness_monitor() {
			if (backlight_path == null) {
				warning("Cannot setup brightness monitor: no backlight path");
				return;
			}
			
			try {
				var brightness_file = File.new_for_path(backlight_path + "/brightness");
				brightness_monitor = brightness_file.monitor_file(FileMonitorFlags.NONE);
				brightness_monitor.changed.connect(on_brightness_file_changed);
				debug("Monitoring brightness changes on %s/brightness", backlight_path);
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
			if (backlight_path == null) return;
			
			try {
				var brightness_file = File.new_for_path(backlight_path + "/brightness");
				uint8[] contents;
				if (brightness_file.load_contents(null, out contents, null)) {
					int new_brightness = int.parse((string)contents);
					if (new_brightness != current_brightness) {
						current_brightness = new_brightness;
						double level = (double)current_brightness / (double)max_brightness;
						debug("Brightness changed to %d/%d (%.2f%%)",
						current_brightness, max_brightness, level * 100);
						brightness_changed(level);
					}
				}
			} catch (Error e) {
				warning("Error reading brightness: %s", e.message);
			}
		}
		
		/**
		* Set up connection to logind session
		*/
		private async void setup_logind_session() {
			try {
				string? session_id = null;
				
				// Method 1: Use XDG_SESSION_ID environment variable (standard method)
				session_id = Environment.get_variable("XDG_SESSION_ID");
				debug("XDG_SESSION_ID from environment: %s", session_id ?? "null");
				
				// Method 2: Ask logind for our session using our PID (proper systemd API)
				if (session_id == null || session_id == "") {
					debug("XDG_SESSION_ID not set, querying logind for our session...");
					session_id = yield get_session_from_logind();
				}
				
				if (session_id == null || session_id == "") {
					warning("Could not determine session ID");
					return;
				}
				
				session_path = "/org/freedesktop/login1/session/" + session_id;
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
		* Get session ID from logind using the proper D-Bus API
		* This is equivalent to sd_pid_get_session()
		*/
		private async string? get_session_from_logind() {
			try {
				// Get our PID - use Posix since GLib.Process.id() doesn't exist in older GLib
				int pid = Posix.getpid();
				debug("Our PID is %d, asking logind for session...", pid);
				
				// Call org.freedesktop.login1.Manager.GetSessionByPID
				var connection = yield Bus.get(BusType.SYSTEM);
				var reply = yield connection.call(
					"org.freedesktop.login1",
					"/org/freedesktop/login1",
					"org.freedesktop.login1.Manager",
					"GetSessionByPID",
					new Variant("(u)", (uint32)pid),
					new VariantType("(o)"),
					DBusCallFlags.NONE,
					-1
				);
				
				// Extract session object path
				string session_object_path;
				reply.get("(o)", out session_object_path);
				debug("logind returned session object path: %s", session_object_path);
				
				// Extract session ID from object path
				// Path format: /org/freedesktop/login1/session/SESSION_ID
				string[] parts = session_object_path.split("/");
				if (parts.length > 0) {
					string session_id = parts[parts.length - 1];
					debug("Extracted session ID: %s", session_id);
					return session_id;
				}
				
			} catch (Error e) {
				warning("Failed to get session from logind: %s", e.message);
			}
			
			return null;
		}
		
		/**
		* Set brightness to absolute value (0 to max_brightness)
		*/
		public void set_brightness(uint32 value) {
			if (!_is_ready) {
				warning("Cannot set brightness: BrightnessManager not ready yet");
				return;
			}
			
			if (logind_session == null || backlight_device == null) {
				warning("Cannot set brightness: not initialized (session=%s, device=%s)",
				logind_session != null ? "ok" : "null",
				backlight_device ?? "null");
				return;
			}
			
			uint32 clamped = uint32.min(value, max_brightness);
			
			try {
				debug("Setting brightness to %u (max: %d)", clamped, max_brightness);
				logind_session.SetBrightness("backlight", backlight_device, clamped);
			} catch (Error e) {
				warning("Failed to set brightness: %s", e.message);
			}
		}
		
		/**
		* Set brightness as percentage (0.0 to 1.0)
		*/
		public void set_brightness_percent(double percent) {
			if (max_brightness == 0) {
				warning("Cannot set brightness: max_brightness is 0");
				return;
			}
			
			double clamped = percent.clamp(0.0, 1.0);
			uint32 value = (uint32)(clamped * max_brightness);
			set_brightness(value);
		}
		
		/**
		* Increase brightness by percentage step
		*/
		public void increase_brightness(double step = 0.05) {
			if (max_brightness == 0) return;
			
			double current_percent = (double)current_brightness / (double)max_brightness;
			double new_percent = (current_percent + step).clamp(0.0, 1.0);
			set_brightness_percent(new_percent);
		}
		
		/**
		* Decrease brightness by percentage step
		*/
		public void decrease_brightness(double step = 0.05) {
			if (max_brightness == 0) return;
			
			double current_percent = (double)current_brightness / (double)max_brightness;
			double new_percent = (current_percent - step).clamp(0.0, 1.0);
			set_brightness_percent(new_percent);
		}
		
		/**
		* Get current brightness level (0.0 to 1.0)
		*/
		public double get_brightness_level() {
			if (max_brightness == 0) return 0.0;
			return (double)current_brightness / (double)max_brightness;
		}
		
		/**
		* Get current brightness value
		*/
		public int get_brightness() {
			return current_brightness;
		}
		
		/**
		* Get max brightness value
		*/
		public int get_max_brightness() {
			return max_brightness;
		}
		
		/**
		* Check if brightness control is available
		*/
		public bool is_available() {
			return _is_ready && backlight_device != null && logind_session != null;
		}
	}
}
