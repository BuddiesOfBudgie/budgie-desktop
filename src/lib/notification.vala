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
	 * Enumeration of why a notification was closed.
	 */
	public enum NotificationCloseReason {
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
	public enum NotificationPosition {
		TOP_LEFT = 1,
		TOP_RIGHT = 2,
		BOTTOM_LEFT = 3,
		BOTTOM_RIGHT = 4
	}

	 /**
	 * This is our wrapper class for a FreeDesktop notification.
	 */
	public class Notification : Object {
		public DesktopAppInfo? app_info { get; private set; default = null; }
		public string app_id { get; private set; }
		public GLib.NotificationPriority urgency { get; private set; default = GLib.NotificationPriority.NORMAL; }

		public uint32 id { get; construct; }

		/* Notification information */
		public string app_name { get; construct; }
		public string notification_icon { get; construct; }
		public HashTable<string, Variant> hints { get; construct; }
		public string[] actions { get; construct; }
		public string body { get; construct set; }
		public string summary { get; construct set; }
		public uint expire_timeout { get; construct set; }

		public string? category { get; construct set; }
		public int64 timestamp { get; construct set; }

		/* Icon stuff */
		public Gtk.Image? app_image { get; set; default = null; }
		public Gtk.Image? image { get; set; default = null; }

		private static Regex entity_regex;
		private static Regex tag_regex;

		public Notification(
			uint32 id,
			string app_name,
			string notification_icon,
			string summary,
			string body,
			string[] actions,
			HashTable<string, Variant> hints,
			uint expire_timeout
		) {
			var name = app_name;

			if (("budgie" in name) && ("caffeine" in notification_icon)) { // Caffeine Notification
				name = _("Caffeine Mode");
			}

			Object (
				id: id,
				app_name: name,
				notification_icon: notification_icon,
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
				warning("Invalid notification regex: %s", e.message);
			}
		}

		construct {
			unowned Variant? variant = null;
			timestamp = new DateTime.now().to_unix();

			// Set the priority
			if ((variant = hints.lookup("urgency")) != null && variant.is_of_type(VariantType.BYTE)) {
				urgency = (GLib.NotificationPriority) variant.get_byte();
			}

			// Set the category
			if ((variant = hints.lookup("category")) != null && variant.is_of_type(VariantType.STRING)) {
				category = variant.get_string();
			}

			// Try to set the application ID and app info
			if ((variant = hints.lookup("desktop-entry")) != null && variant.is_of_type(VariantType.STRING)) {
				app_id = variant.get_string();
				app_id.replace(".desktop", "");
				app_info = new DesktopAppInfo("%s.desktop".printf(app_id));
			}

			// Because following specs is a lost art, sometimes the desktop-entry
			// value does not correspond to the desktop file. So, try to best-guess
			// the desktop id instead.
			if (app_info == null) {
				app_id = app_name.replace(" ", "-").down();
				app_info = new DesktopAppInfo("%s.desktop".printf(app_id));
			}

			// Make sure we have the best app name
			if (app_info != null) {
				app_name = app_info.get_string("Name") ?? app_name;
			}

			// Try to get the application's image
			app_image = get_appinfo_image(Gtk.IconSize.DND, app_id.down());

			bool image_found = false;

			// Per the Freedesktop Notification spec, first check if there is image data
			if (
				(variant = hints.lookup("image-data")) != null ||
				(variant = hints.lookup("image_data")) != null
			) {
				var pixbuf = decode_image(variant);
				if (pixbuf != null) {
					image = new Gtk.Image.from_pixbuf(pixbuf);
					image_found = true;
				}
			}

			// If there was no image data, check if we have a path to the image to use.
			if (!image_found &&
				(
					(variant = hints.lookup("image-path")) != null ||
					(variant = hints.lookup("image_path")) != null
				)
			) {
				var path = variant.get_string();

				if (Gtk.IconTheme.get_default().has_icon(path) && path != notification_icon) {
					var icon = new ThemedIcon(path);
					image = new Gtk.Image.from_gicon(icon, Gtk.IconSize.DIALOG);
					image_found = true;
				} else if (path.has_prefix("/") || path.has_prefix("file://")) {
					try {
						var pixbuf = new Gdk.Pixbuf.from_file_at_size(path, 48, 48);
						image = new Gtk.Image.from_pixbuf(pixbuf);
						image_found = true;
					} catch (Error e) {
						critical("Unable to get pixbuf from path: %s", e.message);
					}
				}
			}

			// If no image path, try the notification_icon parameter.
			if (!image_found) {
				if (notification_icon != "" && !notification_icon.contains("/")) { // Use the app icon directly
					image = new Gtk.Image.from_icon_name(notification_icon, Gtk.IconSize.DIALOG);
					image_found = true;
				} else if (notification_icon == "" && app_info != null) { // Try to get icon from application info
					image = get_appinfo_image(Gtk.IconSize.DIALOG, "mail-unread-symbolic");
					image_found = true;
				} else if (notification_icon.contains("/")) { // Try to get icon from file
					var file = File.new_for_uri(notification_icon);
					if (file.query_exists()) {
						var icon = new FileIcon(file);
						image = new Gtk.Image.from_gicon(icon, Gtk.IconSize.DIALOG);
						image_found = true;
					}
				}
			}

			// Lastly, for compatibility, check if we have icon_data if no other image was found
			if (!image_found && (variant = hints.lookup("icon_data")) != null) {
				var pixbuf = decode_image(variant);
				if (pixbuf != null) {
					image = new Gtk.Image.from_pixbuf(pixbuf);
					image_found = true;
				}
			}

			// If we still don't have a valid image to use, show a generic icon
			if (!image_found) {
				image = new Gtk.Image.from_icon_name("mail-unread-symbolic", Gtk.IconSize.DIALOG);
			}

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

		private Gdk.Pixbuf? decode_image(Variant img) {
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

			return pixbuf.copy();
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

		private Gtk.Image? get_appinfo_image(Gtk.IconSize size, string? fallback) {
			if (app_info == null) {
				var theme = Gtk.IconTheme.get_default();

				if (!theme.has_icon(fallback)) {
					return null;
				}

				return new Gtk.Image.from_icon_name(fallback, size);
			}

			var app_icon_name = app_info.get_string("Icon"); // Use the Icon from the respective DesktopAppInfo or fallback to generic applications-internet
			var app_icon = app_info.get_icon();

			if (app_icon_name != null) {
				return new Gtk.Image.from_icon_name(app_icon_name, size);
			} else if ((app_icon_name == null) && (app_icon != null)) {
				return new Gtk.Image.from_gicon(app_icon, size);
			}

			return null;
		}
	}
}
