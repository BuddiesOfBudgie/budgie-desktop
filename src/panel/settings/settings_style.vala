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
	* StylePage simply provides a bunch of theme controls
	*/
	public class StylePage : Budgie.SettingsPage {
		private Gtk.ComboBox? combobox_gtk;
		private Gtk.ComboBox? combobox_icon;
		private Gtk.ComboBox? combobox_cursor;
		private Gtk.ComboBox? combobox_notification_position;
		private Gtk.ComboBox? combobox_color_scheme;
		private Gtk.Switch? switch_dark;
		private Gtk.Switch? switch_builtin;
		private Gtk.Switch? switch_animations;
		private Gtk.ComboBox? labwc_theme_override;
		private Settings ui_settings;
		private Settings budgie_settings;
		private SettingsRow? builtin_row;
		private SettingsRow? labwc_theme_row;
		private ThemeScanner? theme_scanner;
		private bool is_labwc_running = false;

		public StylePage() {
			Object(group: SETTINGS_GROUP_APPEARANCE,
				content_id: "style",
				title: _("Style"),
				display_weight: 0,
				icon_name: "preferences-desktop-theme"
			);

			budgie_settings = new Settings("com.solus-project.budgie-panel");
			ui_settings = new Settings("org.gnome.desktop.interface");

			is_labwc_running = check_labwc_running();

			var group = new Gtk.SizeGroup(Gtk.SizeGroupMode.HORIZONTAL);
			var grid = new SettingsGrid();
			this.add(grid);

			combobox_gtk = new Gtk.ComboBox();
			grid.add_row(new SettingsRow(combobox_gtk,
				_("Widgets"),
				_("Set the appearance of window decorations and controls")));

			combobox_icon = new Gtk.ComboBox();
			grid.add_row(new SettingsRow(combobox_icon,
				_("Icons"),
				_("Set the globally used icon theme")));

			combobox_cursor = new Gtk.ComboBox();
			grid.add_row(new SettingsRow(combobox_cursor,
				_("Cursors"),
				_("Set the globally used mouse cursor theme")));

			combobox_notification_position = new Gtk.ComboBox();
			grid.add_row(new SettingsRow(combobox_notification_position,
				_("Notification Position"),
				_("Set the location for notification popups")));

			combobox_color_scheme = new Gtk.ComboBox();
			grid.add_row(new SettingsRow(combobox_color_scheme,
				_("Color Scheme"),
				_("Set the dark theme preference for applications")));

			/* Stick the combos in a size group */
			group.add_widget(combobox_gtk);
			group.add_widget(combobox_icon);
			group.add_widget(combobox_cursor);
			group.add_widget(combobox_notification_position);
			group.add_widget(combobox_color_scheme);

			switch_dark = new Gtk.Switch();
			grid.add_row(new SettingsRow(switch_dark, _("Dark theme for panel")));

			bool show_builtin = budgie_settings.get_boolean("show-builtin-theme-option");

			if (show_builtin) {
				switch_builtin = new Gtk.Switch();
				builtin_row = new SettingsRow(switch_builtin,
				_("Built-in theme"),
				_("When enabled, the built-in theme will override the desktop component styling"));

				grid.add_row(builtin_row);
			}

			if (is_labwc_running) {
				setup_labwc_theme_override();
				grid.add_row(labwc_theme_row);
				group.add_widget(labwc_theme_override);
			}

			switch_animations = new Gtk.Switch();
			grid.add_row(new SettingsRow(switch_animations,
				_("Animations"),
				_("Control whether windows and controls use animations")));

			/* Add options for notification position */
			var model = new Gtk.ListStore(3, typeof(string), typeof(string), typeof(Budgie.NotificationPosition));

			Gtk.TreeIter iter;
			const Budgie.NotificationPosition[] positions = {
				Budgie.NotificationPosition.TOP_LEFT,
				Budgie.NotificationPosition.TOP_RIGHT,
				Budgie.NotificationPosition.BOTTOM_LEFT,
				Budgie.NotificationPosition.BOTTOM_RIGHT
			};

			foreach (var pos in positions) {
				model.append(out iter);
				model.set(iter, 0, pos.to_string(), 1, notification_position_to_display(pos), 2, pos, -1);
			}

			combobox_notification_position.set_model(model);
			combobox_notification_position.set_id_column(0);

			/* Add options for color scheme */
			var color_scheme_model = new Gtk.ListStore(2, typeof(string), typeof(string));

			Gtk.TreeIter color_scheme_iter;
			string[] color_schemes = { "default", "prefer-light", "prefer-dark" };

			foreach (var color_scheme in color_schemes) {
				color_scheme_model.append(out color_scheme_iter);
				color_scheme_model.set(color_scheme_iter, 0, color_scheme, 1, color_scheme_to_display(color_scheme), -1);
			}

			combobox_color_scheme.set_model(color_scheme_model);
			combobox_color_scheme.set_id_column(0);

			/* Sort out renderers for all of our dropdowns */
			var render = new Gtk.CellRendererText();
			render.width_chars = 1;
			render.ellipsize = Pango.EllipsizeMode.END;
			combobox_gtk.pack_start(render, true);
			combobox_gtk.add_attribute(render, "text", 0);
			combobox_icon.pack_start(render, true);
			combobox_icon.add_attribute(render, "text", 0);
			combobox_cursor.pack_start(render, true);
			combobox_cursor.add_attribute(render, "text", 0);
			combobox_notification_position.pack_start(render, true);
			combobox_notification_position.add_attribute(render, "text", 1);
			combobox_color_scheme.pack_start(render, true);
			combobox_color_scheme.add_attribute(render, "text", 1);

			/* Hook up settings */
			budgie_settings.bind("dark-theme", switch_dark, "active", SettingsBindFlags.DEFAULT);

			if (show_builtin) {
				budgie_settings.bind("builtin-theme", switch_builtin, "active", SettingsBindFlags.DEFAULT);
			}

			budgie_settings.bind("notification-position", combobox_notification_position, "active-id", SettingsBindFlags.DEFAULT);
			ui_settings.bind("color-scheme", combobox_color_scheme, "active-id", SettingsBindFlags.DEFAULT);
			ui_settings.bind("enable-animations", switch_animations, "active", SettingsBindFlags.DEFAULT);
			this.theme_scanner = new ThemeScanner();

			Idle.add(() => {
				this.load_themes();
				return false;
			});
		}

		// Check if labwc is the current window manager
		private bool check_labwc_running() {
			// Try to detect labwc by checking for the process
			try {
				string output;
				int exit_status;
				Process.spawn_command_line_sync("pgrep -x labwc",
					out output,
					null,
					out exit_status);
				return exit_status == 0;
			} catch (SpawnError e) {
				warning("Failed to check for labwc: %s", e.message);
			}

			return false;
		}

		// Scan for available labwc theme files
		private string[] get_labwc_themes() {
			string[] themes = { "use-theme" };
			GenericSet<string> theme_set = new GenericSet<string>(str_hash, str_equal);

			// Scan all system data directories
			foreach (string data_dir in Environment.get_system_data_dirs()) {
				string themes_dir = Path.build_filename(data_dir, "budgie-desktop", "labwc");

				if (!FileUtils.test(themes_dir, FileTest.IS_DIR)) {
					continue;
				}

				try {
					Dir dir = Dir.open(themes_dir, 0);
					string? name = null;

					while ((name = dir.read_name()) != null) {
						if (name.has_prefix("themerc-")) {
							// Extract theme name from filename (themerc-NAME)
							string theme_name = name.substring(8); // Remove "themerc-"
							theme_set.add(theme_name);
						}
					}
				} catch (FileError e) {
					warning("Could not read labwc themes directory %s: %s", themes_dir, e.message);
				}
			}

			// Convert set to array
			theme_set.foreach ((theme) => {
				themes += theme;
			});

			return themes;
		}

		// Get display name for theme
		private string get_theme_display_name(string theme_id) {
			if (theme_id == "use-theme") return _("Use theme");
			// Capitalize first letter
			return theme_id.substring(0, 1).up() + theme_id.substring(1);
		}

		// Get current labwc theme override
		private string get_current_labwc_theme() {
			string config_dir = Path.build_filename(Environment.get_user_config_dir(),
				"budgie-desktop", "labwc");
			string override_path = Path.build_filename(config_dir, "themerc-override");

			// Check if override file exists and is a symlink
			if (FileUtils.test(override_path, FileTest.IS_SYMLINK)) {
				try {
					string target = FileUtils.read_link(override_path);
					// Extract theme name from path
					string basename = Path.get_basename(target);
					if (basename.has_prefix("themerc-")) {
						return basename.substring(8);
					}
				} catch (FileError e) {
					warning("Could not read labwc theme override: %s", e.message);
				}
			}

			return "use-theme";
		}

		// Set labwc theme override
		private void set_labwc_theme(string theme_id) {
			string config_dir = Path.build_filename(Environment.get_user_config_dir(),
				"budgie-desktop", "labwc");
			string override_path = Path.build_filename(config_dir, "themerc-override");

			// Create config directory if it doesn't exist
			DirUtils.create_with_parents(config_dir, 0755);

			// Remove existing override if present
			if (FileUtils.test(override_path, FileTest.EXISTS)) {
				FileUtils.unlink(override_path);
			}

			// If not "use-theme", create symlink to the selected theme
			if (theme_id != "use-theme") {
				string? target = null;

				// Search for theme file in system data directories
				foreach (string data_dir in Environment.get_system_data_dirs()) {
					string theme_path = Path.build_filename(data_dir, "budgie-desktop", "labwc", "themerc-" + theme_id);
					if (FileUtils.test(theme_path, FileTest.EXISTS)) {
						target = theme_path;
						break;
					}
				}

				if (target == null) {
					warning("Could not find labwc theme file for: %s", theme_id);
					return;
				}

				try {
					FileUtils.symlink(target, override_path);
					// Reload labwc configuration
					Process.spawn_command_line_async("labwc -r");
				} catch (Error e) {
					warning("Could not create labwc theme override: %s", e.message);
				}
			} else {
				// Reload labwc to use default theme
				try {
					Process.spawn_command_line_async("labwc -r");
				} catch (SpawnError e) {
					warning("Could not reload labwc: %s", e.message);
				}
			}
		}

		// Setup labwc theme override combo box
		private void setup_labwc_theme_override() {
			labwc_theme_override = new Gtk.ComboBox();

			var model = new Gtk.ListStore(2, typeof(string), typeof(string));
			Gtk.TreeIter iter;

			string[] themes = get_labwc_themes();
			foreach (string theme in themes) {
				model.append(out iter);
				model.set(iter, 0, theme, 1, get_theme_display_name(theme), -1);
			}

			labwc_theme_override.set_model(model);
			labwc_theme_override.set_id_column(0);

			var render = new Gtk.CellRendererText();
			render.width_chars = 1;
			render.ellipsize = Pango.EllipsizeMode.END;
			labwc_theme_override.pack_start(render, true);
			labwc_theme_override.add_attribute(render, "text", 1);

			// Set current value
			labwc_theme_override.active_id = get_current_labwc_theme();

			// Connect change signal
			labwc_theme_override.changed.connect(() => {
				string? theme_id = labwc_theme_override.get_active_id();
				if (theme_id != null) {
					set_labwc_theme(theme_id);
				}
			});

			labwc_theme_row = new SettingsRow(labwc_theme_override,
				_("Labwc Compositor Theme"),
				_("Override the labwc compositor theme independently from the desktop theme.")
			);
		}

		public void load_themes() {
			/* Scan the themes */
			this.theme_scanner.scan_themes.begin(() => {
				/* Gtk themes */ {
					Gtk.TreeIter iter;
					var model = new Gtk.ListStore(1, typeof(string));
					bool hit = false;
					foreach (var theme in theme_scanner.get_gtk_themes()) {
						model.append(out iter);
						model.set(iter, 0, theme, -1);
						hit = true;
					}
					combobox_gtk.set_model(model);
					combobox_gtk.set_id_column(0);
					model.set_sort_column_id(0, Gtk.SortType.ASCENDING);
					if (hit) {
						combobox_gtk.sensitive = true;
						ui_settings.bind("gtk-theme", combobox_gtk, "active-id", SettingsBindFlags.DEFAULT);
					}
				}
				/* Icon themes */ {
					Gtk.TreeIter iter;
					var model = new Gtk.ListStore(1, typeof(string));
					bool hit = false;
					foreach (var theme in theme_scanner.get_icon_themes()) {
						model.append(out iter);
						model.set(iter, 0, theme, -1);
						hit = true;
					}
					combobox_icon.set_model(model);
					combobox_icon.set_id_column(0);
					model.set_sort_column_id(0, Gtk.SortType.ASCENDING);
					if (hit) {
						combobox_icon.sensitive = true;
						ui_settings.bind("icon-theme", combobox_icon, "active-id", SettingsBindFlags.DEFAULT);
					}
				}

				/* Cursor themes */ {
					Gtk.TreeIter iter;
					var model = new Gtk.ListStore(1, typeof(string));
					bool hit = false;
					foreach (var theme in theme_scanner.get_cursor_themes()) {
						model.append(out iter);
						model.set(iter, 0, theme, -1);
						hit = true;
					}
					combobox_cursor.set_model(model);
					combobox_cursor.set_id_column(0);
					model.set_sort_column_id(0, Gtk.SortType.ASCENDING);
					if (hit) {
						combobox_cursor.sensitive = true;
						ui_settings.bind("cursor-theme", combobox_cursor, "active-id", SettingsBindFlags.DEFAULT);
					}
				}
				queue_resize();
			});
		}

		/**
		* Get a user-friendly name for each position.
		*/
		public string notification_position_to_display(Budgie.NotificationPosition position) {
			switch (position) {
				case NotificationPosition.TOP_LEFT:
					return _("Top Left");
				case NotificationPosition.BOTTOM_LEFT:
					return _("Bottom Left");
				case NotificationPosition.BOTTOM_RIGHT:
					return _("Bottom Right");
				case NotificationPosition.TOP_RIGHT:
				default:
					return _("Top Right");
			}
		}

		/**
		* Get a user-friendly name for each color scheme.
		*/
		private string color_scheme_to_display(string color_scheme) {
			switch (color_scheme) {
				case "prefer-light":
					return _("Prefer Light");
				case "prefer-dark":
					return _("Prefer Dark");
				case "default":
				default:
					return _("Default");
				}
		}
	}
}
