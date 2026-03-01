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
	 * Handles matching windows to desktop application files.
	 *
	 * This class implements the window-to-desktop-ID matching methods
	 * inspired by GNOME Shell, KDE Plasma, and BAMF. It handles:
	 * - StartupWMClass matching (primary method)
	 * - Reverse-DNS naming (com.example.App)
	 * - Java package naming (org-gjt-sp-jedit-jEdit)
	 * - Snap naming patterns (snap-name_app-name)
	 * - Case-insensitive fallbacks
	 */
	public class ApplicationMatcher : GLib.Object {
		/**
		 * Result of a matching operation.
		 */
		public class MatchResult {
			public string? desktop_id { get; set; }

			public bool matched() {
				return desktop_id != null;
			}
		}

		/**
		 * Find the desktop ID that matches a window.
		 *
		 * @param window The window to match
		 * @return MatchResult containing the desktop ID and match method, or null if not found
		 */
		public MatchResult match_window(Xfw.Window window) {
			var match_result = new MatchResult();
			var class_ids = window.get_class_ids();
			if (class_ids == null || class_ids.length == 0) {
				debug(@"Got no class_ids for window='$(window.get_name())");
				return match_result;
			}

			string instance = class_ids[0];
			string? class_name = null;

			if (class_ids.length > 1 && class_ids[1] != null && class_ids[1].length > 0) {
				class_name = class_ids[1];
			}

			debug(@"Matching WM_CLASS instance='$instance', class='$(class_name ?? "")'");

			// Extract all possible name variants from the instance
			string[] variants = extract_name_variants(instance);

			// Search all installed desktop files
			var apps = AppInfo.get_all();
			foreach (var app_info in apps) {
				if (!(app_info is DesktopAppInfo)) continue;

				var desktop_info = app_info as DesktopAppInfo;
				var desktop_id = desktop_info.get_id();
				if (desktop_id == null) continue;

				// Try each matching strategy in priority order
				match_result = try_startup_wm_class(desktop_info, desktop_id, instance, class_name, variants);
				if (match_result.matched()) return match_result;

				match_result = try_desktop_id_match(desktop_info, desktop_id, instance, class_name, variants);
				if (match_result.matched()) return match_result;

				match_result = try_reverse_dns_match(desktop_info, desktop_id, instance, class_name, variants);
				if (match_result.matched()) return match_result;

				match_result = try_snap_pattern_match(desktop_info, desktop_id, instance, class_name, variants);
				if (match_result.matched()) return match_result;

				match_result = try_instance_to_exec_match(desktop_info, desktop_id, instance);
				if (match_result.matched()) return match_result;
			}

			debug(@"No match found for instance='$instance'");
			return match_result;
		}

		/**
		 * Find the desktop ID that matches a window group.
		 *
		 * @param group The window group to match
		 * @return MatchResult or null if no window available or no match
		 */
		public MatchResult match_window_group(Budgie.Windowing.WindowGroup group) {
			var window = group.get_first_window();
			if (window == null) {
				return new MatchResult();
			}

			return match_window(window);
		}

		/**
		 * Create a Budgie.Application from a desktop ID.
		 *
		 * @param desktop_id The desktop file ID (e.g., "firefox.desktop")
		 * @return Application object or null if creation failed
		 */
		public Budgie.Application? create_application(string desktop_id) {
			var app_info = new DesktopAppInfo(desktop_id);
			if (app_info == null) {
				warning(@"Failed to create DesktopAppInfo for '$desktop_id'");
				return null;
			}

			return new Budgie.Application(app_info);
		}

		/**
		 * Check StartupWMClass field in desktop file.
		 */
		private MatchResult try_startup_wm_class(
			DesktopAppInfo desktop_info,
			string desktop_id,
			string instance,
			string? class_name,
			string[] variants
		) {
			var wm_class = desktop_info.get_startup_wm_class();
			if (wm_class == null || wm_class.length == 0) {
				return new MatchResult();
			}

			if (matches_any_variant(wm_class, instance, variants)) {
				debug(@"Matched via StartupWMClass: $desktop_id");
				return create_match_result(desktop_id);
			}

			if (class_name != null && wm_class.down() == class_name.down()) {
				debug(@"Matched via StartupWMClass (class): $desktop_id");
				return create_match_result(desktop_id);
			}

			return new MatchResult();
		}

		/**
		 * Check if desktop file ID matches WM_CLASS.
		 */
		private MatchResult try_desktop_id_match(
			DesktopAppInfo desktop_info,
			string desktop_id,
			string instance,
			string? class_name,
			string[] variants
		) {
			var id_base = desktop_id.has_suffix(".desktop")
				? desktop_id.substring(0, desktop_id.length - 8)
				: desktop_id;

			if (matches_any_variant(id_base, instance, variants)) {
				debug(@"Matched via desktop ID: $desktop_id");
				return create_match_result(desktop_id);
			}

			if (class_name != null && id_base.down() == class_name.down()) {
				debug(@"Matched via desktop ID (class): $desktop_id");
				return create_match_result(desktop_id);
			}

			return new MatchResult();
		}

		/**
		 * Handle reverse-DNS naming (com.example.App).
		 */
		private MatchResult try_reverse_dns_match(
			DesktopAppInfo desktop_info,
			string desktop_id,
			string instance,
			string? class_name,
			string[] variants
		) {
			var id_base = desktop_id.has_suffix(".desktop")
				? desktop_id.substring(0, desktop_id.length - 8)
				: desktop_id;
			var match_result = new MatchResult();

			if (!id_base.contains(".")) return match_result;

			var parts = id_base.split(".");
			if (parts.length <= 1) return match_result;

			var last_part = parts[parts.length - 1];

			if (matches_any_variant(last_part, instance, variants)) {
				debug(@"Matched via reverse-DNS: $desktop_id");
				match_result = create_match_result(desktop_id);
			}

			if (match_result.matched()) return match_result;

			if (class_name != null && last_part.down() == class_name.down()) {
				debug(@"Matched via reverse-DNS (class): $desktop_id");
				match_result = create_match_result(desktop_id);
			}

			return match_result;
		}

		/**
		 * Handle snap naming pattern (snap-name_app-name).
		 */
		private MatchResult try_snap_pattern_match(
			DesktopAppInfo desktop_info,
			string desktop_id,
			string instance,
			string? class_name,
			string[] variants
		) {
			var id_base = desktop_id.has_suffix(".desktop")
				? desktop_id.substring(0, desktop_id.length - 8)
				: desktop_id;

			var match_result = new MatchResult();

			if (!id_base.contains("_")) return match_result;

			var snap_parts = id_base.split("_");
			if (snap_parts.length < 2) return match_result;

			var snap_name = snap_parts[0];

			if (matches_any_variant(snap_name, instance, variants)) {
				debug(@"Matched via snap pattern: $desktop_id");
				match_result = create_match_result(desktop_id);
			}

			return match_result;
		}

		/**
		* Handle attempting to match the instance name and transformations of it to the exec in the desktop file
	 	*/
		private MatchResult try_instance_to_exec_match(
			DesktopAppInfo desktop_info,
			string desktop_id,
			string instance
		) {
			var exec = Path.get_basename(desktop_info.get_executable());
			if (instance == exec) {
				debug(@"Matched via InstanceToExec: $desktop_id");
				return create_match_result(desktop_id);
			}

			if (!instance.contains(" ")) return new MatchResult(); // No whitespace, return early since subsequent logic requires it

			var instance_dash = instance.replace(" ", "-");
			var instance_dot = instance.replace(" ", ".");

			if (instance_dash == exec || instance_dot == exec) {
				debug(@"Matched via InstanceToExec: $desktop_id");
				return create_match_result(desktop_id);
			}
			return new MatchResult();
		}

		/**
		 * Extract all possible name variants from a WM_CLASS instance.
		 *
		 * Handles:
		 * - Reverse-DNS: com.example.App → ["com.example.App", "App"]
		 * - Java packages: org-gjt-sp-jedit-jEdit → ["org-gjt-sp-jedit-jEdit", "jEdit", "jedit", "org"]
		 * - Dashed names: brave-browser → ["brave-browser", "browser", "brave"]
		 *
		 * @param instance The WM_CLASS instance string
		 * @return Array of possible name variants
		 */
		private string[] extract_name_variants(string instance) {
			var variants = new string[]{};

			// Always include original
			variants += instance;

			// Handle dot-separated (reverse-DNS, Java packages)
			if (instance.contains(".")) {
				var parts = instance.split(".");
				if (parts.length > 1) {
					var last = parts[parts.length - 1];
					add_unique(ref variants, last);
				}
			}

			// Handle dash-separated
			if (instance.contains("-")) {
				var parts = instance.split("-");
				if (parts.length > 1) {
					add_unique(ref variants, parts[parts.length - 1]);
					add_unique(ref variants, parts[0]);
				}
			}

			// Add lowercase variants
			foreach (var variant in variants.copy()) {
				var lower = variant.down();
				if (lower != variant) {
					add_unique(ref variants, lower);
				}
			}

			return variants;
		}

		/**
		 * Check if target matches any variant (case-insensitive).
		 */
		private bool matches_any_variant(string target, string original, string[] variants) {
			var target_lower = target.down();

			if (target_lower == original.down()) {
				return true;
			}

			foreach (var variant in variants) {
				if (target_lower == variant.down()) {
					return true;
				}
			}

			return false;
		}

		/**
		 * Add string to array if not already present.
		 */
		private void add_unique(ref string[] array, string value) {
			foreach (var item in array) {
				if (item == value) {
					return;
				}
			}

			var old_length = array.length;
			array.resize(old_length + 1);
			array[old_length] = value;
		}

		/**
		 * Create a MatchResult object.
		 */
		private MatchResult create_match_result(string desktop_id) {
			var result = new MatchResult();
			result.desktop_id = desktop_id;
			return result;
		}
	}
}
