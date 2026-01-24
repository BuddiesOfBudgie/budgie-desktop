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

/**
* budgie-brightness-helper
*
* Simple command-line utility to adjust screen brightness
* Designed to be called from keyboard shortcuts
*
* Usage:
*   budgie-brightness-helper up [step]     - Increase brightness
*   budgie-brightness-helper down [step]   - Decrease brightness
*   budgie-brightness-helper set <value>   - Set to specific percentage (0-100)
*
* Examples:
*   budgie-brightness-helper up            - Increase by 5%
*   budgie-brightness-helper up 10         - Increase by 10%
*   budgie-brightness-helper down          - Decrease by 5%
*   budgie-brightness-helper set 50        - Set to 50%
*/

namespace Budgie {
	/**
	* DBus interface for logind Session
	*/
	[DBus (name = "org.freedesktop.login1.Session")]
	interface LogindSession : GLib.Object {
		public abstract void SetBrightness(string subsystem, string name, uint32 brightness) throws DBusError, IOError;
	}
	
	public class BrightnessHelper {
		private string? backlight_device = null;
		private string? backlight_path = null;
		private int max_brightness = 0;
		private int current_brightness = 0;
		private LogindSession? logind_session = null;
		
		public BrightnessHelper() {
			find_backlight_device();
			setup_logind_session();
		}
		
		/**
		* Find the first available backlight device
		*/
		private void find_backlight_device() {
			try {
				var backlight_dir = File.new_for_path("/sys/class/backlight");
				var enumerator = backlight_dir.enumerate_children(
					FileAttribute.STANDARD_NAME,
					FileQueryInfoFlags.NONE
				);
				
				FileInfo? info;
				while ((info = enumerator.next_file()) != null) {
					backlight_device = info.get_name();
					backlight_path = "/sys/class/backlight/" + backlight_device;
					break;
				}
				
				if (backlight_device == null) {
					critical("No backlight device found");
					return;
				}
				
				// Read max brightness
				var max_file = File.new_for_path(backlight_path + "/max_brightness");
				uint8[] contents;
				if (max_file.load_contents(null, out contents, null)) {
					max_brightness = int.parse((string)contents);
				}
				
				// Read current brightness
				var brightness_file = File.new_for_path(backlight_path + "/brightness");
				if (brightness_file.load_contents(null, out contents, null)) {
					current_brightness = int.parse((string)contents);
				}
				
			} catch (Error e) {
				critical("Error finding backlight device: %s", e.message);
			}
		}
		
		/**
		* Set up connection to logind session
		*/
		private void setup_logind_session() {
			try {
				string? session_id = null;
				
				// Method 1: Use XDG_SESSION_ID environment variable
				session_id = Environment.get_variable("XDG_SESSION_ID");
				
				// Method 2: Ask logind for our session using our PID
				if (session_id == null || session_id == "") {
					session_id = get_session_from_logind();
				}
				
				if (session_id == null || session_id == "") {
					critical("Could not determine session ID");
					return;
				}
				
				string session_path = "/org/freedesktop/login1/session/" + session_id;
				
				logind_session = Bus.get_proxy_sync(
					BusType.SYSTEM,
					"org.freedesktop.login1",
					session_path
				);
				
			} catch (Error e) {
				critical("Error connecting to logind: %s", e.message);
			}
		}
		
		/**
		* Get session ID from logind using D-Bus API (synchronous version)
		*/
		private string? get_session_from_logind() {
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
				
				string[] parts = session_object_path.split("/");
				if (parts.length > 0) {
					string session_id = parts[parts.length - 1];
					return session_id;
				}
				
			} catch (Error e) {
				warning("Failed to get session from logind: %s", e.message);
			}
			
			return null;
		}
		
		/**
		* Set brightness to absolute value
		*/
		public bool set_brightness(uint32 value) {
			if (logind_session == null || backlight_device == null) {
				critical("Brightness control not initialized");
				return false;
			}
			
			uint32 clamped = uint32.min(value, max_brightness);
			
			try {
				logind_session.SetBrightness("backlight", backlight_device, clamped);
				return true;
			} catch (Error e) {
				critical("Failed to set brightness: %s", e.message);
				return false;
			}
		}
		
		/**
		* Set brightness as percentage (0-100)
		*/
		public bool set_brightness_percent(int percent) {
			if (max_brightness == 0) {
				return false;
			}
			
			int clamped = percent.clamp(0, 100);
			uint32 value = (uint32)((clamped * max_brightness) / 100);
			return set_brightness(value);
		}
		
		/**
		* Increase brightness by percentage step
		*/
		public bool increase_brightness(int step_percent) {
			if (max_brightness == 0) {
				return false;
			}
			
			int current_percent = (current_brightness * 100) / max_brightness;
			int new_percent = (current_percent + step_percent).clamp(0, 100);
			return set_brightness_percent(new_percent);
		}
		
		/**
		* Decrease brightness by percentage step
		*/
		public bool decrease_brightness(int step_percent) {
			if (max_brightness == 0) {
				return false;
			}
			
			int current_percent = (current_brightness * 100) / max_brightness;
			int new_percent = (current_percent - step_percent).clamp(0, 100);
			return set_brightness_percent(new_percent);
		}
		
		/**
		* Print usage information
		*/
		private static void print_usage() {
			print("Usage: budgie-brightness-helper <command> [value]\n");
			print("\n");
			print("Commands:\n");
			print("  up [step]      Increase brightness by step percent (default: 5)\n");
			print("  down [step]    Decrease brightness by step percent (default: 5)\n");
			print("  set <value>    Set brightness to specific percentage (0-100)\n");
			print("\n");
			print("Examples:\n");
			print("  budgie-brightness-helper up       # Increase by 5%%\n");
			print("  budgie-brightness-helper up 10    # Increase by 10%%\n");
			print("  budgie-brightness-helper down     # Decrease by 5%%\n");
			print("  budgie-brightness-helper set 50   # Set to 50%%\n");
		}
		
		public static int main(string[] args) {
			if (args.length < 2) {
				print_usage();
				return 1;
			}
			
			var helper = new BrightnessHelper();
			string command = args[1].down();
			
			bool success = false;
			
			switch (command) {
				case "up":
				int step = 5;
				if (args.length >= 3) {
					step = int.parse(args[2]);
				}
				success = helper.increase_brightness(step);
				break;
				
				case "down":
				int step = 5;
				if (args.length >= 3) {
					step = int.parse(args[2]);
				}
				success = helper.decrease_brightness(step);
				break;
				
				case "set":
				if (args.length < 3) {
					print("'set' command requires a value (0-100)");
					print_usage();
					return 1;
				}
				int value = int.parse(args[2]);
				success = helper.set_brightness_percent(value);
				break;
				
				case "help":
				case "--help":
				case "-h":
				print_usage();
				return 0;
				
				default:
				print("Unknown command '%s'", command);
				print_usage();
				return 1;
			}
			
			return success ? 0 : 1;
		}
	}
}
