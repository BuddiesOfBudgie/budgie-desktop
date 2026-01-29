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
*/

namespace Budgie {
	/**
	* DBus interface for logind Session
	*/
	[DBus (name = "org.freedesktop.login1.Session")]
	interface LogindSession : GLib.Object {
		public abstract void SetBrightness(string subsystem, string name, uint32 brightness) throws DBusError, IOError;
	}

	public class BrightnessHelper : GLib.Application {
		private BrightnessUtil util;
		private LogindSession? logind_session = null;

		public BrightnessHelper() {
			Object(
				application_id: "org.buddiesofbudgie.BrightnessCLI",
				flags: ApplicationFlags.HANDLES_COMMAND_LINE
			);

			// Add options to the application
			add_main_option("up", 'u', OptionFlags.NONE, OptionArg.NONE,
			"Increase brightness", null);
			add_main_option("down", 'd', OptionFlags.NONE, OptionArg.NONE,
			"Decrease brightness", null);
			add_main_option("set", 's', OptionFlags.NONE, OptionArg.INT,
			"Set brightness to PERCENT (0-100)", "PERCENT");
			add_main_option("step", 't', OptionFlags.NONE, OptionArg.INT,
			"Step size for up/down (default: 5)", "PERCENT");

			util = new BrightnessUtil();
		}

		public override int command_line(ApplicationCommandLine cmd) {
			var options = cmd.get_options_dict();

			// Initialize hardware
			if (!util.find_backlight_device()) {
				cmd.printerr("Failed to find backlight device\n");
				return 1;
			}

			if (!setup_logind_session()) {
				cmd.printerr("Failed to connect to logind session\n");
				return 1;
			}

			// Get option values
			bool opt_up = options.contains("up");
			bool opt_down = options.contains("down");
			bool has_set = options.contains("set");
			int opt_set = has_set ? options.lookup_value("set", VariantType.INT32).get_int32() : -1;
			int opt_step = options.contains("step") ?
			options.lookup_value("step", VariantType.INT32).get_int32() : 5;

			// Validate step size
			if (opt_step < 1 || opt_step > 100) {
				cmd.printerr("Error: step must be between 1 and 100\n");
				return 1;
			}

			// Process commands (mutually exclusive)
			int commands_given = 0;
			if (opt_up) commands_given++;
			if (opt_down) commands_given++;
			if (has_set) commands_given++;

			if (commands_given == 0) {
				cmd.printerr("Error: Must specify one of --up, --down, or --set\n");
				cmd.printerr("Run with --help for usage information\n");
				return 1;
			}

			if (commands_given > 1) {
				cmd.printerr("Error: Cannot specify multiple commands (--up, --down, --set) simultaneously\n");
				return 1;
			}

			// Execute the requested command
			bool success = false;

			if (opt_up) {
				success = increase_brightness(opt_step);
			} else if (opt_down) {
				success = decrease_brightness(opt_step);
			} else if (has_set) {
				if (opt_set < 0 || opt_set > 100) {
					cmd.printerr("Error: brightness percentage must be between 0 and 100\n");
					return 1;
				}
				success = set_brightness_percent(opt_set);
			}

			return success ? 0 : 1;
		}

		private bool setup_logind_session() {
			try {
				string? session_id = BrightnessUtil.get_session_id();

				if (session_id == null || session_id == "") {
					critical("Could not determine session ID");
					return false;
				}

				string session_path = Path.build_filename("/org/freedesktop/login1/session", session_id);

				logind_session = Bus.get_proxy_sync(
					BusType.SYSTEM,
					"org.freedesktop.login1",
					session_path
				);

				return true;

			} catch (Error e) {
				critical("Error connecting to logind: %s", e.message);
				return false;
			}
		}

		public bool set_brightness(uint32 value) {
			if (logind_session == null || util.backlight_device == null) {
				critical("Brightness control not initialized");
				return false;
			}

			uint32 clamped = uint32.min(value, util.max_brightness);

			try {
				logind_session.SetBrightness("backlight", util.backlight_device, clamped);
				return true;
			} catch (Error e) {
				critical("Failed to set brightness: %s", e.message);
				return false;
			}
		}

		public bool set_brightness_percent(int percent) {
			if (util.max_brightness == 0) {
				critical("Max brightness is 0");
				return false;
			}

			int clamped = percent.clamp(0, 100);
			uint32 value = (uint32)((clamped * util.max_brightness) / 100);
			return set_brightness(value);
		}

		public bool increase_brightness(int step_percent) {
			if (util.max_brightness == 0) {
				critical("Max brightness is 0");
				return false;
			}

			int current_percent = (util.current_brightness * 100) / util.max_brightness;
			int new_percent = (current_percent + step_percent).clamp(0, 100);
			return set_brightness_percent(new_percent);
		}

		public bool decrease_brightness(int step_percent) {
			if (util.max_brightness == 0) {
				critical("Max brightness is 0");
				return false;
			}

			int current_percent = (util.current_brightness * 100) / util.max_brightness;
			int new_percent = (current_percent - step_percent).clamp(0, 100);
			return set_brightness_percent(new_percent);
		}

		public static int main(string[] args) {
			var app = new BrightnessHelper();
			return app.run(args);
		}
	}
}
