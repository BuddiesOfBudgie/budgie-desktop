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

namespace Budgie {
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
	 * This is our implementation of the FreeDesktop Notification spec.
	 */
	[DBus (name="org.freedesktop.Notifications")]
	public class Notifications.Server : Object {
		private const string NOTIFICATION_SCHEMA = "org.gnome.desktop.notifications.application";
		private const string NOTIFICATION_PREFIX = "/org/gnome/desktop/notifications/application";

		private uint32 notif_id = 0;

		private HashTable<uint32, Notifications.Popup> popups;

		construct {
			Bus.own_name(
				BusType.SESSION,
				"org.freedesktop.Notifications",
				BusNameOwnerFlags.NONE,
				on_bus_acquired
			);

			this.popups = new HashTable<uint32, Notifications.Popup>(int_hash, int_equal);
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

			// TODO: Check for DoNotDisturb

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

			should_show = app_notification_settings.get_boolean("enable"); // Will only be false if set

			// Add a new notification popup if we should show one
			if (should_show) {
				// If there is already a popup with this ID, replace it
				if (this.popups.contains(id) && this.popups[id] != null) {
					this.popups[id].replace(notification);
				} else {
					this.popups[id] = new Notifications.Popup(this, notification);
					this.popups[id].show_all();

					this.popups[id].ActionInvoked.connect((action_key) => {
						this.ActionInvoked(id, action_key);
					});

					this.popups[id].Closed.connect((reason) => {
						this.popups.remove(id);
						this.NotificationClosed(id, reason);
					});
				}

				// TODO: Show the popup
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
	}

	/**
	 * This is our wrapper class for a FreeDesktop notification.
	 */
	public class Notifications.Notification : Object {
		public DesktopAppInfo? app_info { get; private set; default = null; }
		public string app_id { get; private set; }
		
		/* Notification information */
		public string app_name { get; construct; }
		public HashTable<string, Variant> hints { get; construct; }
		public string[] actions { get; construct; }
		public string app_icon { get; construct; }
		public string body { get; construct set; }
		public string summary { get; construct set; }
		public uint expire_timeout { get; construct; }

		/* Icon stuff */
		public Gdk.Pixbuf? pixbuf { get; private set; default = null; }
		public Gtk.Image? notif_icon { get; private set; default = null; }
		private string? image_path { get; private set; default = null; }

		private static Regex entity_regex;
    	private static Regex tag_regex;

		public Notification(
			string app_name,
			string app_icon,
			string summary,
			string body,
			string[] actions,
			HashTable<string, Variant> hints,
			uint expire_timeout
		) {
			Object (
				app_name: app_name,
				app_icon: app_icon,
				summary: summary,
				body: body,
				actions: actions,
				hints: hints,
				expire_timeout: expire_timeout
			);
		}

		static construct {
			try {
				entity_regex = new Regex("&(?!amp;|quot;|apos;|lt;|gt;|#39;|nbsp;)");
				tag_regex = new Regex("<(?!\\/?[biu]>)");
			} catch (Error e) {
				warning("Invalid notificiation regex: %s", e.message);
			}
		}

		construct {
			unowned Variant? variant = null;

			if ((variant = hints.lookup("desktop-entry")) != null && variant.is_of_type(VariantType.STRING)) {
				this.app_id = variant.get_string();
				app_id.replace(".desktop", "");
				this.app_info = new DesktopAppInfo("%s.desktop".printf(app_id));
			}

			// Now for the fun that is trying to get an icon to use for the notification.
			set_image.begin(app_icon, () => {});

			// GLib.Notification only requires summary, so make sure we have a title
			// when body is empty.
			if (body == "") {
				body = fix_markup(summary);
				summary = app_name;
			} else {
				body = fix_markup(body);
				summary = fix_markup(summary);
			}
		}

		/**
		* Follow the priority list for loading notification images
		* specified in the DesktopNotification spec.
		*/
		// TODO: Surely there has got to be a better way...
		private async bool set_image(string? app_icon) {
			unowned Variant? variant = null;

			// try the raw hints
			if ((variant = hints.lookup("image-data")) != null || (variant = hints.lookup("image_data")) != null) {
				var image_path = variant.get_string();

				// if this fails for some reason, we can still fallback to the
				// other elements in the priority list
				if (yield set_image_from_data(hints.lookup(image_path))) {
					return true;
				}
			}

			if (yield set_from_image_path(app_icon)) {
				return true;
			} else if (hints.contains("icon_data")) { // compatibility
				return yield set_image_from_data(hints.lookup("icon_data"));
			} else {
				return false;
			}
		}

		private async bool set_from_image_path(string? app_icon) {
			unowned Variant? variant = null;

			/* Update the icon. */
			string? img_path = null;
			if ((variant = hints.lookup("image-path")) != null || (variant = hints.lookup("image_path")) != null) {
				img_path = variant.get_string();
			}

			/* Fallback for filepath based icons */
			if (app_icon != null && "/" in app_icon) {
				img_path = app_icon;
			}

			/* Take the img_path */
			if (img_path == null) {
				return false;
			}

			/* Don't unnecessarily update the image */
			if (img_path == this.image_path) {
				return true;
			}

			this.image_path = img_path;

			try {
				var file = File.new_for_path(image_path);
				var ins = yield file.read_async(Priority.DEFAULT, null);
				this.pixbuf = yield new Gdk.Pixbuf.from_stream_at_scale_async(ins, 48, 48, true, null);
				this.notif_icon.set_from_pixbuf(pixbuf);
			} catch (Error e) {
				return false;
			}

			return true;
		}

		/**
		* Decode a raw image (iiibiiay) sent through 'hints'
		*/
		private async bool set_image_from_data(Variant img) {
			// Read the image fields
			int width = img.get_child_value(0).get_int32();
			int height = img.get_child_value(1).get_int32();
			int rowstride = img.get_child_value(2).get_int32();
			bool has_alpha = img.get_child_value(3).get_boolean();
			int bits_per_sample = img.get_child_value(4).get_int32();
			// read the raw data
			unowned uint8[] raw = (uint8[]) img.get_child_value(6).get_data();

			// rebuild and scale the image
			var pixbuf = new Gdk.Pixbuf.with_unowned_data(
				raw,
				Gdk.Colorspace.RGB,
				has_alpha,
				bits_per_sample,
				width,
				height,
				rowstride,
				null
			);

			if (height != 48) { // Height isn't 48
				pixbuf = pixbuf.scale_simple(48, 48, Gdk.InterpType.BILINEAR); // Scale down (or up if it is small)
			}

			// set the image
			if (pixbuf != null) {
				this.notif_icon.set_from_pixbuf(pixbuf);
				return true;
			} else {
				return false;
			}
		}

		/**
		 * Taken from gnome-shell. Notification markup is always a mess, and this is cleaner
		 * than our previous solution.
		 */
		private string fix_markup(string markup) {
			var text = markup;

			try {
				text = entity_regex.replace (markup, markup.length, 0, "&amp;");
				text = tag_regex.replace (text, text.length, 0, "&lt;");
			} catch (Error e) {
				warning ("Invalid regex: %s", e.message);
			}

			return text;
		}
	}

	/**
	 * This class is a notification popup with no content in it.
	 */
	public class Notifications.AbstractPopup : Gtk.Window {
		private const int NOTIFICATION_SIZE = 400;
		
		protected Gtk.Box content_box;
		
		private uint expire_id { get; private set; }
		
		public signal void Closed(CloseReason reason);

		construct {
			this.resizable = false;
			this.skip_pager_hint = true;
			this.skip_taskbar_hint = true;
			this.set_decorated(false);

			var visual = this.screen.get_rgba_visual();
			if (visual != null) {
				this.set_visual(visual);
			}

			this.set_default_size(NOTIFICATION_SIZE, -1);
			this.get_style_context().add_class("budgie-notification-window");

			this.content_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			this.content_box.get_style_context().add_class("drop-shadow");

			var close_button = new Gtk.Button.from_icon_name("window-close-symbolic", Gtk.IconSize.BUTTON) {
				halign = Gtk.Align.END,
				valign = Gtk.Align.START
			};
			close_button.clicked.connect(() => {
				this.Closed(CloseReason.DISMISSED);
				this.dismiss();
			});
		}

		/**
		 * Destroy this notification popup.
		 */
		public void dismiss() {
			destroy();
		}

		/**
		 * Close this notification when it expires.
		 */
		bool do_expire() {
			this.expire_id = 0;

			this.Closed(CloseReason.EXPIRED);
			this.dismiss();
			return false;
		}

		/**
		 * Start the decay timer for this notification. At the end of the decay, the notification is closed.
		 */
		public void begin_decay(uint timeout) {
			if (this.expire_id != 0) {
				Source.remove(this.expire_id);
			}

			this.expire_id = Timeout.add(timeout, do_expire, Priority.HIGH);
		}

		/**
		 * Stop the decay timer for this notification.
		 */
		public void stop_decay() {
			if (this.expire_id > 0) {
				Source.remove(this.expire_id);
				this.expire_id = 0;
			}
		}
	}

	public class Notifications.Popup : AbstractPopup {
		public Server owner { get; construct; }
		public Notifications.Notification notification { get; construct; }

		public bool did_interact { get; private set; default = false; }

		/**
		 * Signal emitted when an action is clicked.
		 */
		public signal void ActionInvoked(string action_key);

		public Popup(Server? owner, Notification notification) {
			Object(
				type: Gtk.WindowType.POPUP,
				type_hint: Gdk.WindowTypeHint.NOTIFICATION,
				owner: owner,
				notification: notification
			);
		}

		construct {
			bool has_actions = this.notification.actions.length > 0;
			bool has_default_action = false;

			// Check for a default action
			foreach (string action in this.notification.actions) {
				if (action == "default") {
					has_default_action = true;
					break;
				}
			}

			// Create the content widgets for the popup
			var contents = new Body(this.notification);
			contents.ActionInvoked.connect((action_key) => {
				this.ActionInvoked(action_key);
				this.dismiss();
			});
			this.content_box.add(contents);

			// Handle mouse enter/leave events to pause/start popup decay
			this.enter_notify_event.connect(() => {
				this.stop_decay();
				return Gdk.EVENT_STOP;
			});

			this.leave_notify_event.connect(() => {
				this.begin_decay(this.notification.expire_timeout);
				return Gdk.EVENT_STOP;
			});

			// Handle interaction events
			this.button_release_event.connect(() => {
				if (has_default_action) {
					this.ActionInvoked("default");
				} else if (this.notification.app_info != null && !has_actions) {
					// Try to launch the application that generated the notification
					try {
						notification.app_info.launch(null, null);
					} catch (Error e) {
						critical("Unable to launch app: %s", e.message);
					}
				}

				this.dismiss();
				return Gdk.EVENT_STOP;
			});
		}

		/**
		 * Replace the content of this notification with a new notification.
		 */
		public void replace(Notifications.Notification new_notif) {
			var new_contents = new Body(new_notif);
			new_contents.show_all();

			new_contents.ActionInvoked.connect((action_key) => {
				this.ActionInvoked(action_key);
				dismiss();
			});

			this.content_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			this.content_box.get_style_context().add_class("drop-shadow");
			this.content_box.add(new_contents);
		}
	}

	/**
	 * This class holds the widgets for all of the parts of a notification popup.
	 */
	private class Body: Gtk.Grid {
		public Notifications.Notification notification { get; construct; }

		/**
		 * Signal emitted when an action is clicked.
		 */
		public signal void ActionInvoked(string action_key);

		public Body(Notifications.Notification notification) {
			Object(notification: notification);
		}

		construct {
			this.get_style_context().add_class("budgie-notification");

			// TODO: See what more we need to do for the icon
			var app_icon = this.notification.notif_icon;
			if (app_icon != null) {
				app_icon.pixel_size = 48;
			}

			var title_label = new Gtk.Label(this.notification.summary) {
				ellipsize = Pango.EllipsizeMode.END,
				margin_top = 8,
				halign = 0
			};
			title_label.get_style_context().add_class("notification-title");

			var body_label = new Gtk.Label(this.notification.body) {
				ellipsize = Pango.EllipsizeMode.END,
				use_markup = true,
				wrap = true,
				wrap_mode = Pango.WrapMode.WORD_CHAR,
				halign = 0
			};
			body_label.get_style_context().add_class("notification-body");

			// Attach the icon and labels to our grid
			this.attach(app_icon, 0, 0, 1, 2);
			this.attach(title_label, 1, 0);
			this.attach(body_label, 1, 1);

			// Add notification actions if any are present
			if (this.notification.actions.length > 0) {
				var action_box = new Gtk.ButtonBox(Gtk.Orientation.HORIZONTAL) {
					layout_style = Gtk.ButtonBoxStyle.CENTER,
					margin_top = 6,
					margin_bottom = 3
				};
				action_box.get_style_context().add_class("linked");

				bool icons = this.notification.hints.contains("action-icons");

				for (int i = 0; i < this.notification.actions.length; i += 2) {
					// Only add an action if its not a default action
					if (this.notification.actions[i] != "default") {
						Gtk.Button? button = null;
						var action = this.notification.actions[i].dup();

						// If we have action icons, use those. Otherwise, just a labelled button
						if (icons) {
							if (!action.has_suffix("-symbolic")) {
								button = new Gtk.Button.from_icon_name("%s-symbolic".printf(action), Gtk.IconSize.MENU);
							} else {
								button = new Gtk.Button.from_icon_name(action, Gtk.IconSize.MENU);
							}
						} else {
							button = new Gtk.Button.with_label(this.notification.actions[i]);
							button.set_can_focus(false);
							button.set_can_default(false);
						}
	
						button.clicked.connect(() => {
							this.ActionInvoked(action);
						});
	
						action_box.add(button);
					} else {
						i += 2;
					}
				}

				this.attach(action_box, 0, 2, 2);
			}
		}
	}
}
