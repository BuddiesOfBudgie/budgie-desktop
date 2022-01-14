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

public class NotificationWidget : Gtk.Box {
	public Budgie.Notification notification { get; construct; }

	private Gtk.Box? header = null;
	private Gtk.Button? dismiss_button = null;
	private Gtk.Label? label_title = null;
	private Gtk.Label? label_body = null;
	private Gtk.Label? label_timestamp = null;

	public signal void closed_individually();

	public NotificationWidget(Budgie.Notification notification) {
		Object(orientation: Gtk.Orientation.VERTICAL, spacing: 10, notification: notification);
	}

	construct {
		expand = false;
		margin_bottom = 5;
		get_style_context().add_class("notification-clone");

		header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0); // Create our Notification header

		dismiss_button = new Gtk.Button.from_icon_name("window-close-symbolic", Gtk.IconSize.MENU);
		dismiss_button.get_style_context().add_class("flat");
		dismiss_button.get_style_context().add_class("image-button");

		label_title = new Gtk.Label(notification.summary) {
			ellipsize = Pango.EllipsizeMode.END,
			halign = Gtk.Align.START,
			justify = Gtk.Justification.LEFT,
			use_markup = true
		};

		if (notification.body != "") { // If there is body content
			label_body = new Gtk.Label(notification.body) {
				halign = Gtk.Align.START,
				justify = Gtk.Justification.LEFT,
				use_markup = true,
				width_chars = 30,
				wrap = true,
				wrap_mode = Pango.WrapMode.WORD_CHAR,
				xalign = 0
			};
		}

		var date = new DateTime.from_unix_local(notification.timestamp);

		var gnome_settings = new Settings("org.gnome.desktop.interface");
		string clock_format = gnome_settings.get_string("clock-format");
		clock_format = (clock_format == "12h") ? date.format("%l:%M %p") : date.format("%H:%M");

		label_timestamp = new Gtk.Label(clock_format) {
			halign = Gtk.Align.START,
			justify = Gtk.Justification.LEFT
		};
		label_timestamp.get_style_context().add_class("dim-label"); // Dim the label

		/**
		 * Start propagating our Notification box
		 */
		header.pack_start(label_title, false, false, 0); // Expand the label
		header.pack_end(dismiss_button, false, false, 0);

		pack_start(header); // Add our header
		pack_end(label_timestamp);

		if (label_body != null) {
			pack_end(label_body);
		}

		dismiss_button.clicked.connect(Dismiss);
	}

	/**
	 * Dismiss this notification
	 */
	public void Dismiss() {
		closed_individually(); // Trigger our signal so Raven NotificationsView knows
	}
}
