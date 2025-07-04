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
	public const string RAVEN_DBUS_NAME = "org.budgie_desktop.Raven";
	public const string RAVEN_DBUS_OBJECT_PATH = "/org/budgie_desktop/Raven";

	const int32 MINIMUM_EXPIRY = 6000;
	const int32 MAXIMUM_EXPIRY = 12000;

	[DBus (name="org.budgie_desktop.Raven")]
	public interface RavenProxy : Object {
		public abstract async void ToggleNotificationsView() throws Error;
	}

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
		private const int BUFFER_ZONE = 0;
		/** Spacing between the first notification and the edge of the screen */
		private const int INITIAL_BUFFER_ZONE = 45;
		/** Maximum number of popups to show on the screen at once */
		private const int MAX_POPUPS_SHOWN = 3;

		private uint32 notif_id = 0;

		private Dispatcher dispatcher { get; private set; default = null; }
		private RavenProxy raven { get; private set; default = null; }
		private HashTable<uint32, Popup> popups;
		private Settings panel_settings { private get; private set; default = null; }

		private uint32 latest_popup_id { private get; private set; default = 0; }
		private int32 latest_popup_y;
		private int paused_notifications { private get; private set; default = 0; }

		private Notify.Notification unpaused_noti = null;

		construct {
			this.dispatcher = new Dispatcher();
			this.dispatcher.notify.connect(on_property_changed);

			Bus.get_proxy.begin<RavenProxy>(BusType.SESSION, RAVEN_DBUS_NAME, RAVEN_DBUS_OBJECT_PATH, 0, null, on_raven_get);

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

		private void on_raven_get(Object? o, AsyncResult? res) {
			try {
				this.raven = Bus.get_proxy.end(res);
			} catch (Error e) {
				critical("Failed to get Raven proxy: %s", e.message);
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
				"body-markup",
				"sound"
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
		[DBus (name="Notify")]
		public uint32 notification_received(
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

			// Check if notifications are enabled for this app
			if (!app_notification_settings.get_boolean("enable")) {
				return id;
			}

			var should_notify = !this.dispatcher.get_do_not_disturb() || notification.urgency == NotificationPriority.URGENT;
			should_show = app_notification_settings.get_boolean("show-banners") && // notification popups for this app are enabled
							!this.dispatcher.notifications_paused && // notifications aren't paused, e.g. no fullscreen apps
							(this.popups.size() < MAX_POPUPS_SHOWN || notification.urgency == NotificationPriority.URGENT); // below the number of max popups, or the noti is critical

			// Because of Raven, if a popup shouldn't be shown, tell the dispatcher that
			// there's a new notification, and then immediately close it with reason
			// EXPIRED.
			if (!should_notify || !should_show) {
				if ("budgie-daemon" in app_name) return id; // We don't want to count our own noti's, or have them shown in Raven
				this.paused_notifications++;
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
				this.dispatcher.NotificationClosed(id, app_name, NotificationCloseReason.EXPIRED);
				this.NotificationClosed(id, NotificationCloseReason.EXPIRED);
				return id;
			}

			var show_body_text = app_notification_settings.get_boolean("force-expanded");

			// Add a new notification popup if we should show one
			// If there is already a popup with this ID, replace it
			if (this.popups.contains(id) && this.popups[id] != null) {
				this.popups[id].replace(notification);
			} else {
				this.popups[id] = new Popup(this, notification);

				if (!show_body_text) {
					// Body text is shown by default
					this.popups[id].toggle_body_text();
				}

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

			// Play a sound for the notification if desired
			maybe_play_sound(notification, should_notify, should_show, app_notification_settings);

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
			if (!new WaylandClient().is_initialised()) return;

			Gdk.Rectangle mon_rect = new WaylandClient().monitor_res;

			GtkLayerShell.init_for_window(popup);
			GtkLayerShell.set_layer(popup, GtkLayerShell.Layer.TOP);

			ulong handler_id = 0;
			handler_id = popup.get_child().size_allocate.connect((alloc) => {
				// Disconnect from the signal to avoid trying to recalculate
				// the position unexpectedly, which occurs when mousing over
				// or clicking the close button with some GTK themes.
				popup.get_child().disconnect(handler_id);
				handler_id = 0;

				/* determine the y position for the latest notification */
				calculate_position(mon_rect.y);
				GtkLayerShell.set_monitor(popup, new WaylandClient().gdk_monitor);
				var pos = (NotificationPosition) this.panel_settings.get_enum("notification-position");
				int edge_a, edge_b;

				switch (pos) {
					case NotificationPosition.TOP_LEFT:
						edge_a = GtkLayerShell.Edge.LEFT;
						edge_b = GtkLayerShell.Edge.TOP;
						break;
					case NotificationPosition.BOTTOM_LEFT:
						edge_a = GtkLayerShell.Edge.LEFT;
						edge_b = GtkLayerShell.Edge.BOTTOM;
						break;
					case NotificationPosition.BOTTOM_RIGHT:
						edge_a = GtkLayerShell.Edge.RIGHT;
						edge_b = GtkLayerShell.Edge.BOTTOM;
						break;
					case NotificationPosition.TOP_RIGHT: // Top right should also be the default case
					default:
						edge_a = GtkLayerShell.Edge.RIGHT;
						edge_b = GtkLayerShell.Edge.TOP;
						break;
				}

				GtkLayerShell.set_margin(popup, edge_a, BUFFER_ZONE);
				GtkLayerShell.set_margin(popup, edge_b, this.latest_popup_y);
				GtkLayerShell.set_anchor(popup, edge_a, true);
				GtkLayerShell.set_anchor(popup, edge_b, true);
			});

			popup.show_all();
		}

		/**
		* Calculate the (y) position of a notification popup based on the setting for where on
		* the screen notifications should appear.
		*/
		private void calculate_position(int monitor_height) {
			var pos = (NotificationPosition) this.panel_settings.get_enum("notification-position");
			var latest = this.popups.get(this.latest_popup_id);
			bool latest_exists = latest != null && !latest.destroying;

			if (latest_exists) {
				var existing_height = latest.get_child().get_allocated_height();
				this.latest_popup_y = this.latest_popup_y + existing_height + BUFFER_ZONE;
			}
			else if  (pos == NotificationPosition.BOTTOM_LEFT || pos == NotificationPosition.BOTTOM_RIGHT ) {
				this.latest_popup_y = INITIAL_BUFFER_ZONE;
			}
			else {
				this.latest_popup_y = monitor_height + INITIAL_BUFFER_ZONE;
			}
		}

		/**
		 * Performs a bunch of checks and plays a sound if all checks pass.
		 */
		private void maybe_play_sound(Notification notification, bool notify, bool should_show, Settings settings) {
			unowned Variant? variant = null;

			// Check if notification sounds are suppressed for this notification
			bool suppress = (variant = notification.hints.lookup("suppress-sound")) != null && variant.is_of_type(VariantType.BOOLEAN) && variant.get_boolean();
			if (suppress) return;

			if (notification.app_info == null) return; // Try to get the DesktopAppInfo for the application that generated this notification

			// Check if the application info has this key set. We check this because for now, we only
			// want to play sounds if they can be disabled via BCC. This check is how the Control Center
			// determines if an application should be shown in the Notification section.
			if (!notification.app_info.get_boolean("X-GNOME-UsesNotifications")) return;

			// Check if sound alerts are enabled for this appllication, or if we should not notify or notification is not shown
			if (!settings.get_boolean("enable-sound-alerts") || !notify || !should_show) return;

			// Default sound name
			string? sound_name = "dialog-information";

			// Give critical notifications a special sound
			if (notification.urgency == NotificationPriority.URGENT) {
				sound_name = "dialog-warning";
			}

			// Look for a sound name in the hints
			if ("sound-name" in notification.hints) {
				sound_name = notification.hints.get("sound-name").get_string();
			}

			// Try to map the notification's category to a sound name to use
			if (sound_name == "dialog-information" && notification.category != null) {
				sound_name = get_sound_for_category(notification.category);
			}

			var player = new SoundPlayer(notification, sound_name);
			new Thread<void>(null, player.play);
		}

		/**
		 * Gets the sound name to use for a notification category.
		 *
		 * See categories: https://specifications.freedesktop.org/notification-spec/latest/ar01s06.html
		 * See sound naming: https://0pointer.de/public/sound-naming-spec.html#names
		 */
		private unowned string? get_sound_for_category(string category) {
			unowned string? sound = null;

			switch (category) {
				case "device.added":
					sound = "device-added";
					break;
				case "device.removed":
					sound = "device-removed";
					break;
				case "email.arrived":
					sound = "message-new-email";
					break;
				case "im":
					sound = "message";
					break;
				case "im.received":
					sound = "message-new-instant";
					break;
				case "network.connected":
					sound = "network-connectivity-established";
					break;
				case "network.disconnected":
					sound = "network-connectivity-lost";
					break;
				case "presence.online":
					sound = "service-login";
					break;
				case "presence.offline":
					sound = "service-logout";
					break;
				// No sound for song changes
				case "x-gnome-music":
					sound = null;
					break;
				// Error sounds
				case "device.error":
				case "email.bounced":
				case "im.error":
				case "network.error":
				case "transfer.error":
					sound = "dialog-error";
					break;
				// Default sound
				default:
					sound = "dialog-information";
					break;
			}

			return sound;
		}

		private void on_property_changed(ParamSpec p) {
			if (p.name != "notifications-paused") return;

			// Only do stuff if notifications are no longer being paused
			if (dispatcher.notifications_paused) {
				this.paused_notifications = 0;
				return;
			}

			// Do nothing if there were no held notifications
			if (paused_notifications == 0) return;

			// translators: This is the title of a notification that is shown after notifications have been blocked because an application was in fullscreen mode
			var summary = _("Unread Notifications");

			string body = ngettext(
				"You received %d notification while an application was fullscreened.",
				"You received %d notifications while an application was fullscreened.",
				this.paused_notifications
			).printf(this.paused_notifications);

			var icon = "dialog-information";

			// If we have an existing noti for some reason, update it
			if (this.unpaused_noti != null) {
				this.unpaused_noti.update(summary, body, icon);
			} else {
				// No existing ref, make a new notification
				unpaused_noti = new Notify.Notification(summary, body, icon);
				// translators: Text for a button on the notification to open Raven to the notifications view
				unpaused_noti.add_action("view-notifications", _("View Notifications"), (notification, action) => {
					// Open Raven to notifications view
					this.raven.ToggleNotificationsView.begin((obj, res) => {
						try {
							this.raven.ToggleNotificationsView.end(res);
						} catch (Error e) {
							warning("Unable to open Raven notification view: %s", e.message);
						}
					});
				});

				// Remove our reference to the noti when it's closed
				unpaused_noti.closed.connect(() => {
					this.unpaused_noti = null;
				});
			}

			// Show the noti. It has to be in another thread because otherwise
			// it just times out and doesn't show.
			try {
				new Thread<void*>.try("budgie-daemon-notification", () => {
					try {
						unpaused_noti.show();
					} catch (Error e) {
						critical("error sending unpause notification: %s", e.message);
					}

					return null;
				});
			} catch (Error e) {
				critical("Error starting notification thread: %s", e.message);
			}
		}
	}

	class SoundPlayer {
		private Notification notification;
		private string? sound_name;

		public SoundPlayer(Notification notification, string? sound_name = "dialog-information") {
			this.notification = notification;
			this.sound_name = sound_name;
		}

		public void play() {
			// Play the sound
			if (sound_name != null) {
				Canberra.Proplist props;
				Canberra.Proplist.create(out props);

				props.sets(Canberra.PROP_CANBERRA_CACHE_CONTROL, "volatile");
				props.sets(Canberra.PROP_EVENT_ID, sound_name);

				CanberraGtk.context_get().play_full(0, props);
			}
		}
	}
}
