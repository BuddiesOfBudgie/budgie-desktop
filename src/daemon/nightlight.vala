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
	public class NightLightManager : GLib.Object {
		private Settings settings;
		private const string local_config_file = "config.ini";
		private const string search_config_file = "gammastep.config";
		private string local_config_path;

		public NightLightManager() {
			// Initialise the GSettings schema
			settings = new Settings("org.gnome.settings-daemon.plugins.color");

			// Ensure the local configuration file exists
			local_config_path = Path.build_filename(GLib.Environment.get_user_config_dir(), "gammastep", local_config_file);
			ensure_local_config_exists();

			// Connect to the "changed" signal for the relevant keys
			settings.changed.connect(on_settings_changed);

			on_settings_changed(settings, "");
		}

		private void on_settings_changed(Settings settings, string key) {
			bool night_light_enabled = settings.get_boolean("night-light-enabled");
			if (night_light_enabled) {
				update_gammastep_config();
				run_gammastep();
			} else {
				stop_gammastep();
			}
		}

		private string? search_for_config() {
			// Check if a local gammastep config_file exists - if doesn't
			// use the budgie-desktop shared file - or the distro variant if it exists
			// to populate the local config folder

			string[] search_path = {local_config_path};
			foreach (string system_dir in GLib.Environment.get_system_data_dirs()) {
				search_path += Path.build_filename(system_dir, "budgie-desktop", "distro-"+search_config_file);
				search_path += Path.build_filename(system_dir, "budgie-desktop", search_config_file);
			}

			string path = "";
			foreach (unowned string p in search_path) {
				File search_config_file = File.new_for_path(p);
				if (search_config_file.query_exists(null)) {
					path = p;
					break;
				}
			}

			if (path == "") {
				critical("Could not find an existing "+search_config_file+" or a shipped budgie equivalent");
				return null;
			}

			return path;
		}


		private void ensure_local_config_exists() {
			string? default_config_path = search_for_config();

			if (default_config_path != null && default_config_path != local_config_path) {
				try {
					// Copy the default configuration file to the local configuration file location
					File dir = File.new_for_path(Path.get_dirname(local_config_path));
					dir.make_directory_with_parents(null);
					File default_config_file = File.new_for_path(default_config_path);
					File local_config_file = File.new_for_path(local_config_path);
					default_config_file.copy(local_config_file, FileCopyFlags.NONE, null, null);
				} catch (Error e) {
					warning("Failed to copy configuration file: %s\n", e.message);
				}
			}
		}

		private void update_gammastep_config() {
			try {
				// Load the configuration file
				KeyFile key_file = new KeyFile();
				key_file.load_from_file(local_config_path, KeyFileFlags.NONE);

				// Get the value of the night-light-temperature key from GSettings
				uint night_light_temperature = settings.get_uint("night-light-temperature");

				// Update the temp-night key in the configuration file
				key_file.set_uint64("general", "temp-night", night_light_temperature);

				// Check if night-light-schedule-automatic is enabled and update location-provider
				bool schedule_automatic = settings.get_boolean("night-light-schedule-automatic");
				if (schedule_automatic) {
					key_file.set_string("general", "location-provider", "geoclue2");
				} else {
					key_file.set_string("general", "location-provider", "manual");
				}

				// Get the value of the night-light-schedule-from key from GSettings
				double night_light_schedule_from = settings.get_double("night-light-schedule-from");

				// Convert the double value to an integer hour in 24-hour format
				int dusk_hour = (int) night_light_schedule_from;

				// Update the dusk-time key in the configuration file
				key_file.set_string("general", "dusk-time", dusk_hour.to_string()+":00");

				// Get the value of the night-light-schedule-to key from GSettings
				double night_light_schedule_to = settings.get_double("night-light-schedule-to");

				// Convert the double value to an integer hour in 24-hour format
				int dawn_hour = (int) night_light_schedule_to;

				// Update the dawn-time key in the configuration file
				key_file.set_string("general", "dawn-time", dawn_hour.to_string()+":00");

				// Save the updated configuration file
				key_file.save_to_file(local_config_path);
			} catch (Error e) {
				warning("Failed to update Gammastep configuration file: %s\n", e.message);
			}
		}

		private void run_gammastep() {
			try {
				// Run gammastep with the configuration file
				string[] spawn_args = {"gammastep", "-o", "-P", "-c", local_config_path};
				string[] spawn_env = Environ.get();

				Process.spawn_async("/",
							spawn_args,
							spawn_env,
							SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
							null,
							null);
			} catch (Error e) {
				warning("Failed to start gammastep: %s\n", e.message);
			}
		}

		private void stop_gammastep() {
			try {
				string[] spawn_args = {"killall", "-s", "SIGHUP", "gammastep"};
				string[] spawn_env = Environ.get();

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
			} catch (Error e) {
				warning("Failed to stop gammastep process: %s\n", e.message);
			}
		}
	}
}
