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

public class NetworkIndicatorPopover : Budgie.Popover {
	private NM.Client client = null;

	private Gtk.Box box;

	private Gtk.Switch wifiSwitch = null;
	private Gtk.Revealer wifiListRevealer = null;
	private Gtk.ListBox wifiNetworkList = null;

	private List<NM.DeviceWifi> wifiDevices = null;

	private uint wifi_recreate_timeout = 0;

	public NetworkIndicatorPopover(Gtk.EventBox ebox, NM.Client client) {
		Object(relative_to: ebox);

		this.client = client;

		wifiDevices = new List<NM.DeviceWifi>();
		client.get_devices().foreach(on_device_added);
		client.device_added.connect(on_device_added);
		client.device_removed.connect((device) => {
			if (device.device_type == NM.DeviceType.WIFI) {
				wifiDevices.remove(device as NM.DeviceWifi);
			}
		});

		build_contents();

		wifiSwitch.set_state(client.wireless_get_enabled());
		wifiListRevealer.set_reveal_child(client.wireless_get_enabled());
		client.notify["wireless-enabled"].connect(on_wireless_state_changed);
		wifiSwitch.state_set.connect((state) => {
			client.dbus_set_property.begin(
				"/org/freedesktop/NetworkManager", "org.freedesktop.NetworkManager",
				"WirelessEnabled", state,
				-1, null
			);

			wifiListRevealer.set_reveal_child(state);

			return true;
		});

		recreate_wifi_list();
		if (client.wireless_get_enabled()) {
			wifi_recreate_timeout = Timeout.add_seconds(10, () => {
				recreate_wifi_list();
				return client.wireless_get_enabled();
			});
		}

		box.show_all();
	}

	private void recreate_wifi_list() {
		wifiNetworkList.get_children().foreach((row) => {
			row.destroy();
		});

		wifiNetworkList.add(new Gtk.Separator(Gtk.Orientation.HORIZONTAL));

		var activeIds = new HashTable<string, NM.AccessPoint>(str_hash, str_equal);
		var table = new HashTable<string, NM.AccessPoint>(str_hash, str_equal);

		wifiDevices.foreach((device) => {
			var activeAP = device.get_active_access_point();
			if (activeAP != null) {
				activeIds.insert(gen_ap_identifier(activeAP), activeAP);
			}

			device.get_access_points().foreach((ap) => {
				if (ap.ssid != null) {
					var identifier = gen_ap_identifier(ap);

					if (!table.contains(identifier)) {
						table.insert(identifier, ap);
					} else if (ap.get_strength() > table.get(identifier).get_strength()) {
						table.replace(identifier, ap);
					}
				}
			});
		});

		activeIds.foreach((id, ap) => {
			var bestAP = table.take(id);

			var row_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
			var icon = new Gtk.Image.from_icon_name(get_signal_icon_name_from_ap_strength(bestAP), Gtk.IconSize.MENU);
			var label = new Gtk.Label(NM.Utils.ssid_to_utf8(bestAP.ssid.get_data()));
			label.xalign = 0.0f;
			row_box.pack_start(icon, false, false, 0);
			row_box.pack_start(label, false, false, 0);

			var connectedLabel = new Gtk.Label("<span alpha='50%'>%s</span>".printf(_("Connected")));
			connectedLabel.use_markup = true;
			row_box.pack_end(connectedLabel, false, false, 0);

			row_box.set_border_width(4);
			wifiNetworkList.add(row_box);
		});

		table.foreach((id, ap) => {
			var row_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
			var icon = new Gtk.Image.from_icon_name(get_signal_icon_name_from_ap_strength(ap), Gtk.IconSize.MENU);
			var label = new Gtk.Label(NM.Utils.ssid_to_utf8(ap.ssid.get_data()));
			label.xalign = 0.0f;
			row_box.pack_start(icon, false, false, 0);
			row_box.pack_start(label, false, false, 0);
			row_box.set_border_width(4);
			wifiNetworkList.add(row_box);
		});

		wifiNetworkList.show_all();
	}

