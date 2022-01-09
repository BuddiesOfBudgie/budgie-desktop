/*
 * This file is part of budgie-desktop
 *
 * Copyright © 2018-2022 Budgie Desktop Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

 namespace Budgie.Notifications {
    public const string NOTIFICATION_DBUS_NAME = "org.budgie_desktop.Notifications";
	public const string NOTIFICATION_DBUS_OBJECT_PATH = "org/budgie_desktop/Notifications";

	/**
	 * Enumeration of why a notification was closed.
	 */
	public enum CloseReason {
		/** The notification expired. */
		EXPIRED = 1,
		/** The notification was dismissed by the user. */
		DISMISSED = 2,
		/** The notification was closed by a call to CloseNotification. */
		CLOSED = 3,
		/** Undefined/reserved reasons. */
		UNDEFINED = 4
	}

    /**
     * Enumeration of where notification popups will be shown.
     */
    public enum Position {
		TOP_LEFT = 1,
		TOP_RIGHT = 2,
		BOTTOM_LEFT = 3,
		BOTTOM_RIGHT = 4
	}

	/**
	 * Enumeration of notification priorities.
	 */
	public enum Urgency {
		LOW = 0,
		NORMAL = 1,
		CRITICAL = 2
	}

	/**
	 * This is our implementation of the FreeDesktop Notification spec.
	 */
	[DBus (name="org.freedesktop.Notifications")]
	public class Server : Object {
        private const string BUDGIE_PANEL_SCHEMA = "com.solus-project.budgie-panel";
		private const string NOTIFICATION_SCHEMA = "org.gnome.desktop.notifications.application";
		private const string NOTIFICATION_PREFIX = "/org/gnome/desktop/notifications/application";

        /** Spacing between notification popups */
        private const int BUFFER_ZONE = 10;
        /** Spacing between the first notification and the edge of the screen */
	    private const int INITIAL_BUFFER_ZONE = 45;

		private uint32 notif_id = 0;

		private HashTable<uint32, Notifications.Popup> popups;
		private Settings notification_settings { private get; private set; default = null; }
        private Settings panel_settings { private get; private set; default = null; }

		construct {
			Bus.own_name(
				BusType.SESSION,
				"org.freedesktop.Notifications",
				BusNameOwnerFlags.NONE,
				on_bus_acquired
			);

			this.popups = new HashTable<uint32, Notifications.Popup>(int_hash, int_equal);
			this.notification_settings = new Settings(NOTIFICATION_SCHEMA);
            this.panel_settings = new Settings(BUDGIE_PANEL_SCHEMA);
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
		public signal void NotificationClosed(uint32 id, CloseReason reason);

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
			name = "Raven"; // TODO: Should this still be Raven?
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
			var notification = new Notification(app_name, app_icon, summary, body, actions, hints, expire_timeout);

			// Check for DoNotDisturb
			var should_notify = this.notification_settings.get_boolean("show-banners") || notification.urgency == Urgency.CRITICAL;
			if (should_notify) {
				//Settings app_notification_settings = null;
				string settings_app_name = app_name;
				bool should_show = true; // Default to showing notification
	
				// If this notification has a desktop entry in the hints,
				// set the app name to get the settings for to it.
				if ("desktop-entry" in hints) {
					settings_app_name = hints.lookup("desktop-entry").get_string().replace(".", "-").down(); // This is necessary because Notifications application-children change . to - as well
				}
	
				// Get the application settings
				var app_notification_settings = new Settings.full(
					SettingsSchemaSource.get_default().lookup(NOTIFICATION_SCHEMA, true),
					null,
					"%s/%s/".printf(NOTIFICATION_PREFIX, settings_app_name)
				);
	
				should_show = app_notification_settings.get_boolean("enable") && app_notification_settings.get_boolean("show-banners");
	
				// Add a new notification popup if we should show one
				if (should_show) {
					// If there is already a popup with this ID, replace it
					if (this.popups.contains(id) && this.popups[id] != null) {
						this.popups[id].replace(notification);
					} else {
						var popup = new Popup(this, notification);
						this.configure_window(popup);
						popup.show_all();
						popup.begin_decay(expire_timeout);
	
						popup.ActionInvoked.connect((action_key) => {
							this.ActionInvoked(id, action_key);
						});
	
						popup.Closed.connect((reason) => {
							this.popups.remove(id);
							this.NotificationClosed(id, reason);
						});
	
						this.popups[id] = popup;
					}
				}
			}

			// TODO: Propogate
			return id;
		}

		/**
		 * Causes a notification to be forcefully closed and removed from the user's view.
		 * It can be used, for example, in the event that what the notification pertains to is no longer relevant, 
		 * or to cancel a notification with no expiration time.
		 *
		 * Per the spec, a blank DBusError should be thrown if the notification doesn't exist when this is called.
		 */
		public void CloseNotification(uint32 id) throws DBusError, IOError {
			if (this.popups.contains(id)) {
				this.popups[id].dismiss();
				this.popups.remove(id);
				this.NotificationClosed(id, CloseReason.CLOSED);
				return;
			}

			throw new DBusError.FAILED("");
		}

        /**
         * Configures the location of a notification popup.
         */
        private void configure_window(Popup? popup) {
			int x;
			int y;

			var screen = Gdk.Screen.get_default();

			Gdk.Monitor mon = screen.get_display().get_primary_monitor();
			Gdk.Rectangle rect = mon.get_geometry();

			/* Set the x, y position of the notification */
			calculate_position(popup, rect, out x, out y);
			popup.move(x, y);
		}

		/**
		* Calculate the (x, y) position of a notification popup based on the setting for where on
		* the screen notifications should appear.
		*/
		private void calculate_position(Popup window, Gdk.Rectangle rect, out int x, out int y) {
			var pos = (Position) this.panel_settings.get_enum("notification-position");
            var latest = this.popups[this.notif_id - 1];

			switch (pos) {
				case Position.TOP_LEFT:
					if (latest != null) { // If a notification is already being displayed
						int nx;
						int ny;
						latest.get_position(out nx, out ny);
						x = nx;
						y = ny + latest.get_child().get_allocated_height() + BUFFER_ZONE;
					} else { // This is the first nofication on the screen
						x = rect.x + BUFFER_ZONE;
						y = rect.y + INITIAL_BUFFER_ZONE;
					}
					break;
				case Position.BOTTOM_LEFT:
					if (latest != null) { // If a notification is already being displayed
						int nx;
						int ny;
						latest.get_position(out nx, out ny);
						x = nx;
						y = ny - latest.get_child().get_allocated_height() - BUFFER_ZONE;
					} else { // This is the first nofication on the screen
						x = rect.x + BUFFER_ZONE;

						int height;
						window.get_size(null, out height); // Get the estimated height of the notification
						y = (rect.y + rect.height) - height - INITIAL_BUFFER_ZONE;
					}
					break;
				case Position.BOTTOM_RIGHT:
					if (latest != null) { // If a notification is already being displayed
						int nx;
						int ny;
						latest.get_position(out nx, out ny);
						x = nx;
						y = ny - latest.get_child().get_allocated_height() - BUFFER_ZONE;
					} else { // This is the first nofication on the screen
						x = (rect.x + rect.width) - NOTIFICATION_SIZE;
						x -= BUFFER_ZONE; // Don't touch edge of the screen

						int height;
						window.get_size(null, out height); // Get the estimated height of the notification
						y = (rect.y + rect.height) - height - INITIAL_BUFFER_ZONE;
					}
					break;
				case Position.TOP_RIGHT: // Top right should also be the default case
				default:
					if (latest != null) { // If a notification is already being displayed
						int nx;
						int ny;
						latest.get_position(out nx, out ny);
						x = nx;
						y = ny + latest.get_child().get_allocated_height() + BUFFER_ZONE;
					} else { // This is the first nofication on the screen
						x = (rect.x + rect.width) - NOTIFICATION_SIZE;
						x -= BUFFER_ZONE; // Don't touch edge of the screen
						y = rect.y + INITIAL_BUFFER_ZONE;
					}
					break;
			}
		}
	}
 }