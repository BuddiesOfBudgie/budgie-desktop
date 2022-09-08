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

	public Gtk.EventBox? ebox = null;
	private Gtk.Box iconBox = null;

	public NetworkIndicatorPopover? popover = null;

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

		try {
			client = new NM.Client();
		} catch (Error e) {
			error("Failed to initialize a NetworkManager client: %s", e.message);
		}

		popover = new NetworkIndicatorPopover(ebox, client);

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
		show_all();
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
		string extraStatus = null;

		if (device.get_mode() == NM.@80211Mode.AP) {
			iconName = "network-wireless-hotspot-symbolic";
			status = _("Hotspot enabled with name <i>%s</i>").printf(NM.Utils.ssid_to_utf8(device.active_access_point.ssid.get_data()));
		} else {
			switch (device.get_state()) {
				case NM.DeviceState.UNAVAILABLE:
				case NM.DeviceState.UNKNOWN:
				case NM.DeviceState.UNMANAGED:
				case NM.DeviceState.DISCONNECTED:
					return null;
				case NM.DeviceState.ACTIVATED:
					iconName = get_connected_icon_name_from_ap_strength(device.active_access_point);
					status = _("Connected to <i>%s</i>").printf(NM.Utils.ssid_to_utf8(device.active_access_point.ssid.get_data()));
					extraStatus = _("Signal strength: %u%%").printf(device.active_access_point.get_strength());
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
		}

		string tooltip = "<b>%s</b>\n%s".printf(_("Wi-Fi"), status);
		if (extraStatus != null) {
			tooltip += "\n%s".printf(extraStatus);
		}

		return new NetworkIconInfo(iconName, tooltip);
	}

	private string get_connected_icon_name_from_ap_strength(NM.AccessPoint ap) {
		var strength = ap.get_strength();
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
}

private class NetworkIconInfo {
	public string iconName;
	public string tooltip;

	public NetworkIconInfo(string iconName, string tooltip) {
		this.iconName = iconName;
		this.tooltip = tooltip;
	}
}
