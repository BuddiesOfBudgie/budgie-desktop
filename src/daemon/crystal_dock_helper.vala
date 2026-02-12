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
	* Helper class to handle Crystal Dock autohide gap workaround
	* Monitors Crystal Dock configuration and adds 1px borders to wallpapers
	* to mask the gap left by autohide mode
	*/
	public class CrystalDockHelper : Object {
		private FileMonitor? config_monitor = null;
		private uint dock_check_timeout = 0;
		private bool last_dock_running = false;
		private bool crystal_dock_installed = false;
		private int current_poll_interval = 5000;  // Start at 5 seconds
		string config_dir = Path.build_filename(Environment.get_user_config_dir(), "crystal-dock", "Budgie");


		// Polling intervals
		const int POLL_INTERVAL_MIN = 5000;        // 5 seconds - minimum
		const int POLL_INTERVAL_MAX = 30000;       // 30 seconds - maximum
		const int POLL_INTERVAL_INCREMENT = 5000;  // Add 5 seconds each time

		public signal void dock_config_changed();

		public CrystalDockHelper() {
			// Check if Crystal Dock is actually installed before setting up monitoring
			crystal_dock_installed = Environment.find_program_in_path("crystal-dock") != null;

			if (crystal_dock_installed) {
				message("Crystal Dock is installed, setting up monitoring");
				setup_monitors();
			}
		}

		~CrystalDockHelper() {
			cleanup_monitors();
		}

		/**
		* Setup monitoring for Crystal Dock config changes and process state
		*/
		private void setup_monitors() {
			setup_config_file_monitor();
			setup_process_monitor();
		}

		/**
		* Cleanup monitors on destruction
		*/
		private void cleanup_monitors() {
			if (dock_check_timeout > 0) {
				Source.remove(dock_check_timeout);
				dock_check_timeout = 0;
			}
			if (config_monitor != null) {
				config_monitor.cancel();
				config_monitor = null;
			}
		}

		/**
		* Setup file monitor for Crystal Dock config directory
		*/
		private void setup_config_file_monitor() {
			if (!FileUtils.test(config_dir, FileTest.IS_DIR)) {
				return;
			}

			try {
				File config_file = File.new_for_path(config_dir);
				config_monitor = config_file.monitor_directory(FileMonitorFlags.NONE, null);

				config_monitor.changed.connect((file, other_file, event_type) => {
					string basename = file.get_basename();
					if (basename.has_prefix("panel_") && basename.has_suffix(".conf")) {
						switch (event_type) {
							case FileMonitorEvent.CHANGED:
							case FileMonitorEvent.CREATED:
							case FileMonitorEvent.DELETED:
								debug("Crystal Dock config changed: %s", basename);
								// Small delay to let file write complete
								Timeout.add(200, () => {
									dock_config_changed();
									return false;
								});
								break;
							default:
								break;
						}
					}
				});

				debug("Monitoring Crystal Dock config for changes");

			} catch (Error e) {
				warning("Failed to setup Crystal Dock config monitor: %s", e.message);
			}
		}

		/**
		* Setup adaptive process polling
		*/
		private void setup_process_monitor() {
			last_dock_running = is_running();
			current_poll_interval = POLL_INTERVAL_MIN;

			dock_check_timeout = Timeout.add(current_poll_interval, check_process_state);
		}

		/**
		* Check Crystal Dock process state and adjust polling interval
		*/
		private bool check_process_state() {
			bool currently_running = is_running();

			if (currently_running != last_dock_running) {
				// State changed - Crystal Dock started or stopped
				debug("Crystal Dock %s",
					currently_running ? "started" : "stopped");
				last_dock_running = currently_running;
				dock_config_changed();

				// Reset to minimum interval after state change
				if (current_poll_interval != POLL_INTERVAL_MIN) {
					current_poll_interval = POLL_INTERVAL_MIN;
					adjust_poll_interval();
				}
			} else {
				// State unchanged - increase interval by 5s (up to max)
				if (current_poll_interval < POLL_INTERVAL_MAX) {
					current_poll_interval += POLL_INTERVAL_INCREMENT;
					if (current_poll_interval > POLL_INTERVAL_MAX) {
						current_poll_interval = POLL_INTERVAL_MAX;
					}
					adjust_poll_interval();
				}
			}

			return true;  // Continue timeout
		}

		/**
		* Adjust polling interval by recreating the timeout
		*/
		private void adjust_poll_interval() {
			// Remove old timeout and create new one with adjusted interval
			if (dock_check_timeout > 0) {
				Source.remove(dock_check_timeout);
			}

			dock_check_timeout = Timeout.add(current_poll_interval, check_process_state);
		}

		/**
		* Check if crystal-dock process is running
		*/
		private bool is_running() {
			try {
				string stdout_str;
				int exit_status;

				Process.spawn_command_line_sync(
					"pgrep -x crystal-dock",
					out stdout_str,
					null,
					out exit_status
				);

				return exit_status == 0;
			} catch (SpawnError e) {
				warning("Failed to check for crystal-dock process: %s", e.message);
				return false;
			}
		}

		/**
		* Get edge position from a single panel config file
		* Returns: "top", "bottom", "left", "right", or null
		*/
		private string? get_panel_edge(string config_path) {
			if (!FileUtils.test(config_path, FileTest.EXISTS)) {
				return null;
			}

			try {
				string contents;
				FileUtils.get_contents(config_path, out contents);

				string[] lines = contents.split("\n");
				foreach (string line in lines) {
					if (line.has_prefix("position=")) {
						string pos_str = line.substring(9).strip();
						int position = int.parse(pos_str);

						// Map position number to edge
						switch (position) {
							case 0: return "top";
							case 1: return "bottom";
							case 2: return "left";
							case 3: return "right";
							default: return null;
						}
					}
				}
			} catch (Error e) {
				warning("Failed to read Crystal Dock config %s: %s", config_path, e.message);
			}

			return null;
		}

		/**
		* Detect all Crystal Dock panel edges
		* Returns: array of active edges (e.g., ["top", "bottom"])
		*/
		public string[] get_active_edges() {
			string[] edges = {};

			if (!crystal_dock_installed) {
				return edges;
			}

			if (!FileUtils.test(config_dir, FileTest.IS_DIR)) {
				return edges;
			}

			// Check for panel_1.conf through panel_4.conf
			for (int i = 1; i <= 4; i++) {
				string panel_file = "panel_%d.conf".printf(i);
				string config_path = Path.build_filename(config_dir, panel_file);

				string? edge = get_panel_edge(config_path);
				if (edge != null) {
					// Check if this edge is already in the array
					bool already_added = false;
					foreach (string existing_edge in edges) {
						if (existing_edge == edge) {
							already_added = true;
							break;
						}
					}
					if (!already_added) {
						edges += edge;
					}
				}
			}

			return edges;
		}

		/**
		* Add borders to wallpaper for dock edges
		* Returns: path to modified wallpaper, or original path if no changes needed
		*/
		public string? apply_borders(string original_path) {
			// Only apply borders if Crystal Dock is actually running
			if (!crystal_dock_installed || !last_dock_running) {
				return original_path;
			}

			string[] edges = get_active_edges();
			if (edges.length == 0) {
				return original_path;
			}

			// Get runtime directory
			string runtime_dir = Environment.get_variable("XDG_RUNTIME_DIR");
			if (runtime_dir == null) {
				runtime_dir = "/run/user/%d".printf((int)Posix.getuid());
			}

			string output_path = Path.build_filename(runtime_dir, "budgie_wallpaper_bordered.jpg");
			string current_input = original_path;
			string temp_output = output_path;

			// Apply borders sequentially for each edge
			foreach (string edge in edges) {
				string gravity;
				string splice;

				switch (edge) {
					case "top":
						gravity = "North";
						splice = "0x2";  // 2 pixel border
						break;
					case "bottom":
						gravity = "South";
						splice = "0x2";
						break;
					case "left":
						gravity = "West";
						splice = "2x0";
						break;
					case "right":
						gravity = "East";
						splice = "2x0";
						break;
					default:
						continue;
				}

				string[] cmdline = {
					"convert",
					current_input,
					"-gravity", gravity,
					"-background", "black",
					"-splice", splice,
					temp_output
				};

				try {
					int exit_status;
					Process.spawn_sync(
						null,
						cmdline,
						null,
						SpawnFlags.SEARCH_PATH,
						null,
						null,
						null,
						out exit_status
					);

					if (exit_status != 0) {
						warning("ImageMagick convert failed for %s edge with status %d", edge, exit_status);
						return original_path;
					}

					// Use output as input for next iteration
					current_input = temp_output;

				} catch (SpawnError e) {
					warning("Failed to spawn ImageMagick convert for %s edge: %s", edge, e.message);
					return original_path;
				}
			}

			if (FileUtils.test(output_path, FileTest.EXISTS)) {
				string edges_str = string.joinv(", ", edges);
				debug("Applied borders on edges: %s", edges_str);
				return output_path;
			}

			return original_path;
		}
	}
}
