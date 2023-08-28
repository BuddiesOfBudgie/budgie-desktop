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
		private HashTable<uint32, NotificationWidget> notifications;

		private Gtk.Label name_label;
		private Gtk.Button dismiss_button;
		private Gtk.ListBox noti_box;

		public string app_name { get; construct; }
		public string app_icon { get; construct; }
		public uint tokeep { get; construct set; }
		public NotificationSort noti_sort_mode { get; construct set; default = NEW_OLD; }
		public int noti_count { get; private set; default = 0; }

		/* Signals */

		public signal void dismissed_group(string app_name);
		public signal void dismissed_notification(uint32 id);

		construct {
			can_focus = false; // Disable focus to prevent scroll on click
			focus_on_click = false;

			get_style_context().add_class("raven-notifications-group");

			// Intentially omit _end because it messes with alignment of dismiss buttons
			margin = 4;

			notifications = new HashTable<uint32, NotificationWidget>(direct_hash, direct_equal);

			noti_box = new Gtk.ListBox() {
				can_focus = false,
				focus_on_click = false,
				selection_mode = Gtk.SelectionMode.NONE,
			};
			noti_box.set_sort_func(sort_notifications);

			/**
			 * Header creation
			 */
			var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0); // Create our Notification header
			header.get_style_context().add_class("raven-notifications-group-header");

			var app_image = new Gtk.Image.from_icon_name(app_icon, Gtk.IconSize.DND) {
				halign = Gtk.Align.START,
				margin_end = 5,
				pixel_size = 32, // Really ensure it's 32x32
			};

			name_label = new Gtk.Label(app_name) {
				ellipsize = Pango.EllipsizeMode.END,
				halign = Gtk.Align.START,
				justify = Gtk.Justification.LEFT,
				use_markup = true,
			};

			dismiss_button = new Gtk.Button.from_icon_name("list-remove-all-symbolic", Gtk.IconSize.MENU) {
				valign = Gtk.Align.CENTER,
				halign = Gtk.Align.END,
			};
			dismiss_button.get_style_context().add_class("flat");
			dismiss_button.get_style_context().add_class("image-button");

			dismiss_button.clicked.connect(dismiss_all);

			header.pack_start(app_image, false, false, 0);
			header.pack_start(name_label, false, false, 0);
			header.pack_end(dismiss_button, false, false, 0);

			pack_start(header);
			pack_start(noti_box);
		}

		public NotificationGroup(string c_app_icon, string c_app_name, NotificationSort sort_mode, uint keep) {
			var name = c_app_name;

			if (("budgie" in name) && ("caffeine" in c_app_icon)) { // Caffeine Notification
				name = _("Caffeine Mode");
			}

			Object(
				app_name: name,
				app_icon: c_app_icon,
				tokeep: keep,
				noti_sort_mode: sort_mode,
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 4
			);
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
			noti_box.prepend(widget);

			noti_box.invalidate_sort();
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
			notifications.foreach_remove((id, widget) => {
				widget.destroy();
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
			var widget = notifications.lookup(id); // Get our notification

			if (widget != null) { // If this notification exists
				notifications.remove(id);

				widget.destroy();

				noti_box.invalidate_sort();
				update_count(); // Update our counter
				dismissed_notification(id); // Notify anything listening

				if (noti_count == 0) { // This was the last notification
					dismissed_group(app_name); // Dismiss the group
				}
			}
		}

		/**
		 * too many notifications will choke raven and the desktop, so let's set a limit;
		 * keep the latest n-notifications of current group, delete older ones
		 */
		public void limit_notifications() {
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
				if (count >= n_remove) {
					break;
				}

				remove_notification(n);
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
		private void update_count() {
			noti_count = (int) notifications.length;

			if (noti_count > tokeep) {
				limit_notifications();
			}

			name_label.set_markup("<b>%s (%i)</b>".printf(app_name, noti_count));
		}

		private int sort_notifications(Gtk.ListBoxRow a, Gtk.ListBoxRow b) {
			var noti_a = a as NotificationWidget;
			var noti_b = b as NotificationWidget;

			switch (noti_sort_mode) {
				case NEW_OLD:
					return (int) (noti_b.notification.timestamp - noti_a.notification.timestamp);
				case OLD_NEW:
					return (int) (noti_a.notification.timestamp - noti_b.notification.timestamp);
			}

			return 0;
		}

		/**
		 * Set the sort mode for this notification group.
		 */
		public void set_sort_mode(NotificationSort sort_mode) {
			noti_sort_mode = sort_mode;
			noti_box.invalidate_sort();
		}
	}
}
