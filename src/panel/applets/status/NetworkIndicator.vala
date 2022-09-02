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

	private Gtk.Box iconBox = null;

	public Gtk.EventBox? ebox = null;
	public Budgie.Popover? popover = null;

	private Gtk.ListBox ethernetList = null;
	private Gtk.ListBox wifiList = null;

	private List<unowned NM.Device> devices_sorted;

	// compares devices, first by type, then by product ID
	private static CompareFunc<NM.Device> compareFunc = (a, b) => {
		if (a.device_type == b.device_type) {
			return strcmp(a.product, b.product);
		} else {
			return (int) (a.device_type > b.device_type) - (int) (a.device_type < b.device_type);
		}
	};

	public NetworkIndicator(int spacing) {
		ebox = new Gtk.EventBox();
		add(ebox);

		iconBox = new Gtk.Box(Gtk.Orientation.HORIZONTAL, spacing);
		ebox.add(iconBox);

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

		devices_sorted = new List<unowned NM.Device>();
		client.get_devices().foreach((device) => {
			if (device.device_type == NM.DeviceType.ETHERNET || device.device_type == NM.DeviceType.WIFI) {
				devices_sorted.insert_sorted(device, compareFunc);
			}
		});

		devices_sorted.foreach((it) => {
			it.state_changed.connect((newState, oldState, reason) => recreate_icons());
		});
		client.device_added.connect((device) => {
			if (device.device_type == NM.DeviceType.ETHERNET || device.device_type == NM.DeviceType.WIFI) {
				devices_sorted.insert_sorted(device, compareFunc);
				recreate_icons();
				device.state_changed.connect((newState, oldState, reason) => recreate_icons());
			}
		});
		client.device_removed.connect((device) => {
			if (device.device_type == NM.DeviceType.ETHERNET || device.device_type == NM.DeviceType.WIFI) {
				devices_sorted.remove(device);
			}
		});

		recreate_icons();
		Timeout.add_seconds(5, () => {
			recreate_icons();
			return Source.CONTINUE;
		});

		// Ensure all content is shown
		box.show_all();
		show_all();

		ethernetList.hide();
		wifiList.hide();
	}

	public void set_spacing(int spacing) {
		iconBox.set_spacing(spacing);
	}

	private void recreate_icons() {
		iconBox.foreach((image) => iconBox.remove(image));

		var iconInfos = new List<NetworkIconInfo>();

		devices_sorted.foreach((it) => {
			NetworkIconInfo? iconInfo = null;
			if (it.device_type == NM.DeviceType.ETHERNET) {
				iconInfo = wired_icon_info_from_state(it as NM.DeviceEthernet);
			} else if (it.device_type == NM.DeviceType.WIFI) {
				iconInfo = wireless_icon_info_from_state(it as NM.DeviceWifi);
			}

			if (iconInfo != null) {
				iconInfos.append(iconInfo);
			}
		});

		// we need at least one icon in the box
		var targetNumIcons = iconInfos.length() > 1 ? iconInfos.length() : 1;

		// avoid recreating any image widgets by adding and removing them from the icon box on demand
		var difference = targetNumIcons - iconBox.get_children().length();
		for (int i = 0; i < difference; i++) {
			iconBox.add(new Gtk.Image());
		}
		for (int i = 0; i > difference; i--) {
			iconBox.remove(iconBox.get_children().last().data);
		}

		for (int i = 0; i < iconInfos.length(); i++) {
			NetworkIconInfo iconInfo = iconInfos.nth_data(i);
			var image = iconBox.get_children().nth_data(i) as Gtk.Image;
			image.set_from_icon_name(iconInfo.iconName, Gtk.IconSize.MENU);
			image.tooltip_markup = iconInfo.tooltip;
		}

		if (iconInfos.length() == 0) {
			var image = iconBox.get_children().nth_data(0) as Gtk.Image;
			image.set_from_icon_name("network-offline-symbolic", Gtk.IconSize.MENU);
		}

		iconBox.show_all();
	}

	private NetworkIconInfo? wired_icon_info_from_state(NM.DeviceEthernet device) {
		string iconName = "network-wired-acquiring-symbolic";
		string status = null;

		switch (device.get_state()) {
			case NM.DeviceState.UNAVAILABLE:
			case NM.DeviceState.UNKNOWN:
			case NM.DeviceState.UNMANAGED:
			case NM.DeviceState.DISCONNECTED:
				return null;
			case NM.DeviceState.ACTIVATED:
				iconName = "network-wired-activated-symbolic";
				status = _("Connected");
				break;
			case NM.DeviceState.CONFIG:
				status = _("Connecting...");
				break;
			case NM.DeviceState.IP_CHECK:
				status = _("Checking for additional steps to connect...");
				break;
			case NM.DeviceState.IP_CONFIG:
				status = _("Requesting IP address...");
				break;
			case NM.DeviceState.NEED_AUTH:
				status = _("Authorization required");
				break;
			case NM.DeviceState.PREPARE:
				status = _("Preparing connection to network...");
				break;
			case NM.DeviceState.SECONDARIES:
				status = _("Connecting...");
				break;
			case NM.DeviceState.DEACTIVATING:
			case NM.DeviceState.FAILED:
				status = _("Disconnecting...");
				break;
		}

		string tooltip = "<b>%s</b>\n%s".printf(_("Ethernet"), status);

		return new NetworkIconInfo(iconName, tooltip);
	}

	private NetworkIconInfo? wireless_icon_info_from_state(NM.DeviceWifi device) {
		string iconName = "network-wireless-acquiring-symbolic";
		string status = null;

		switch (device.get_state()) {
			case NM.DeviceState.UNAVAILABLE:
			case NM.DeviceState.UNKNOWN:
			case NM.DeviceState.UNMANAGED:
			case NM.DeviceState.DISCONNECTED:
				return null;
			case NM.DeviceState.ACTIVATED:
				iconName = get_icon_name_from_ap_strength(device);
				status = _("Connected to <i>%s</i>").printf(NM.Utils.ssid_to_utf8(device.active_access_point.ssid.get_data()));
				break;
			case NM.DeviceState.CONFIG:
				status = _("Connecting...");
				break;
			case NM.DeviceState.IP_CHECK:
				status = _("Checking for further steps to connect...");
				break;
			case NM.DeviceState.IP_CONFIG:
				status = _("Requesting IP address...");
				break;
			case NM.DeviceState.NEED_AUTH:
				status = _("Authorization required");
				break;
			case NM.DeviceState.PREPARE:
				status = _("Preparing connection to network...");
				break;
			case NM.DeviceState.SECONDARIES:
				status = _("Connecting...");
				break;
			case NM.DeviceState.DEACTIVATING:
			case NM.DeviceState.FAILED:
				status = _("Disconnecting...");
				break;
		}

		string tooltip = "<b>%s</b>\n%s".printf(_("Wi-Fi"), status);

		return new NetworkIconInfo(iconName, tooltip);
	}

	private string get_icon_name_from_ap_strength(NM.DeviceWifi device) {
		var strength = device.active_access_point.get_strength();
		var iconStrength = "00";

		if (strength > 80) {
			iconStrength = "100";
		} else if (strength > 55) {
			iconStrength = "75";
		} else if (strength > 30) {
			iconStrength = "50";
		} else if (strength > 5) {
			iconStrength = "25";
		}

		return "network-wireless-connected-" + iconStrength + "-symbolic";
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

private class NetworkIconInfo {
	public string iconName;
	public string tooltip;

	public NetworkIconInfo(string iconName, string tooltip) {
		this.iconName = iconName;
		this.tooltip = tooltip;
	}
}
