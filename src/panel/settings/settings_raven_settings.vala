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
	public class RavenSettingsPage : Budgie.SettingsGrid {
		private Gtk.ComboBox? raven_position;
		private Gtk.ComboBox? notification_sort;
		private Settings raven_settings;

		public RavenSettingsPage() {
			margin_top = 8;
			margin_start = 20;
			margin_end = 20;

			raven_position = new Gtk.ComboBox();
			notification_sort = new Gtk.ComboBox();

			// Add options for Raven position
			var render = new Gtk.CellRendererText();
			var model = new Gtk.ListStore(3, typeof(string), typeof(string), typeof(RavenPosition));
			Gtk.TreeIter iter;
			const RavenPosition[] positions = {
				RavenPosition.AUTOMATIC,
				RavenPosition.LEFT,
				RavenPosition.RIGHT
			};

			foreach (var pos in positions) {
				model.append(out iter);
				model.set(iter, 0, pos.to_string(), 1, pos.get_display_name(), 2, pos, -1);
			}

			raven_position.set_model(model);
			raven_position.pack_start(render, true);
			raven_position.add_attribute(render, "text", 1);
			raven_position.set_id_column(0);

			add_row(new SettingsRow(raven_position,
				_("Set Raven position"),
				_("Set which side of the screen Raven will open on. If set to Automatic, Raven will open where its parent panel is.")
			));

			// Add option for Notification sorting
			var noti_renderer = new Gtk.CellRendererText();
			var noti_model = new Gtk.ListStore(3, typeof(string), typeof(string), typeof(NotificationSort));
			Gtk.TreeIter noti_iter;
			const NotificationSort[] sortings = {
				NEW_OLD,
				OLD_NEW,
			};

			foreach (var sort in sortings) {
				noti_model.append(out noti_iter);
				noti_model.set(noti_iter, 0, sort.to_string(), 1, sort.get_display_name(), 2, sort, -1);
			}

			notification_sort.set_model(noti_model);
			notification_sort.pack_start(noti_renderer, true);
			notification_sort.add_attribute(noti_renderer, "text", 1);
			notification_sort.set_id_column(0);

			add_row(new SettingsRow(notification_sort,
				_("Set notification sort order"),
				_("Set whether notifications are sorted from oldest to newest, or newest to oldest.")
			));

			// Bind the settings to our comboboxes
			raven_settings = new Settings("com.solus-project.budgie-raven");
			raven_settings.bind("raven-position", raven_position, "active-id", SettingsBindFlags.DEFAULT);
			raven_settings.bind("notification-sort", notification_sort, "active-id", SettingsBindFlags.DEFAULT);
		}
	}
}
