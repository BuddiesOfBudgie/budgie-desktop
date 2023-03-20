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
	 * NotificationGroup is a group of notifications.
	 */
	public class NotificationGroup : Gtk.Box {
		public int? count = 0;
		private HashTable<uint32, NotificationWidget>? notifications = null;
		private Gtk.ListBox? list = null;
		private Gtk.Box? header = null;
		private Gtk.Image? app_image = null;
		private Gtk.Label? app_label = null;
		private string? app_name;
		private Gtk.Button? dismiss_button = null;
		private uint? tokeep;

		/**
		 * Signals
		 */
		public signal void dismissed_group(string app_name);
		public signal void dismissed_notification(uint32 id);

		public NotificationGroup(string c_app_icon, string c_app_name, NotificationSort sort_mode, uint keep) {
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 4);
			can_focus = false; // Disable focus to prevent scroll on click
			focus_on_click = false;
			tokeep = keep;

			get_style_context().add_class("raven-notifications-group");

			// Intentially omit _end because it messes with alignment of dismiss buttons
			margin = 4;

			app_name = c_app_name;

			if (("budgie" in c_app_name) && ("caffeine" in c_app_icon)) { // Caffeine Notification
				app_name = _("Caffeine Mode");
			}

			notifications = new HashTable<uint32, NotificationWidget>(direct_hash, direct_equal);
			list = new Gtk.ListBox();
			list.can_focus = false; // Disable focus to prevent scroll on click
			list.focus_on_click = false;
			list.set_selection_mode(Gtk.SelectionMode.NONE);
			set_sort_mode(sort_mode);

			/**
			 * Header creation
			 */
			header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0); // Create our Notification header
			header.get_style_context().add_class("raven-notifications-group-header");

			app_image = new Gtk.Image.from_icon_name(c_app_icon, Gtk.IconSize.DND);
			app_image.halign = Gtk.Align.START;
			app_image.margin_end = 5;
			app_image.set_pixel_size(32); // Really ensure it's 32x32

			app_label = new Gtk.Label(app_name);
			app_label.ellipsize = Pango.EllipsizeMode.END;
			app_label.halign = Gtk.Align.START;
			app_label.justify = Gtk.Justification.LEFT;
			app_label.use_markup = true;

			dismiss_button = new Gtk.Button.from_icon_name("list-remove-all-symbolic", Gtk.IconSize.MENU);
			dismiss_button.get_style_context().add_class("flat");
			dismiss_button.get_style_context().add_class("image-button");
			dismiss_button.valign = Gtk.Align.CENTER;
			dismiss_button.halign = Gtk.Align.END;

			dismiss_button.clicked.connect(dismiss_all);

			header.pack_start(app_image, false, false, 0);
			header.pack_start(app_label, false, false, 0);
			header.pack_end(dismiss_button, false, false, 0);

			pack_start(header);
			pack_start(list);
		}

		/**
		 * add_notification is responsible for adding a notification (if it doesn't exist) and updating our counter
		 */
		public void add_notification(uint32 id, Budgie.Notification notification) {
			if (notifications.contains(id)) { // If this id already exists
				remove_notification(id); // Remove the current one first
			}

			var widget = new NotificationWidget(notification);
			notifications.insert(id, widget);
			list.prepend(widget);

			list.invalidate_sort();
			update_count();

			widget.closed_individually.connect(() => { // When this notification is closed
				uint n_id = (uint) notification.id;
				remove_notification(n_id);
				dismissed_notification(n_id);
			});
		}

		/**
		 * dismiss_all is responsible for dismissing all notifications
		 */
		public void dismiss_all() {
			notifications.foreach_remove((id, notification) => {
				var parent = notification.get_parent();
				list.remove(parent);
				parent.destroy();
				dismissed_notification(id);
				return true;
			});

			update_count();
			dismissed_group(app_name);
		}

		/**
		 * remove_notification is responsible for removing a notification (if it exists) and updating our counter
		 */
		public void remove_notification(uint32 id) {
			var notification = notifications.lookup(id); // Get our notification

			if (notification != null) { // If this notification exists
				notifications.remove(id);
				var parent = notification.get_parent();
				list.remove(parent);
				list.invalidate_sort();
				parent.destroy();
				update_count(); // Update our counter
				dismissed_notification(id); // Notify anything listening
				if (count == 0) { // This was the last notification
					dismissed_group(app_name); // Dismiss the group
				}
			}
		}

		/**
		 * too many notifications will choke raven and the desktop, so let's set a limit;
		 * keep the latest n-notifications of current group, delete older ones
		 */
		public void limit_notifications () {
			GLib.List<uint32> currnotifs = notifications.get_keys();
			currnotifs.sort((a, b) => {
				return (int) (a > b) - (int) (a < b);
			});
			uint n_currnotifs = currnotifs.length();
			/**
			 * no need to reduce if the current number of notifications is below our threshold
			 * and we shouldn't attempt to set a negative uint
			 */
			if (n_currnotifs <= tokeep) return;
			uint n_remove = n_currnotifs - tokeep;
			int count = 0;
			foreach (uint n in currnotifs) {
				if (count < n_remove) {
					remove_notification(n);
				} else {
					break;
				}
				count++;
			}
		}

		/**
		 * if the total number of notifications exceeds threshold, NotificationsView will
		 * update the max number per group ('tokeep')
		 */
		public void set_group_max_notifications(uint keep) {
			tokeep = keep;
		}

		/**
		 * update_count updates our notifications count for this group
		 */
		public void update_count() {
			count = (int) notifications.length;
			if (count > tokeep) {
				limit_notifications();
			}
			app_label.set_markup("<b>%s (%i)</b>".printf(app_name, count));
		}

		/**
		 * Set the sort mode for this notification group.
		 */
		public void set_sort_mode(NotificationSort sort_mode) {
			switch (sort_mode) {
				case OLD_NEW:
					list.set_sort_func(sort_old_to_new);
					break;
				case NEW_OLD:
				default:
					list.set_sort_func(sort_new_to_old);
					break;
			}

			list.invalidate_sort();
		}

		private int sort_new_to_old(Gtk.ListBoxRow a, Gtk.ListBoxRow b) {
			var noti_a = a.get_child() as NotificationWidget;
			var noti_b = b.get_child() as NotificationWidget;

			// Sort notifications from new -> old, descending
			return (int)(noti_b.notification.timestamp - noti_a.notification.timestamp);
		}

		private int sort_old_to_new(Gtk.ListBoxRow a, Gtk.ListBoxRow b) {
			var noti_a = a.get_child() as NotificationWidget;
			var noti_b = b.get_child() as NotificationWidget;

			// Sort notifications from old -> new, descending
			return (int)(noti_a.notification.timestamp - noti_b.notification.timestamp);
		}
	}
}