	private void build_contents() {
		box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
		box.border_width = 10;

		// Wifi
		wifiSwitch = new Gtk.Switch();
		wifiSwitch.set_halign(Gtk.Align.END);

		var wifiLabel = new Gtk.Label("<b><big>%s</big></b>".printf(_("Wi-Fi")));
		wifiLabel.set_use_markup(true);
		wifiLabel.margin_start = 4;
		wifiLabel.margin_end = 48;

		var wifiBox = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
		wifiBox.pack_start(wifiLabel, false, false, 0);
		wifiBox.pack_end(wifiSwitch, false, false, 0);
		box.pack_start(wifiBox, false, false, 0);

		wifiListRevealer = new Gtk.Revealer();
		box.pack_start(wifiListRevealer, false, false, 0);

		wifiNetworkList = new Gtk.ListBox();
		wifiListRevealer.add(wifiNetworkList);

		// Separator
		box.pack_start(new Gtk.Separator(Gtk.Orientation.HORIZONTAL));

		// Settings
		var settingsLabel = new Gtk.Label("<b><big>%s</big></b>".printf(_("Settings")));
		settingsLabel.set_use_markup(true);
		settingsLabel.margin_start = 4;
		settingsLabel.margin_end = 48;

		var networkSettings = new Gtk.Button.from_icon_name("network-wired-symbolic", Gtk.IconSize.BUTTON);
		networkSettings.clicked.connect(() => on_settings_activate("budgie-network-panel.desktop"));

		var wifiSettings = new Gtk.Button.from_icon_name("network-wireless-symbolic", Gtk.IconSize.BUTTON);
		wifiSettings.clicked.connect(() => on_settings_activate("budgie-wifi-panel.desktop"));

		var settingsBox = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 2);
		settingsBox.pack_start(settingsLabel, false, false, 0);
		settingsBox.pack_end(networkSettings, false, false, 0);
		settingsBox.pack_end(wifiSettings, false, false, 0);

		box.pack_start(settingsBox);

		add(box);
	}

	private void on_device_added(NM.Device device) {
		if (device.device_type == NM.DeviceType.WIFI) {
			var wifiDevice = device as NM.DeviceWifi;

			wifiDevices.append(wifiDevice);
			wifiDevice.access_point_added.connect((ap) => recreate_wifi_list());
			wifiDevice.access_point_removed.connect((ap) => recreate_wifi_list());
		}
	}

	private void on_wireless_state_changed() {
		var state = client.wireless_get_enabled();

		wifiSwitch.set_state(state);
		if (state) {
			wifiNetworkList.add(new Gtk.Separator(Gtk.Orientation.HORIZONTAL));
			wifiNetworkList.add(new Gtk.Label(_("Searching for networks...")));
			wifiNetworkList.show_all();

			wifi_recreate_timeout = Timeout.add_seconds(10, () => {
				recreate_wifi_list();
				return client.wireless_get_enabled();
			});
		} else if (wifi_recreate_timeout != 0) {
			Source.remove(wifi_recreate_timeout);
		}
	}

	private string get_signal_icon_name_from_ap_strength(NM.AccessPoint ap) {
		var strength = ap.get_strength();
		var iconStrength = "none";
		var infix = "";

		if (strength > 80) {
			iconStrength = "excellent";
		} else if (strength > 55) {
			iconStrength = "good";
		} else if (strength > 30) {
			iconStrength = "ok";
		} else if (strength > 5) {
			iconStrength = "low";
		}

		if (ap.get_wpa_flags() != NM.@80211ApSecurityFlags.NONE || ap.get_rsn_flags() != NM.@80211ApSecurityFlags.NONE) {
			infix = "-secure";
		}

		return "network-wireless" + infix + "-signal-" + iconStrength + "-symbolic";
	}

	private void on_settings_activate(string desktopFile) {
		hide();

		var app_info = new DesktopAppInfo(desktopFile);
		if (app_info == null) {
			return;
		}
		try {
			app_info.launch(null, null);
		} catch (Error e) {
			message("Unable to launch %s: %s", desktopFile, e.message);
		}
	}

	private string gen_ap_identifier(NM.AccessPoint ap) {
		return "%s-%u-%u-%u".printf(
			NM.Utils.ssid_to_utf8(ap.ssid.get_data()),
			ap.get_mode(),
			ap.get_rsn_flags(),
			ap.get_wpa_flags()
		);
	}
}
