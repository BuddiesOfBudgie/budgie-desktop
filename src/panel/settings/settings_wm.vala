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
	* WindowsPage allows users to control window manager settings
	*/
	public class WindowsPage : Budgie.SettingsPage {
		private Settings budgie_wm_settings;
		private Gtk.Switch center_windows;
		private Gtk.Switch disable_night_light;
		private Gtk.Switch pause_notifications;
		private Gtk.ComboBox combo_layouts;
		private Gtk.ComboBox combo_window_focus_mode;
		private Gtk.Switch switch_tiling;
		private Gtk.Switch switch_all_windows_tabswitcher;

		public WindowsPage() {
			Object(group: SETTINGS_GROUP_APPEARANCE,
				content_id: "windows",
				title: _("Windows"),
				display_weight: 4,
				icon_name: "preferences-system-windows");

			var grid = new SettingsGrid();
			this.add(grid);

			combo_layouts = new Gtk.ComboBox();
			grid.add_row(new SettingsRow(combo_layouts,
				_("Button layout"),
				_("Change the layout of buttons in application titlebars.")
			));

			center_windows = new Gtk.Switch();
			grid.add_row(new SettingsRow(center_windows,
				_("Center new windows on screen"),
				_("Center newly launched windows on the current screen.")
			));

			disable_night_light = new Gtk.Switch();
			grid.add_row(new SettingsRow(disable_night_light,
				_("Disable Night Light mode when windows are fullscreen"),
				_("Disables Night Light mode when a window is fullscreen. Re-enables when leaving fullscreen.")
			));

			pause_notifications = new Gtk.Switch();
			grid.add_row(new SettingsRow(pause_notifications,
				_("Pause notifications when windows are fullscreen"),
				_("Prevents notifications from appearing when a window is fullscreen. Unpauses when leaving fullscreen.")
			));

			switch_tiling = new Gtk.Switch();
			grid.add_row(new SettingsRow(switch_tiling,
				_("Automatic tiling"),
				_("Windows will automatically tile when dragged into the top of the screen or the far corners.")
			));

			combo_window_focus_mode = new Gtk.ComboBox();
			grid.add_row(new SettingsRow(combo_window_focus_mode,
				_("Window focus mode"),
				_("Choose how windows receive focus: click to focus; sloppy to focus without raising windows; mouse to focus with raising.")
			));

			switch_all_windows_tabswitcher = new Gtk.Switch();
			grid.add_row(new SettingsRow(switch_all_windows_tabswitcher,
				_("Show all windows in tab switcher"),
				_("All tabs will be displayed in tab switcher regardless of the workspace in use.")
			));

			/* Button layout */
			var model = new Gtk.ListStore(2, typeof(string), typeof(string));
			Gtk.TreeIter iter;
			model.append(out iter);
			model.set(iter, 0, "traditional", 1, _("Right (standard)"), -1);
			model.append(out iter);
			model.set(iter, 0, "left", 1, _("Left"), -1);
			combo_layouts.set_model(model);
			combo_layouts.set_id_column(0);

			var render = new Gtk.CellRendererText();
			combo_layouts.pack_start(render, true);
			combo_layouts.add_attribute(render, "text", 1);
			combo_layouts.set_id_column(0);

			/* Window Focus Mode */
			var focus_model = new Gtk.ListStore(2, typeof(string), typeof(string));
			Gtk.TreeIter focus_iter;
			focus_model.append(out focus_iter);
			focus_model.set(focus_iter, 0, "click", 1, _("Click"), -1);
			focus_model.append(out focus_iter);
			focus_model.set(focus_iter, 0, "sloppy", 1, _("Sloppy"), -1);
			focus_model.append(out focus_iter);
			focus_model.set(focus_iter, 0, "mouse", 1, _("Mouse"), -1);
			combo_window_focus_mode.set_model(focus_model);
			combo_window_focus_mode.set_id_column(0);

			var focus_render = new Gtk.CellRendererText();
			combo_window_focus_mode.pack_start(focus_render, true);
			combo_window_focus_mode.add_attribute(focus_render, "text", 1);
			combo_window_focus_mode.set_id_column(0);

			/* Hook up settings */
			budgie_wm_settings = new Settings("com.solus-project.budgie-wm");
			budgie_wm_settings.bind("button-style", combo_layouts, "active-id", SettingsBindFlags.DEFAULT);
			budgie_wm_settings.bind("center-windows", center_windows, "active", SettingsBindFlags.DEFAULT);
			budgie_wm_settings.bind("disable-night-light-on-fullscreen", disable_night_light, "active", SettingsBindFlags.DEFAULT);
			budgie_wm_settings.bind("pause-notifications-on-fullscreen", pause_notifications, "active", SettingsBindFlags.DEFAULT);
			budgie_wm_settings.bind("edge-tiling", switch_tiling, "active", SettingsBindFlags.DEFAULT);
			budgie_wm_settings.bind("window-focus-mode", combo_window_focus_mode, "active-id", SettingsBindFlags.DEFAULT);
			budgie_wm_settings.bind("show-all-windows-tabswitcher", switch_all_windows_tabswitcher, "active", SettingsBindFlags.DEFAULT);
		}
	}
}
