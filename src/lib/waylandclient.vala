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

	public struct MonitorInfo {
		public string connector;
		public int index;
		public int width;
		public int height;
		public int scale_factor;
		public bool is_current_primary;
		public bool is_connected;
		public string manufacturer;
		public string model;
	}

	public struct MonitorMetadata {
		public string manufacturer;
		public string model;
		public int last_width;
		public int last_height;
		public int last_scale;
	}

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
		private Settings? panel_settings = null;
		private string? current_primary_connector = null;
		// Screen power management
		private static bool screen_power_suspended = false;

		// Primary monitor grace period
		private string? missing_primary_connector = null;
		private uint missing_primary_timeout = 0;
		private const uint PRIMARY_GRACE_PERIOD_MS = 5000;  // 5 seconds

		public signal void primary_monitor_changed(string? connector);

		public signal void initialized();
		public signal void initialization_failed();

		public bool is_initialised() {
			return _is_valid && primary_monitor != null && _gdk_monitor != null;
		}

		/**
		* Notify WaylandClient that screen power is being managed
		* This prevents monitor hotplugging from triggering during DPMS events
		*/
		public static void set_screen_power_suspended(bool suspended) {
			screen_power_suspended = suspended;
			if (suspended) {
				debug("Screen power suspended - ignoring monitor changes");
			} else {
				debug("Screen power resumed - monitoring changes");
			}
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
				Idle.add(on_initialization_failed_idle);
				return;
			}

			// Try to load panel settings for primary monitor config
			panel_settings = new Settings("com.solus-project.budgie-panel");
			panel_settings.changed["primary-monitor-list"].connect(on_primary_monitor_list_changed);

			screen.monitors_changed.connect(on_monitors_changed_smoothed);
			initialize_monitor_info();
		}

		private bool on_initialization_failed_idle() {
			initialization_failed();
			return false;
		}

		private void on_primary_monitor_list_changed() {
			on_monitors_changed_smoothed();
		}

		private bool on_smooth_timeout() {
			smooth_timeout = 0;
			debug("Monitor changes have stoppped, updating...");
			on_monitors_changed();
			return false;
		}

		/**
		* Get the configured primary monitor using various techniques
		*/
		private unowned Xfw.Monitor? get_budgie_primary_monitor() {
			if (screen == null) {
				return null;
			}

			unowned GLib.List<Xfw.Monitor> monitors = screen.get_monitors();
			if (monitors == null || monitors.length() == 0) {
				return null;
			}

			string? selected_connector = null;
			unowned Xfw.Monitor? selected_monitor = null;

			// Try monitors in the primary-monitor-list in order
			if (panel_settings != null) {
				string[] monitor_list = panel_settings.get_strv("primary-monitor-list");

				if (monitor_list.length > 0) {
					int list_position = 0;

					foreach (string candidate in monitor_list) {
						foreach (var monitor in monitors) {
							string? connector = monitor.get_connector();
							if (connector == candidate) {
								selected_connector = connector;
								selected_monitor = monitor;

								if (list_position == 0) {
									debug("Using configured primary monitor: %s", connector);
								} else {
									debug("Using fallback monitor #%d: %s", list_position, connector);

									// Promote this fallback to the primary position
									string[] new_list = new string[monitor_list.length];
									new_list[0] = candidate;
									int idx = 1;
									foreach (string mon in monitor_list) {
										if (mon != candidate) {
											new_list[idx++] = mon;
										}
									}
									panel_settings.set_strv("primary-monitor-list", new_list);
									debug("Promoted %s to primary position in list", candidate);
								}
								break;
							}
						}
						if (selected_monitor != null) break;
						list_position++;
					}

					if (selected_monitor == null) {
						debug("No monitors from primary-monitor-list are connected, using automatic selection");
					}
				}
			}

			// Use Xfw's primary monitor (if available)
			if (selected_monitor == null) {
				selected_monitor = screen.get_primary_monitor();
				if (selected_monitor != null) {
					selected_connector = selected_monitor.get_connector();
					debug("Using Xfw primary monitor: %s", selected_connector ?? "unknown");
				}
			}

			// Use leftmost/topmost monitor - basically none of the above was successful
			if (selected_monitor == null) {
				unowned Xfw.Monitor? leftmost = null;
				Gdk.Rectangle leftmost_rect = Gdk.Rectangle();
				leftmost_rect.x = int.MAX;
				leftmost_rect.y = int.MAX;

				foreach (var monitor in monitors) {
					var rect = monitor.get_logical_geometry();
					if (rect.x < leftmost_rect.x ||
						(rect.x == leftmost_rect.x && rect.y < leftmost_rect.y)) {
							leftmost = monitor;
							leftmost_rect = rect;
						}
					}

					selected_monitor = leftmost;
					if (selected_monitor != null) {
						selected_connector = selected_monitor.get_connector();
						debug("Using leftmost monitor: %s", selected_connector ?? "unknown");
					}
				}

				// Update current primary connector and emit signal if changed
				if (selected_connector != current_primary_connector) {
					string? old_connector = current_primary_connector;
					current_primary_connector = selected_connector;

					if (old_connector != null || selected_connector != null) {
						primary_monitor_changed(selected_connector);
					}
				}

				return selected_monitor;
			}

			/**
			* Cache metadata for a monitor
			*/
			private void cache_monitor_metadata(string connector, string manufacturer, string model, int width, int height, int scale) {
				if (panel_settings == null) return;

				string cache_json = panel_settings.get_string("monitor-metadata-cache");
				var parser = new Json.Parser();

				Json.Node? root = null;
				if (cache_json != "" && cache_json != "{}") {
					try {
						parser.load_from_data(cache_json);
						root = parser.get_root();
					} catch (Error e) {
						debug("Failed to parse existing cache, creating new: %s", e.message);
					}
				}

				var cache_obj = (root != null && root.get_node_type() == Json.NodeType.OBJECT)
				? root.get_object()
				: new Json.Object();

				var metadata = new Json.Object();
				metadata.set_string_member("manufacturer", manufacturer);
				metadata.set_string_member("model", model);
				metadata.set_int_member("last_width", width);
				metadata.set_int_member("last_height", height);
				metadata.set_int_member("last_scale", scale);
				metadata.set_int_member("last_seen", (int64) GLib.get_real_time());

				cache_obj.set_object_member(connector, metadata);

				var gen = new Json.Generator();
				var new_root = new Json.Node(Json.NodeType.OBJECT);
				new_root.set_object(cache_obj);
				gen.set_root(new_root);

				panel_settings.set_string("monitor-metadata-cache", gen.to_data(null));
			}

			/**
			* Get cached metadata for a monitor
			*/
			private MonitorMetadata? get_cached_metadata(string connector) {
				if (panel_settings == null) return null;

				string cache_json = panel_settings.get_string("monitor-metadata-cache");
				if (cache_json == "" || cache_json == "{}") {
					return null;
				}

				var parser = new Json.Parser();
				try {
					parser.load_from_data(cache_json);
				} catch (Error e) {
					debug("Failed to parse metadata cache for %s: %s", connector, e.message);
					return null;
				}

				var root = parser.get_root();
				if (root == null || root.get_node_type() != Json.NodeType.OBJECT) {
					return null;
				}

				var cache_obj = root.get_object();
				if (!cache_obj.has_member(connector)) {
					return null;
				}

				var metadata_obj = cache_obj.get_object_member(connector);
				MonitorMetadata metadata = MonitorMetadata() {
					manufacturer = metadata_obj.get_string_member("manufacturer"),
					model = metadata_obj.get_string_member("model"),
					last_width = (int) metadata_obj.get_int_member("last_width"),
					last_height = (int) metadata_obj.get_int_member("last_height"),
					last_scale = (int) metadata_obj.get_int_member("last_scale")
				};

				return metadata;
			}

			/**
			* Get the connector name of the current primary monitor
			*/
			public string? get_primary_connector() {
				return current_primary_connector;
			}

			/**
			* Get the number of currently connected monitors
			*/
			public uint get_monitor_count() {
				if (screen == null) {
					return 0;
				}
				unowned GLib.List<Xfw.Monitor> monitors = screen.get_monitors();
				return monitors != null ? monitors.length() : 0;
			}

			/**
			* Get list of currently available monitors with their information
			*/
			public MonitorInfo[] get_available_monitors() {
				MonitorInfo[] monitors = {};

				if (screen == null) {
					return monitors;
				}

				unowned GLib.List<Xfw.Monitor> xfw_monitors = screen.get_monitors();
				if (xfw_monitors == null) {
					return monitors;
				}

				string? current_primary = get_primary_connector();
				int index = 0;

				foreach (var xfw_mon in xfw_monitors) {
					var gdk_mon = xfw_mon.get_gdk_monitor();
					if (gdk_mon != null) {
						string? connector = xfw_mon.get_connector();
						var geom = xfw_mon.get_logical_geometry();
						int scale = (int) xfw_mon.get_scale();
						string manufacturer = gdk_mon.get_manufacturer() ?? "Unknown";
						string model = gdk_mon.get_model() ?? "Unknown";

						if (connector != null) {
							cache_monitor_metadata(connector, manufacturer, model, geom.width, geom.height, scale);
						}

						MonitorInfo info = MonitorInfo() {
							connector = connector ?? "Unknown-%d".printf(index),
							index = index,
							width = geom.width,
							height = geom.height,
							scale_factor = scale,
							is_current_primary = (connector == current_primary),
							is_connected = true,
							manufacturer = manufacturer,
							model = model
						};

						monitors += info;
						index++;
					}
				}

				return monitors;
			}

			/**
			* Get information for a specific monitor by connector name
			* This works even if the monitor is disconnected (uses cached data)
			*/
			public MonitorInfo? get_monitor_info(string connector) {
				var connected = get_available_monitors();
				foreach (var mon in connected) {
					if (mon.connector == connector) {
						return mon;
					}
				}

				var metadata = get_cached_metadata(connector);
				if (metadata == null) {
					return null;
				}

				MonitorInfo info = MonitorInfo() {
					connector = connector,
					index = -1,
					width = metadata.last_width,
					height = metadata.last_height,
					scale_factor = metadata.last_scale,
					is_current_primary = false,
					is_connected = false,
					manufacturer = metadata.manufacturer,
					model = metadata.model
				};

				return info;
			}

			private void on_monitors_changed_smoothed() {
				// Ignore monitor changes during screen power suspend
				if (screen_power_suspended) {
					debug("Ignoring monitor change - screen power is suspended");
					return;
				}

				if (smooth_timeout != 0) {
					Source.remove(smooth_timeout);
				}

				smooth_timeout = Timeout.add(SMOOTH_MS, on_smooth_timeout);
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
			*/
			private bool poll_for_monitor() {
				initialization_attempts++;

				primary_monitor = get_budgie_primary_monitor();

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
			}

			private bool validate_monitor_reference() {
				if (!_is_valid || _gdk_monitor == null) {
					return false;
				}

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

			private void on_monitors_changed() {
				// Check if the current primary monitor is still connected
				string? current_primary = null;

				// Get the first entry from primary-monitor-list
				if (panel_settings != null) {
					string[] primary_list = panel_settings.get_strv("primary-monitor-list");
					if (primary_list.length > 0) {
						current_primary = primary_list[0];
					}
				}

				if (current_primary != null && current_primary != "") {
					bool primary_still_connected = false;

					unowned GLib.List<Xfw.Monitor> monitors = screen.get_monitors();
					foreach (unowned Xfw.Monitor mon in monitors) {
						if (mon.get_connector() == current_primary) {
							primary_still_connected = true;
							break;
						}
					}

					if (!primary_still_connected) {
						// Primary disconnected - start grace period if not already running
						if (missing_primary_connector == null) {
							debug("Primary monitor %s disconnected - starting %d second grace period",
							current_primary, (int)PRIMARY_GRACE_PERIOD_MS / 1000);
							missing_primary_connector = current_primary;

							// Cancel any existing timeout
							if (missing_primary_timeout != 0) {
								Source.remove(missing_primary_timeout);
							}

							// Set grace period timeout
							missing_primary_timeout = Timeout.add(PRIMARY_GRACE_PERIOD_MS, on_grace_period_expired);

							// Don't proceed with monitor change yet - wait for grace period
							return;
						} else {
							// Grace period already running - just ignore this change
							debug("Grace period active for %s - ignoring change", missing_primary_connector);
							return;
						}
					} else {
						// Primary is connected - cancel grace period if running
						if (missing_primary_connector != null) {
							debug("Primary monitor %s reconnected during grace period - cancelling fallback",
							missing_primary_connector);
							if (missing_primary_timeout != 0) {
								Source.remove(missing_primary_timeout);
								missing_primary_timeout = 0;
							}
							missing_primary_connector = null;
						}
					}
				}

				// Normal monitor change processing
				poll_for_monitor();
			}

			private bool on_grace_period_expired() {
				debug("Grace period expired for %s - allowing fallback switch",
				missing_primary_connector);
				missing_primary_timeout = 0;
				missing_primary_connector = null;

				// Now trigger the actual monitor change
				poll_for_monitor();
				return false;
			}

			// provide monitor info
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
