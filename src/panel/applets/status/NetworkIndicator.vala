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

public class NetworkIndicator : Gtk.Bin {
	private NM.Client client = null;

	public Gtk.Image? image = null;

	public Gtk.EventBox? ebox = null;
	public Budgie.Popover? popover = null;

	private Gtk.ListBox ethernetList = null;
	private Gtk.ListBox wifiList = null;

	public NetworkIndicator() {
		image = new Gtk.Image.from_icon_name("network-offline-symbolic", Gtk.IconSize.MENU);

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
		var ethernetSwitch = new Gtk.Switch();
		var ethernetBox = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
		ethernetBox.pack_start(new Gtk.Label(_("Ethernet")), false, false, 0);
		ethernetBox.pack_end(ethernetSwitch, false, false, 0);
		box.pack_start(ethernetBox, false, false, 0);

		ethernetList = new Gtk.ListBox();
		box.pack_start(ethernetList, false, false, 0);

		ethernetSwitch.state_set.connect((state) => {
			ethernetList.visible = state;
			return false;
		});

		// Separator
		box.pack_start(new Gtk.Separator(Gtk.Orientation.HORIZONTAL));

		// Wifi
		var wifiSwitch = new Gtk.Switch();
		var wifiBox = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
		wifiBox.pack_start(new Gtk.Label(_("Wi-Fi")), false, false, 0);
		wifiBox.pack_end(wifiSwitch, false, false, 0);
		box.pack_start(wifiBox, false, false, 0);

		wifiList = new Gtk.ListBox();
		box.pack_start(wifiList, false, false, 0);

		wifiSwitch.state_set.connect((state) => {
			wifiList.visible = state;
			return false;
		});

		// Separator
		box.pack_start(new Gtk.Separator(Gtk.Orientation.HORIZONTAL));

		// Settings button
		var button = new Gtk.Button.with_label(_("Network Settings"));
		button.get_child().set_halign(Gtk.Align.START);
		button.get_style_context().add_class(Gtk.STYLE_CLASS_FLAT);
		button.clicked.connect(on_settings_activate);
		box.pack_start(button, false, false, 0);

		try {
			client = new NM.Client();
		} catch (Error e) {
			error("Failed to initialize a NetworkManager client: %s", e.message);
		}

		client.get_devices().foreach((device) => {
			warning("Type: %s, Description: %s", device.device_type.to_string(), device.get_description());
			if (device.device_type == NM.DeviceType.ETHERNET) {
				var ethernetDevice = device as NM.DeviceEthernet;
				var row = new Gtk.ListBoxRow();
				row.add(new Gtk.Label(ethernetDevice.get_description()));
				ethernetList.add(row);
			} else if (device.device_type == NM.DeviceType.WIFI) {
				var wifiDevice = device as NM.DeviceWifi;
				wifiDevice.get_access_points().foreach((ap) => {
					if (ap.ssid != null) {
						var row = new Gtk.ListBoxRow();
						row.add(new Gtk.Label(NM.Utils.ssid_to_utf8(ap.ssid.get_data())));
						wifiList.add(row);
					}
				});
			}
		});

		client.get_connections().foreach((connection) => {
			warning("Interface name: %s", connection.get_interface_name());
		});

		set_icon_from_state();

		// Ensure all content is shown
		box.show_all();
		show_all();

		ethernetList.hide();
		wifiList.hide();
	}

	void set_icon_from_state() {
		switch (client.get_state()) {
			case NM.State.ASLEEP:
				image.set_from_icon_name("network-offline-symbolic", Gtk.IconSize.MENU);
				break;
			case NM.State.CONNECTED_GLOBAL:
				image.set_from_icon_name("network-wired-activated-symbolic", Gtk.IconSize.MENU);
				break;
			case NM.State.CONNECTED_LOCAL:
			case NM.State.CONNECTED_SITE:
				image.set_from_icon_name("network-wired-no-route-symbolic", Gtk.IconSize.MENU);
				break;
			case NM.State.CONNECTING:
			case NM.State.DISCONNECTING:
				image.set_from_icon_name("network-wired-acquiring-symbolic", Gtk.IconSize.MENU);
				break;
		}
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
