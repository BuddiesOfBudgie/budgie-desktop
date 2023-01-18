/*
 * This file is part of budgie-desktop
 *
 * Copyright Budgie Desktop Developers
 * Copyright © 2015 Alberts Muktupāvels
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * BluetoothIndicator is largely inspired by gnome-flashback.
 */

public class BluetoothIndicator : Gtk.Bin {
	public Gtk.Image? image = null;
	public Gtk.EventBox? ebox = null;
	public Budgie.Popover? popover = null;

	private Gtk.CheckButton radio_airplane;
	private ulong radio_id;
	private Gtk.Button send_to;

	private BluetoothClient client;

	public BluetoothIndicator() {
		image = new Gtk.Image.from_icon_name("bluetooth-active-symbolic", Gtk.IconSize.MENU);

		ebox = new Gtk.EventBox();
		ebox.add(image);
		ebox.add_events(Gdk.EventMask.BUTTON_RELEASE_MASK);

		// Create our popover
		popover = new Budgie.Popover(ebox);
		var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 1);
		box.border_width = 6;
		popover.add(box);

		// Settings button
		var button = new Gtk.Button.with_label(_("Bluetooth Settings"));
		button.get_child().set_halign(Gtk.Align.START);
		button.get_style_context().add_class(Gtk.STYLE_CLASS_FLAT);
		button.clicked.connect(on_settings_activate);
		box.pack_start(button, false, false, 0);

		// Send files button
		send_to = new Gtk.Button.with_label(_("Send Files"));
		send_to.get_child().set_halign(Gtk.Align.START);
		send_to.get_style_context().add_class(Gtk.STYLE_CLASS_FLAT);
		//  send_to.clicked.connect(on_send_file);
		box.pack_start(send_to, false, false, 0);

		var sep = new Gtk.Separator(Gtk.Orientation.HORIZONTAL);
		box.pack_start(sep, false, false, 1);

		// Airplane mode
		radio_airplane = new Gtk.CheckButton.with_label(_("Bluetooth Airplane Mode"));
		radio_airplane.get_child().set_property("margin", 4);
		box.pack_start(radio_airplane, false, false, 0);

		// Ensure all content is shown
		box.show_all();

		// Create our Bluetooth client
		client = new BluetoothClient();
		client.device_added.connect((path) => {
			message("Bluetooth device added: %s", path);
		});

		client.device_removed.connect((path) => {
			message("Bluetooth device removed: %s", path);
		});

		add(ebox);
		show_all();
	}

	void on_settings_activate() {
		this.popover.hide();

		var app_info = new DesktopAppInfo("budgie-bluetooth-panel.desktop");
		if (app_info == null) {
			return;
		}
		try {
			app_info.launch(null, null);
		} catch (Error e) {
			message("Unable to launch budgie-bluetooth-panel.desktop: %s", e.message);
		}
	}
}
