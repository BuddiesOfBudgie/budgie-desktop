/*
 * This file is part of budgie-desktop
 *
 * Copyright © 2015-2022 Budgie Desktop Developers
 * Copyright 2014 Josh Klar <j@iv597.com> (original Budgie work, prior to Budgie 10)
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

namespace Budgie {
	/** Spam apps */
	public const string ROOT_KEY_SPAM_APPS = "spam-apps";

	/** Spam categories */
	public const string ROOT_KEY_SPAM_CATEGORIES = "spam-categories";

	/**
	* Simple placeholder to use when there are no notifications
	*/
	public class NotificationPlaceholder : Gtk.Box {
		public NotificationPlaceholder() {
			Object(spacing: 6, orientation: Gtk.Orientation.VERTICAL);

			get_style_context().add_class("dim-label");
			var image = new Gtk.Image.from_icon_name("notification-alert-symbolic", Gtk.IconSize.DIALOG);
			image.pixel_size = 64;
			pack_start(image, false, false, 6);
			var label = new Gtk.Label("<big>%s</big>".printf(_("Nothing to see here")));
			label.use_markup = true;
			pack_start(label, false, false, 0);

			halign = Gtk.Align.CENTER;
			valign = Gtk.Align.CENTER;

			this.show_all();
		}
	}

	public const string NOTIFICATION_DBUS_NAME = "org.budgie_desktop.Notifications";
	public const string NOTIFICATION_DBUS_OBJECT_PATH = "/org/budgie_desktop/Notifications";
	
	[DBus (name="org.buddiesofbudgie.budgie.Dispatcher")]
	public interface Dispatcher : Object {
		public signal void NotificationAdded(
			string app_name,
			uint32 id,
			string app_icon,
			string summary,
			string body,
			string[] actions,
			HashTable<string, Variant> hints,
			int32 expire_timeout
		);

		public signal void NotificationClosed(uint32 id, NotificationCloseReason reason);
	}

	public class NotificationsView : Gtk.Box {
		private const string BUDGIE_PANEL_SCHEMA = "com.solus-project.budgie-panel";
		private const string NOTIFICATION_SCHEMA = "org.gnome.desktop.notifications.application";
		private const string NOTIFICATION_PREFIX = "/org/gnome/desktop/notifications/application";

		Dispatcher dispatcher { private get; private set; default = null; }

		construct {
			Bus.get_proxy.begin<Dispatcher>(
				BusType.SESSION,
				NOTIFICATION_DBUS_NAME,
				NOTIFICATION_DBUS_OBJECT_PATH,
				0,
				null,
				on_dbus_get
			);
		}

		private void on_dbus_get(Object? o, AsyncResult? res) {
			try {
				this.dispatcher = Bus.get_proxy.end(res);
				this.dispatcher.NotificationAdded.connect(on_notification_added);
				this.dispatcher.NotificationClosed.connect(on_notification_closed);
			} catch (Error e) {
				critical("Unable to connect to notifications dispatcher: %s", e.message);
			}
		}

		private void on_notification_added(
			string app_name,
			uint32 id,
			string app_icon,
			string summary,
			string body,
			string[] actions,
			HashTable<string, Variant> hints,
			int32 expire_timeout
		) {
		}

		private void on_notification_closed(uint32 id, NotificationCloseReason reason) {
		}
	}

	//  [DBus (name="org.freedesktop.Notifications")]
	//  public class NotificationsView : Gtk.Box {
	//  	private const string BUDGIE_PANEL_SCHEMA = "com.solus-project.budgie-panel";
	//  	private const string NOTIFICATION_SCHEMA = "org.gnome.desktop.notifications.application";
	//  	private const string NOTIFICATION_PREFIX = "/org/gnome/desktop/notifications/application";

	//  	RavenRemote? raven_proxy = null;

	//  	/* Hold onto our Raven proxy ref */
	//  	void on_raven_get(Object? o, AsyncResult? res) {
	//  		try {
	//  			raven_proxy = Bus.get_proxy.end(res);
	//  			raven_proxy.ClearAllNotifications.connect(on_clear_all);
	//  			raven_proxy.PauseNotificationsChanged.connect((paused) => {
	//  				notifications_paused = paused;
	//  			});
	//  		} catch (Error e) {
	//  			warning("Failed to gain Raven proxy: %s", e.message);
	//  		}
	//  	}

	//  	private Settings settings = new Settings(BUDGIE_PANEL_SCHEMA);

	//  	private Gtk.Button button_mute;
	//  	private Gtk.Button clear_notifications_button;
	//  	private Gtk.ListBox? listbox;
	//  	private Gtk.Image image_notifications_disabled = new Gtk.Image.from_icon_name("notification-disabled-symbolic", Gtk.IconSize.MENU);
	//  	private Gtk.Image image_notifications_enabled = new Gtk.Image.from_icon_name("notification-alert-symbolic", Gtk.IconSize.MENU);
	//  	private HashTable<string,NotificationGroup>? notifications_list = null;
	//  	private bool performing_clear_all = false;
	//  	private HeaderWidget? header = null;
	//  	private bool dnd_enabled = false;
	//  	private bool notifications_paused = false;

	//  	private uint32 notif_id = 0;

	//  	[DBus (visible=false)]
	//  	void update_child_count() {
	//  		int len = 0;

	//  		if (notifications_list.length != 0) {
	//  			notifications_list.foreach((app_name, notification_group) => { // For each notifications list
	//  				len += notification_group.count; // Add this notification group count
	//  			});
	//  		}

	//  		string? text = null;
	//  		if (len > 1) {
	//  			text = _("%u unread notifications").printf(len);
	//  		} else if (len == 1) {
	//  			text = _("1 unread notification");
	//  		} else {
	//  			text = _("No unread notifications");
	//  		}

	//  		Raven.get_instance().set_notification_count(len);
	//  		header.text = text;
	//  		clear_notifications_button.set_visible((len >= 1)); // Only show clear notifications button if we actually have notifications
	//  	}

	//  	public uint32 Notify(string app_name, uint32 replaces_id, string app_icon,
	//  						string summary, string body, string[] actions,
	//  						HashTable<string,Variant> hints, int32 expire_timeout) throws DBusError, IOError {
	//  		++notif_id;

	//  		/**
	//  		* Do notification key checking
	//  		*/
	//  		Settings app_notification_settings = null;
	//  		string settings_app_name = app_name;
	//  		bool should_show = true; // Default to showing notification

	//  		if ("desktop-entry" in hints) {
	//  			settings_app_name = hints.lookup("desktop-entry").get_string().replace(".", "-").down(); // This is necessary because Notifications application-children change . to - as well
	//  		}

	//  		if (settings_app_name != "") { // If there is a settings app name
	//  			try {
	//  				app_notification_settings = new Settings.with_path(NOTIFICATION_SCHEMA, "%s/%s/".printf(NOTIFICATION_PREFIX, settings_app_name));

	//  				if (app_notification_settings != null) { // If settings exist
	//  					should_show = app_notification_settings.get_boolean("enable"); // Will only be false if set
	//  				}
	//  			} catch (Error e) {
	//  				warning("Failed to get application settings for this app. %s", e.message);
	//  			}
	//  		}

	//  		return notif_id;
	//  	}

	//  	[DBus (visible=false)]
	//  	void clear_all() {
	//  		performing_clear_all = true;

	//  		notifications_list.foreach((app_name, notification_group) => {
	//  			notification_group.dismiss_all();
	//  		});

	//  		notifications_list.steal_all(); // Ensure we're resetting notifications_list

	//  		performing_clear_all = false;
	//  		update_child_count();
	//  		Raven.get_instance().ReadNotifications();
	//  	}

	//  	void on_clear_all() {
	//  		clear_all();
	//  		update_child_count();
	//  	}

	//  	[DBus (visible=false)]
	//  	void do_not_disturb_toggle() {
	//  		dnd_enabled = !dnd_enabled; // Invert value, so if DND was enabled, set to disabled, otherwise set to enabled
	//  		button_mute.set_image(!dnd_enabled ? image_notifications_enabled : image_notifications_disabled);
	//  		Raven.get_instance().set_dnd_state(dnd_enabled);
	//  	}


	//  	[DBus (visible=false)]
	//  	public NotificationsView() {
	//  		Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
	//  		get_style_context().add_class("raven-notifications-view");

	//  		clear_notifications_button = new Gtk.Button.from_icon_name("list-remove-all-symbolic", Gtk.IconSize.MENU);
	//  		clear_notifications_button.relief = Gtk.ReliefStyle.NONE;
	//  		clear_notifications_button.no_show_all = true;
	//  		clear_notifications_button.get_style_context().add_class("clear-all-notifications");

	//  		button_mute = new Gtk.Button();
	//  		button_mute.set_image(image_notifications_enabled);
	//  		button_mute.relief = Gtk.ReliefStyle.NONE;
	//  		button_mute.get_style_context().add_class("do-not-disturb");

	//  		var control_buttons = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
	//  		control_buttons.pack_start(button_mute, false, false, 0);
	//  		control_buttons.pack_start(clear_notifications_button, false, false, 0);

	//  		header = new HeaderWidget(_("No new notifications"), "notification-alert-symbolic", false, null, control_buttons);
	//  		header.margin_top = 6;

	//  		clear_notifications_button.clicked.connect(this.clear_all);
	//  		button_mute.clicked.connect(this.do_not_disturb_toggle);

	//  		pack_start(header, false, false, 0);

	//  		notifications_list = new HashTable<string,NotificationGroup>(str_hash, str_equal);

	//  		var scrolledwindow = new Gtk.ScrolledWindow(null, null);
	//  		scrolledwindow.get_style_context().add_class("raven-background");
	//  		scrolledwindow.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);

	//  		pack_start(scrolledwindow, true, true, 0);

	//  		listbox = new Gtk.ListBox();
	//  		listbox.set_selection_mode(Gtk.SelectionMode.NONE);
	//  		var placeholder = new NotificationPlaceholder();
	//  		listbox.set_placeholder(placeholder);
	//  		scrolledwindow.add(listbox);

	//  		show_all();
	//  		update_child_count();

	//  		Bus.get_proxy.begin<RavenRemote>(BusType.SESSION, RAVEN_DBUS_NAME, RAVEN_DBUS_OBJECT_PATH, 0, null, on_raven_get);
	//  		serve_dbus();
	//  	}


	//  	[DBus (visible=false)]
	//  	void on_bus_acquired(DBusConnection conn) {
	//  		try {
	//  			conn.register_object("/org/freedesktop/Notifications", this);
	//  		} catch (Error e) {
	//  			warning("Unable to register notification dbus: %s", e.message);
	//  		}
	//  	}

	//  	[DBus (visible=false)]
	//  	void serve_dbus() {
	//  		Bus.own_name(BusType.SESSION, "org.freedesktop.Notifications",
	//  			BusNameOwnerFlags.NONE,
	//  			on_bus_acquired, null, null);
	//  	}
	//  }
}
