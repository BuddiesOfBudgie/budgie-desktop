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
     /**
	 * This is our wrapper class for a FreeDesktop notification.
	 */
	public class Notification : Object {
		public DesktopAppInfo? app_info { get; private set; default = null; }
		public string app_id { get; private set; }
		public Urgency urgency { get; private set; default = Urgency.NORMAL; }
		
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

			// Set the priority
			if ((variant = hints.lookup("urgency")) != null && variant.is_of_type(VariantType.BYTE)) {
				this.urgency = (Urgency) variant.get_byte();
			}

			// Set the application ID and app info
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
 }