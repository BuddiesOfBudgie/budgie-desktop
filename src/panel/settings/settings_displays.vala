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
	public class DisplaysPage : SettingsPage {
		private unowned DesktopManager? manager;
		private Settings panel_settings;
		private Gtk.ListBox monitor_list;
		private Gtk.ListBox fallback_list;
		private WaylandClient? wayland_client = null;

		public DisplaysPage(DesktopManager? manager) {
			Object(group: SETTINGS_GROUP_PANEL,
				content_id: "displays",
				title: _("Displays"),
				display_weight: 0,
				icon_name: "video-display");

			this.manager = manager;
			panel_settings = new Settings("com.solus-project.budgie-panel");
			wayland_client = new WaylandClient();

			var grid = new SettingsGrid();
			this.add(grid);

			// Connected monitors section
			var header_label = new Gtk.Label(null);
			header_label.set_markup("<b>%s</b>".printf(_("Connected Monitors")));
			header_label.set_xalign(0.0f);
			header_label.margin_bottom = 6;
			grid.add_row(new SettingsRow(header_label, null, null));

			var desc_label = new Gtk.Label(_("Select which monitor should be the primary display for panel placement."));
			desc_label.get_style_context().add_class("dim-label");
			desc_label.set_line_wrap(true);
			desc_label.set_xalign(0.0f);
			desc_label.margin_bottom = 12;
			grid.add_row(new SettingsRow(desc_label, null, null));

			var frame = new Gtk.Frame(null);
			monitor_list = new Gtk.ListBox();
			monitor_list.set_selection_mode(Gtk.SelectionMode.NONE);

			var scroll = new Gtk.ScrolledWindow(null, null);
			scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
			scroll.set_min_content_height(150);
			scroll.add(monitor_list);
			frame.add(scroll);

			grid.add_row(new SettingsRow(frame, null, null));

			var clear_button = new Gtk.Button.with_label(_("Use Automatic Selection"));
			clear_button.clicked.connect(on_clear_button_clicked);

			grid.add_row(new SettingsRow(clear_button,
				_("Clear Primary Monitor"),
				_("Remove manual primary monitor selection and use automatic detection.")
			));

			// Fallback monitors section
			var fallback_header = new Gtk.Label(null);
			fallback_header.set_markup("<b>%s</b>".printf(_("Fallback Monitors")));
			fallback_header.set_xalign(0.0f);
			fallback_header.margin_top = 24;
			fallback_header.margin_bottom = 6;
			grid.add_row(new SettingsRow(fallback_header, null, null));

			var fallback_desc = new Gtk.Label(_("Previously used monitors. Use in the order given when the primary monitor is disconnected."));
			fallback_desc.get_style_context().add_class("dim-label");
			fallback_desc.set_line_wrap(true);
			fallback_desc.set_xalign(0.0f);
			fallback_desc.margin_bottom = 12;
			grid.add_row(new SettingsRow(fallback_desc, null, null));

			var fallback_frame = new Gtk.Frame(null);
			fallback_list = new Gtk.ListBox();
			fallback_list.set_selection_mode(Gtk.SelectionMode.NONE);

			var fallback_scroll = new Gtk.ScrolledWindow(null, null);
			fallback_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
			fallback_scroll.set_min_content_height(100);
			fallback_scroll.add(fallback_list);
			fallback_frame.add(fallback_scroll);

			grid.add_row(new SettingsRow(fallback_frame, null, null));

			if (wayland_client != null) {
				wayland_client.primary_monitor_changed.connect(on_wayland_primary_monitor_changed);
			}

			if (manager != null) {
				manager.panels_changed.connect(refresh_monitor_list);
			}

			// Set initial visibility before showing
			update_visibility();

			// Only refresh if visible
			if (this.get_visible()) {
				refresh_monitor_list();
				refresh_fallback_list();
			}
		}

		private void update_visibility() {
			if (wayland_client == null) {
				return;
			}

			uint monitor_count = wayland_client.get_monitor_count();
			bool should_show = (monitor_count > 1);

			debug("DisplaysPage visibility: monitor_count=%u, should_show=%s", monitor_count, should_show.to_string());

			this.visible = should_show;
			this.no_show_all = !should_show;

			// Notify parent window to refresh filter
			var toplevel = this.get_toplevel() as SettingsWindow;
			if (toplevel != null) {
				toplevel.refresh_sidebar_filter();
			}
		}

		private void on_clear_button_clicked() {
			var panel_manager = manager as PanelManager;
			if (panel_manager != null) {
				panel_manager.clear_primary_monitor();
				refresh_monitor_list();
			}
		}

		private void on_wayland_primary_monitor_changed() {
			update_visibility();
			refresh_monitor_list();
		}

		private void refresh_monitor_list() {
			monitor_list.foreach((widget) => {
				monitor_list.remove(widget);
			});

			if (manager == null) {
				return;
			}

			var panel_manager = manager as PanelManager;
			if (panel_manager == null) {
				return;
			}

			var monitors = panel_manager.get_available_monitors();
			string? configured_primary = panel_manager.get_configured_primary();

			if (monitors.length == 0) {
				var no_monitors = new Gtk.Label(_("No monitors detected"));
				no_monitors.get_style_context().add_class("dim-label");
				no_monitors.margin = 12;
				monitor_list.add(no_monitors);
				monitor_list.show_all();
				return;
			}

			foreach (var monitor in monitors) {
				var row = create_monitor_row(monitor, configured_primary);
				monitor_list.add(row);
			}

			monitor_list.show_all();
			refresh_fallback_list();
		}

		private void refresh_fallback_list() {
			fallback_list.foreach((widget) => {
				fallback_list.remove(widget);
			});

			var panel_manager = manager as PanelManager;
			if (panel_manager == null) {
				return;
			}

			string[] fallbacks = panel_manager.get_fallback_monitors();

			if (fallbacks.length == 0) {
				var no_fallbacks = new Gtk.Label(_("No fallback monitors configured"));
				no_fallbacks.get_style_context().add_class("dim-label");
				no_fallbacks.margin = 12;
				fallback_list.add(no_fallbacks);
				fallback_list.show_all();
				return;
			}

			foreach (string connector in fallbacks) {
				var monitor_info = panel_manager.get_monitor_info(connector);
				var row = create_fallback_row(connector, monitor_info);
				fallback_list.add(row);
			}

			fallback_list.show_all();
		}

		private Gtk.ListBoxRow create_monitor_row(MonitorInfo monitor, string? configured_primary) {
			var row = new Gtk.ListBoxRow();
			row.set_activatable(false);

			var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
			box.margin = 8;

			var icon = new Gtk.Image.from_icon_name("video-display", Gtk.IconSize.DIALOG);
			icon.pixel_size = 48;
			box.pack_start(icon, false, false, 0);

			var info_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);

			var name_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
			var name_label = new Gtk.Label(null);
			name_label.set_markup("<b>%s</b>".printf(GLib.Markup.escape_text(monitor.connector)));
			name_label.set_xalign(0.0f);
			name_box.pack_start(name_label, false, false, 0);

			if (monitor.is_current_primary) {
				var primary_badge = new Gtk.Label(_("Primary"));
				primary_badge.get_style_context().add_class("dim-label");
				var badge_frame = new Gtk.Frame(null);
				badge_frame.get_style_context().add_class("badge");
				badge_frame.add(primary_badge);
				primary_badge.margin = 2;
				primary_badge.margin_start = 6;
				primary_badge.margin_end = 6;
				name_box.pack_start(badge_frame, false, false, 0);
			}

			info_box.pack_start(name_box, false, false, 0);

			string model_info = "";
			bool has_manufacturer = monitor.manufacturer != "Unknown" && monitor.manufacturer.length > 0;
			bool has_model = monitor.model != "Unknown" && monitor.model.length > 0;

			if (has_manufacturer && has_model) {
				model_info = "%s %s".printf(monitor.manufacturer, monitor.model);
			} else if (has_manufacturer) {
				model_info = monitor.manufacturer;
			} else if (has_model) {
				model_info = monitor.model;
			} else {
				model_info = _("Unknown model");
			}

			var model_label = new Gtk.Label(model_info);
			model_label.get_style_context().add_class("dim-label");
			model_label.set_xalign(0.0f);
			info_box.pack_start(model_label, false, false, 0);

			var res_text = "%d × %d".printf(monitor.width, monitor.height);
			if (monitor.scale_factor > 1) {
				res_text += " @ %d×".printf(monitor.scale_factor);
			}
			var res_label = new Gtk.Label(res_text);
			res_label.get_style_context().add_class("dim-label");
			res_label.set_xalign(0.0f);
			info_box.pack_start(res_label, false, false, 0);

			box.pack_start(info_box, true, true, 0);

			bool is_configured = (configured_primary != null && monitor.connector == configured_primary);

			if (!monitor.is_current_primary || !is_configured) {
				var set_button = new Gtk.Button.with_label(_("Set as Primary"));
				set_button.get_style_context().add_class("suggested-action");
				set_button.valign = Gtk.Align.CENTER;
				set_button.set_data("monitor-connector", monitor.connector);
				set_button.clicked.connect(on_set_primary_button_clicked);
				box.pack_end(set_button, false, false, 0);
			}

			row.add(box);
			return row;
		}

		private void on_set_primary_button_clicked(Gtk.Button button) {
			string connector = button.get_data<string>("monitor-connector");
			var panel_manager = manager as PanelManager;
			if (panel_manager != null) {
				panel_manager.set_primary_monitor(connector);
				refresh_monitor_list();
			}
		}

		private Gtk.ListBoxRow create_fallback_row(string connector, MonitorInfo? info) {
			var row = new Gtk.ListBoxRow();
			row.set_activatable(false);

			var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
			box.margin = 8;

			string icon_name = (info != null && info.is_connected) ? "video-display" : "video-display-symbolic";
			var icon = new Gtk.Image.from_icon_name(icon_name, Gtk.IconSize.DND);
			if (info == null || !info.is_connected) {
				icon.get_style_context().add_class("dim-label");
			}
			box.pack_start(icon, false, false, 0);

			var info_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);

			var name_label = new Gtk.Label(null);
			name_label.set_markup("<b>%s</b>".printf(GLib.Markup.escape_text(connector)));
			name_label.set_xalign(0.0f);
			info_box.pack_start(name_label, false, false, 0);

			if (info != null) {
				string model_info = "";
				if (info.manufacturer != "Unknown" && info.model != "Unknown") {
					model_info = "%s %s".printf(info.manufacturer, info.model);
				} else if (info.manufacturer != "Unknown") {
					model_info = info.manufacturer;
				} else if (info.model != "Unknown") {
					model_info = info.model;
				}

				if (model_info != "") {
					var model_label = new Gtk.Label(model_info);
					model_label.get_style_context().add_class("dim-label");
					model_label.set_xalign(0.0f);
					info_box.pack_start(model_label, false, false, 0);
				}

				var res_text = "%d × %d".printf(info.width, info.height);
				if (info.scale_factor > 1) {
					res_text += " @ %d×".printf(info.scale_factor);
				}
				if (!info.is_connected) {
					res_text += " " + _("(last known)");
				}
				var res_label = new Gtk.Label(res_text);
				res_label.get_style_context().add_class("dim-label");
				res_label.set_xalign(0.0f);
				info_box.pack_start(res_label, false, false, 0);
			} else {
				var unknown_label = new Gtk.Label(_("No cached information"));
				unknown_label.get_style_context().add_class("dim-label");
				unknown_label.set_xalign(0.0f);
				info_box.pack_start(unknown_label, false, false, 0);
			}

			box.pack_start(info_box, true, true, 0);

			if (info != null && info.is_connected) {
				var connected_badge = new Gtk.Label(_("Connected"));
				connected_badge.get_style_context().add_class("dim-label");
				var badge_frame = new Gtk.Frame(null);
				badge_frame.get_style_context().add_class("badge");
				badge_frame.add(connected_badge);
				connected_badge.margin = 2;
				connected_badge.margin_start = 6;
				connected_badge.margin_end = 6;
				badge_frame.valign = Gtk.Align.CENTER;
				box.pack_end(badge_frame, false, false, 0);
			}

			var remove_button = new Gtk.Button.from_icon_name("edit-delete-symbolic", Gtk.IconSize.MENU);
			remove_button.get_style_context().add_class("flat");
			remove_button.valign = Gtk.Align.CENTER;
			remove_button.set_data("monitor-connector", connector);
			remove_button.clicked.connect(on_remove_fallback_button_clicked);
			box.pack_end(remove_button, false, false, 0);

			row.add(box);
			return row;
		}

		private void on_remove_fallback_button_clicked(Gtk.Button button) {
			string connector = button.get_data<string>("monitor-connector");
			var panel_manager = manager as PanelManager;
			if (panel_manager != null) {
				panel_manager.remove_from_monitor_list(connector);
				refresh_fallback_list();
			}
		}
	}
}
