/*
 * This file is part of budgie-desktop
 *
 * Copyright © 2015-2022 Budgie Desktop Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

 public const string USER_ICON = "user-info";

/**
 * Creates a button using the current user's profile picture, if they
 * have one set, falling back to a generic user icon.
 */
public class UserButton : Gtk.Button {
	const string ACCOUNTSSERVICE_ACC = "org.freedesktop.Accounts";
	const string ACCOUNTSSERVICE_USER = "org.freedesktop.Accounts.User";

	private AccountsRemote? user_manager = null;
	private AccountUserRemote? current_user = null;
	private string? current_username = null;
	private PropertiesRemote? current_user_props = null;

	public UserButton() {
		Object(always_show_image: true, relief: Gtk.ReliefStyle.NONE);
	}

	construct {
		this.get_style_context().add_class("user-icon-button");

		this.current_username = Environment.get_user_name();
		this.setup_dbus.begin();
	}

	private async void setup_dbus() {
		try {
			this.user_manager = yield Bus.get_proxy(BusType.SYSTEM, ACCOUNTSSERVICE_ACC, "/org/freedesktop/Accounts");

			string uid = this.user_manager.find_user_by_name(this.current_username);

			try {
				this.current_user_props = yield Bus.get_proxy(BusType.SYSTEM, ACCOUNTSSERVICE_ACC, uid);
				this.update_userinfo();
			} catch (Error e) {
				warning("Unable to connect to Account User Service: %s", e.message);
			}

			try {
				this.current_user = yield Bus.get_proxy(BusType.SYSTEM, ACCOUNTSSERVICE_ACC, uid);
				this.current_user.changed.connect(this.update_userinfo);
			} catch (Error e) {
				warning("Unable to connect to Account User Service: %s", e.message);
			}
		} catch (Error e) {
			warning("Unable to connect to Accounts Service: %s", e.message);
		}
	}

	/**
	 * Sets the user name and profile picture from DBus.
	 */
	private void update_userinfo() {
		string user_image = this.get_user_image();
		string user_name = this.get_user_name();

		this.set_user_image(user_image);
		this.set_label(user_name);
	}

	/**
	 * Get the User's profile picture if set, falling back to a
	 * generic icon if not.
	 */
	private string get_user_image() {
		string source = USER_ICON;

		if (this.current_user_props != null) {
			try {
				string icon_file = this.current_user_props.get(ACCOUNTSSERVICE_USER, "IconFile").get_string();
				if (icon_file != "") {
					source = icon_file;
				}
			} catch (Error e) {
				warning("Failed to fetch IconFile: %s", e.message);
			}
		}

		return source;
	}

	/**
	 * Get the User's name.
	 */
	private string get_user_name() {
		string user_name = this.current_username; // Default to current_username

		if (this.current_user_props != null) {
			try {
				string real_name = this.current_user_props.get(ACCOUNTSSERVICE_USER, "RealName").get_string();
				if (real_name != "") {
					user_name = real_name;
				}
			} catch (Error e) {
				warning("Failed to fetch RealName: %s", e.message);
			}
		}

		return user_name;
	}

	/**
	 * Try to set the user image from a file. If this fails,
	 * fallback to a generic user icon.
	 */
	private void set_user_image(string source) {
		bool has_slash_prefix = source.has_prefix("/");
		bool is_user_image = (has_slash_prefix && !source.has_suffix(".face"));

		source = (has_slash_prefix && !is_user_image) ? USER_ICON : source;

		var user_image = new Gtk.Image() {
			margin_end = 6
		};

		if (is_user_image) {
			try {
				var pixbuf = new Gdk.Pixbuf.from_file_at_size(source, 24, 24);
				var surface = this.render_rounded(pixbuf, 1);
				user_image.set_from_surface(surface);
			} catch (Error e) {
				warning("File for user image does not exist: %s", e.message);
			}
		} else {
			user_image.set_from_icon_name(source, Gtk.IconSize.LARGE_TOOLBAR);
		}

		this.set_image(user_image);
	}

	/**
	 * Takes a `Gdk.Pixbuf` and turns it into a circle.
	 *
	 * This was ported from the C functions to do the same thing in
	 * Budgie Control Center.
	 */
	private Cairo.Surface render_rounded(Gdk.Pixbuf source, int scale) {
		var size = source.get_width();

		var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, size, size);
		var context = new Cairo.Context(surface);

		// Clip a circle
		context.arc(size/2, size/2, size/2, 0, 2 * GLib.Math.PI);
		context.clip();
		context.new_path();

		Gdk.cairo_set_source_pixbuf(context, source, 0, 0);
		context.paint();

		var rounded = Gdk.pixbuf_get_from_surface(surface, 0, 0, size, size);
		return Gdk.cairo_surface_create_from_pixbuf(rounded, scale, null);
	}
}
