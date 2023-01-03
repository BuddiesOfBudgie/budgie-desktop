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

 namespace Budgie.Notifications {
	public const string NOTIFICATION_DBUS_NAME = "org.budgie_desktop.Notifications";
	public const string NOTIFICATION_DBUS_OBJECT_PATH = "/org/budgie_desktop/Notifications";

	const int32 MINIMUM_EXPIRY = 6000;
	const int32 MAXIMUM_EXPIRY = 12000;

	[DBus (name="org.buddiesofbudgie.budgie.Dispatcher")]
	public class Dispatcher : Object {
		/**
		 * Do Not Disturb property.
		 */
		private bool dnd { get; private set; default = false; }

		/**
		 * Get or set whether or not notifications should be paused, e.g. when an app enters fullscreen
		 * and Budgie is configured to not show notifications when there is a fullscreen app open.
		 */
		public bool notifications_paused { get; set; default = false; }

		construct {}

		[DBus (visible=false)]
		public void setup_dbus(bool replace) {
			var flags = BusNameOwnerFlags.ALLOW_REPLACEMENT;
			if (replace) {
				flags |= BusNameOwnerFlags.REPLACE;
			}
			Bus.own_name(BusType.SESSION, Budgie.Notifications.NOTIFICATION_DBUS_NAME, flags,
				on_dbus_acquired, ()=> {}, Budgie.DaemonNameLost);
		}

		private void on_dbus_acquired(DBusConnection conn) {
			try {
				conn.register_object(NOTIFICATION_DBUS_OBJECT_PATH, this);
			} catch (Error e) {
				critical("Unable to register notification dispatcher: %s", e.message);
			}
		}

		/**
		 * Signal emitted when Do Not Disturb is toggled.
		 */
		public signal void DoNotDisturbChanged(bool value);

		/**
		 * Signal emitted when a new notification comes in.
		 *
		 * The id might be a replacement id. It is up to the client to check for this
		 * if they are keeping track of notifications.
		 */
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

		/**
		 * Signal emitted when a notification is closed.
		 */
		public signal void NotificationClosed(uint32 id, string app_name, NotificationCloseReason reason);

		/**
		 * Returns if Do Not Disturb mode is enabled or not.
		 */
		public bool get_do_not_disturb() throws DBusError, IOError {
			return this.dnd;
		}

		/**
		 * Toggles if Do Not Disturb mode is enabled or not.
		 */
		public void toggle_do_not_disturb() throws DBusError, IOError {
			this.dnd = !this.dnd;
			this.DoNotDisturbChanged(this.dnd);
		}
	}

	/**
	 * This is our implementation of the FreeDesktop Notification spec.
	 */
	[DBus (name="org.freedesktop.Notifications")]
	public class Server : Object {
		private const string BUDGIE_PANEL_SCHEMA = "com.solus-project.budgie-panel";

		private const string APPLICATION_SCHEMA = "org.gnome.desktop.notifications.application";
		private const string APPLICATION_PREFIX = "/org/gnome/desktop/notifications/application";

		/** Spacing between notification popups */
		private const int BUFFER_ZONE = 10;
		/** Spacing between the first notification and the edge of the screen */
		private const int INITIAL_BUFFER_ZONE = 45;

		private uint32 notif_id = 0;

		private Dispatcher dispatcher { get; private set; default = null; }
		private HashTable<uint32, Popup> popups;
		private Settings panel_settings { private get; private set; default = null; }

		private uint32 latest_popup_id { private get; private set; default = 0; }

		construct {
			this.dispatcher = new Dispatcher();

			this.popups = new HashTable<uint32, Popup>(direct_hash, direct_equal);
			this.panel_settings = new Settings(BUDGIE_PANEL_SCHEMA);
		}

		[DBus (visible=false)]
		public void setup_dbus(bool replace) {
			var flags = BusNameOwnerFlags.ALLOW_REPLACEMENT;
			if (replace) {
				flags |= BusNameOwnerFlags.REPLACE;
			}
			Bus.own_name(BusType.SESSION, "org.freedesktop.Notifications", flags, on_bus_acquired, ()=> {}, Budgie.DaemonNameLost);
			this.dispatcher.setup_dbus(replace);
		}

		private void on_bus_acquired(DBusConnection conn) {
			try {
				conn.register_object("/org/freedesktop/Notifications", this);
			} catch (Error e) {
				warning("Unable to register notification DBus: %s", e.message);
			}
		}

		/**
		 * Signal emitted when one of the following occurs:
		 *   - When the user performs some global "invoking" action upon a notification.
		 * 	   For instance, clicking somewhere on the notification itself.
		 *   - The user invokes a specific action as specified in the original Notify request.
		 *     For example, clicking on an action button.
		 */
		public signal void ActionInvoked(uint32 id, string action_key);

		/**
		 * This signal can be emitted before a ActionInvoked signal.
		 * It carries an activation token that can be used to activate a toplevel.
		 */
		public signal void ActivationToken(uint32 id, string activation_token);

		/**
		 * Signal emitted when a notification is closed.
		 */
		public signal void NotificationClosed(uint32 id, uint32 reason);

		/**
		 * Returns the capabilities of this DBus Notification server.
		 */
		public string[] GetCapabilities() throws DBusError, IOError {
			return {
				"action-icons",
				"actions",
				"body",
				"body-markup"
			};
		}

		/**
		 * Returns the information for this DBus Notification server.
		 */
		public void GetServerInformation(out string name, out string vendor,
			out string version, out string spec_version) throws DBusError, IOError {
			name = "Budgie Notification Server";
			vendor = "Budgie Desktop Developers";
			version = Budgie.VERSION;
			spec_version = "1.2";
		}

		/**
		 * Handles a notification from DBus.
		 *
		 * If replaces_id is 0, the return value is a UINT32 that represent the notification.
		 * It is unique, and will not be reused unless a MAXINT number of notifications have been generated.
		 * An acceptable implementation may just use an incrementing counter for the ID. The returned ID is
		 * always greater than zero. Servers must make sure not to return zero as an ID.
		 *
		 * If replaces_id is not 0, the returned value is the same value as replaces_id.
		 */
		public uint32 Notify(
			string app_name,
			uint32 replaces_id,
			string app_icon,
			string summary,
			string body,
			string[] actions,
			HashTable<string, Variant> hints,
			int32 expire_timeout
		) throws DBusError, IOError {
			var id = (replaces_id != 0 ? replaces_id : ++notif_id);

			// The spec says that an expiry_timeout of 0 means that the
			// notification should never expire. That doesn't really make
			// sense for our implementation however, since this only handles
			// popups. Notification "storage" is done seperately by Raven.
			// All of that is to say: clamp the expiry
			var expires = expire_timeout.clamp(MINIMUM_EXPIRY, MAXIMUM_EXPIRY);

			var notification = new Notification(id, app_name, app_icon, summary, body, actions, hints, expires);

			string settings_app_name = app_name;
			bool should_show = true; // Default to showing notification

			// If this notification has a desktop entry in the hints,
			// set the app name to get the settings for to it.
			if ("desktop-entry" in hints) {
				settings_app_name = hints.lookup("desktop-entry").get_string().replace(".", "-").down(); // This is necessary because Notifications application-children change . to - as well
			}

			// Get the application settings
			var app_notification_settings = new Settings.full(
				SettingsSchemaSource.get_default().lookup(APPLICATION_SCHEMA, true),
				null,
				"%s/%s/".printf(APPLICATION_PREFIX, settings_app_name)
			);

			var should_notify = !this.dispatcher.get_do_not_disturb() || notification.urgency == NotificationUrgency.CRITICAL;
			should_show = app_notification_settings.get_boolean("enable") &&
							app_notification_settings.get_boolean("show-banners") &&
							!this.dispatcher.notifications_paused;

			// Set to expire immediately if a popup shouldn't be shown.
			if (!should_notify || !should_show) {
				notification.expire_timeout = 0;
			}

			// Add a new notification popup if we should show one
			// If there is already a popup with this ID, replace it
			if (this.popups.contains(id) && this.popups[id] != null) {
				this.popups[id].replace(notification);
			} else {
				this.popups[id] = new Popup(this, notification);
				this.configure_window(this.popups[id]);
				this.latest_popup_id = id;
				this.popups[id].begin_decay(notification.expire_timeout);

				this.popups[id].ActionInvoked.connect((action_key) => {
					this.ActionInvoked(id, action_key);
				});

				this.popups[id].Closed.connect((reason) => {
					if (this.popups.length == 1 && this.latest_popup_id == id) {
						this.latest_popup_id = 0;
					}
					this.popups.remove(id);
					this.dispatcher.NotificationClosed(id, app_name, reason);
					this.NotificationClosed(id, reason);
				});
			}

			this.dispatcher.NotificationAdded(
				app_name,
				id,
				app_icon,
				summary,
				body,
				actions,
				hints,
				expire_timeout
			);
			return id;
		}

		/**
		 * Causes a notification to be forcefully closed and removed from the user's view.
		 * It can be used, for example, in the event that what the notification pertains to is no longer relevant,
		 * or to cancel a notification with no expiration time.
		 *
		 * Per the spec, a blank DBusError should be thrown if the notification doesn't exist when this is called.
		 * However, this can break notifications from some applications, and other desktop environments don't
		 * follow that part of the spec, either. So, return to avoid breaking things.
		 */
		public void CloseNotification(uint32 id) throws DBusError, IOError {
			if (!this.popups.contains(id)) {
				return;
			}

			this.popups[id].dismiss();
			this.popups.remove(id);
			this.NotificationClosed(id, NotificationCloseReason.CLOSED);
		}

		/**
		 * Configures the location of a notification popup and makes it visible on the screen.
		 */
		private void configure_window(Popup? popup) {
			var screen = Gdk.Screen.get_default();

			Gdk.Monitor mon = screen.get_display().get_primary_monitor();
			Gdk.Rectangle mon_rect = mon.get_geometry();

			ulong handler_id = 0;
			handler_id = popup.get_child().size_allocate.connect((alloc) => {
				// Diconnect from the signal to avoid trying to recalculate
				// the position unexpectedly, which occurs when mousing over
				// or clicking the close button with some GTK themes.
				popup.get_child().disconnect(handler_id);
				handler_id = 0;

				/* Set the x, y position of the notification */
				int x = 0, y = 0;
				calculate_position(popup, mon_rect, out x, out y);
				popup.move(x, y);
			});

			popup.show_all();
		}

		/**
		* Calculate the (x, y) position of a notification popup based on the setting for where on
		* the screen notifications should appear.
		*/
		private void calculate_position(Popup window, Gdk.Rectangle rect, out int x, out int y) {
			var pos = (NotificationPosition) this.panel_settings.get_enum("notification-position");
			var latest = this.popups.get(this.latest_popup_id);
			bool latest_exists = latest != null && !latest.destroying;
			int existing_height = 0, existing_x = 0, existing_y = 0;

			if (latest_exists) {
				existing_height = latest.get_child().get_allocated_height();
				latest.get_position(out existing_x, out existing_y);
			}

			switch (pos) {
				case NotificationPosition.TOP_LEFT:
					if (latest_exists) { // If a notification is already being displayed
						x = existing_x;
						y = existing_y + existing_height + BUFFER_ZONE;
					} else { // This is the first nofication on the screen
						x = rect.x + BUFFER_ZONE;
						y = rect.y + INITIAL_BUFFER_ZONE;
					}
					break;
				case NotificationPosition.BOTTOM_LEFT:
					if (latest_exists) { // If a notification is already being displayed
						x = existing_x;
						y = existing_y - existing_height - BUFFER_ZONE;
					} else { // This is the first nofication on the screen
						x = rect.x + BUFFER_ZONE;
						y = (rect.y + rect.height) - window.get_allocated_height() - INITIAL_BUFFER_ZONE;
					}
					break;
				case NotificationPosition.BOTTOM_RIGHT:
					if (latest_exists) { // If a notification is already being displayed
						x = existing_x;
						y = existing_y - existing_height - BUFFER_ZONE;
					} else { // This is the first nofication on the screen
						x = (rect.x + rect.width) - NOTIFICATION_WIDTH;
						x -= BUFFER_ZONE; // Don't touch edge of the screen
						y = (rect.y + rect.height) - window.get_allocated_height() - INITIAL_BUFFER_ZONE;
					}
					break;
				case NotificationPosition.TOP_RIGHT: // Top right should also be the default case
				default:
					if (latest_exists) { // If a notification is already being displayed
						x = existing_x;
						y = existing_y + existing_height + BUFFER_ZONE;
					} else { // This is the first nofication on the screen
						x = (rect.x + rect.width) - NOTIFICATION_WIDTH;
						x -= BUFFER_ZONE; // Don't touch edge of the screen
						y = rect.y + INITIAL_BUFFER_ZONE;
					}
					break;
			}
		}
	}
 }
