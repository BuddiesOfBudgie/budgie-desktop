/*
 * This file is part of budgie-desktop
 *
 * Copyright © 2022 Budgie Desktop Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

[DBus (name="org.freedesktop.NetworkManager")]
public interface NetworkManagerIface : GLib.Object {
	public abstract void GetDevices();
}

public class NetworkIndicator : Gtk.Bin {
	public Gtk.Image? image = null;

	public Gtk.EventBox? ebox = null;
	public Budgie.Popover? popover = null;

	public NetworkIndicator() {
		image = new Gtk.Image.from_icon_name("network-wired-disconnected-symbolic", Gtk.IconSize.MENU);

		ebox = new Gtk.EventBox();
		add(ebox);

		ebox.add(image);

		ebox.add_events(Gdk.EventMask.BUTTON_RELEASE_MASK);
		ebox.button_release_event.connect(on_button_release_event);

		// Create our popover
		popover = new Budgie.Popover(ebox);
		var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 1);
		box.border_width = 6;
		popover.add(box);

		// Ethernet
		var ethernetBox = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
		ethernetBox.pack_start(new Gtk.Label(_("Ethernet")), false, false, 0);
		ethernetBox.pack_end(new Gtk.Switch(), false, false, 0);
		box.pack_start(ethernetBox, false, false, 0);

		// Wifi
		var wifiBox = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
		wifiBox.pack_start(new Gtk.Label(_("Wi-Fi")), false, false, 0);
		wifiBox.pack_end(new Gtk.Switch(), false, false, 0);
		box.pack_start(wifiBox, false, false, 0);

		// Separator
		box.add(new Gtk.Separator(Gtk.Orientation.HORIZONTAL));

		// Settings button
		var button = new Gtk.Button.with_label(_("Network Settings"));
		button.get_child().set_halign(Gtk.Align.START);
		button.get_style_context().add_class(Gtk.STYLE_CLASS_FLAT);
		button.clicked.connect(on_settings_activate);
		box.pack_start(button, false, false, 0);

		// Ensure all content is shown
		box.show_all();

		show_all();
	}

	private bool on_button_release_event(Gdk.EventButton e) {
		if (e.button != Gdk.BUTTON_MIDDLE) { // Middle click
			return Gdk.EVENT_PROPAGATE;
		}

		return Gdk.EVENT_STOP;
	}

	void on_settings_activate() {
		this.popover.hide();

		var app_info = new DesktopAppInfo("budgie-network-panel.desktop");
		if (app_info == null) {
			return;
		}
		try {
			app_info.launch(null, null);
		} catch (Error e) {
			message("Unable to launch budgie-network-panel.desktop: %s", e.message);
		}
	}
}
