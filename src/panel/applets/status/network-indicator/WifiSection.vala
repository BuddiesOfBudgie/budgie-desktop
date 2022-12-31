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

public class NetworkIndicatorWifiSection : Gtk.Box {
	private unowned NM.Client client;

	private List<NM.DeviceWifi> wifiDevices = null;
	private Gtk.Switch wifiSwitch = null;
	private Gtk.Revealer wifiListRevealer = null;
	private Gtk.ListBox wifiNetworkList = null;
	private Gtk.Box wifiPlaceholderBox = null;
	private Gtk.Spinner wifiPlaceholderSpinner = null;

	private uint wifi_recreate_timeout = 0;

	public NetworkIndicatorWifiSection(NM.Client client) {
		Object(margin_top: 6, orientation: Gtk.Orientation.VERTICAL, spacing: 0);

		this.client = client;

		var wifiLabel = new Gtk.Label("<b><big>%s</big></b>".printf(_("Wi-Fi"))) {
			use_markup = true,
			valign = Gtk.Align.CENTER,
			margin_start = 4
		};

		var wifiSettings = new Gtk.Button.from_icon_name("settings-symbolic", Gtk.IconSize.BUTTON);
		wifiSettings.get_style_context().add_class(Gtk.STYLE_CLASS_FLAT);
		wifiSettings.set_tooltip_text(_("Open Wi-Fi Settings"));
		wifiSettings.clicked.connect(() => settings_activated());

		wifiSwitch = new Gtk.Switch() {
			halign = Gtk.Align.END,
			valign = Gtk.Align.CENTER
		};

		var wifiHeaderBox = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
		wifiHeaderBox.pack_start(wifiLabel, false, false, 0);
		wifiHeaderBox.pack_end(wifiSwitch, false, false, 0);
		wifiHeaderBox.pack_end(wifiSettings, false, false, 0);

		wifiPlaceholderSpinner = new Gtk.Spinner();

		wifiPlaceholderBox = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
		wifiPlaceholderBox.add(wifiPlaceholderSpinner);
		wifiPlaceholderBox.add(new Gtk.Label(_("Searching for networks...")));
		wifiPlaceholderBox.set_halign(Gtk.Align.CENTER);
		wifiPlaceholderBox.get_style_context().add_class("wifi-network-placeholder");
		wifiPlaceholderBox.border_width = 4;

		wifiNetworkList = new Gtk.ListBox();
		wifiNetworkList.set_selection_mode(Gtk.SelectionMode.NONE);
		wifiNetworkList.get_style_context().add_class("wifi-network-list");

		var wifiRevealerBox = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
		wifiRevealerBox.get_style_context().add_class("wifi-network-revealer-box");
		wifiRevealerBox.add(wifiPlaceholderBox);
		wifiRevealerBox.add(wifiNetworkList);

		wifiListRevealer = new Gtk.Revealer();
		wifiListRevealer.add(wifiRevealerBox);

		pack_start(wifiHeaderBox, false, false, 0);
		pack_start(wifiListRevealer, false, false, 0);

		wifiDevices = new List<NM.DeviceWifi>();
		client.get_devices().foreach(on_device_added);
		client.device_added.connect(on_device_added);
		client.device_removed.connect((device) => {
			if (device.device_type == NM.DeviceType.WIFI) {
				wifiDevices.remove(device as NM.DeviceWifi);
			}
		});

		wifiSwitch.set_state(client.wireless_get_enabled());
		wifiListRevealer.set_reveal_child(client.wireless_get_enabled());
		client.notify["wireless-enabled"].connect(on_wireless_state_changed);
		wifiSwitch.state_set.connect((state) => {
			client.dbus_set_property.begin(
				"/org/freedesktop/NetworkManager", "org.freedesktop.NetworkManager",
				"WirelessEnabled", state,
				-1, null
			);

			if (state) {
				wifiPlaceholderBox.show();
			} else {
				wifiListRevealer.set_reveal_child(false);
			}

			return true;
		});

		recreate_wifi_list();
		if (client.wireless_get_enabled()) {
			wifi_recreate_timeout = Timeout.add_seconds(10, () => {
				recreate_wifi_list();
				return client.wireless_get_enabled();
			});
		}
	}

	public void hide_placeholder() {
		wifiPlaceholderBox.hide();
	}

	private void on_device_added(NM.Device device) {
		if (device.device_type == NM.DeviceType.WIFI) {
			var wifiDevice = device as NM.DeviceWifi;

			wifiDevices.append(wifiDevice);
			wifiDevice.access_point_added.connect((ap) => recreate_wifi_list());
			wifiDevice.access_point_removed.connect((ap) => recreate_wifi_list());

			wifiDevice.state_changed.connect(recreate_wifi_list);
		}
	}

	private void on_wireless_state_changed() {
		var state = client.wireless_get_enabled();

		wifiSwitch.set_state(state);
		if (state) {
			wifiListRevealer.set_reveal_child(true);
			wifi_recreate_timeout = Timeout.add_seconds(10, () => {
				recreate_wifi_list();
				return client.wireless_get_enabled();
			});
		} else if (wifi_recreate_timeout != 0) {
			Source.remove(wifi_recreate_timeout);
		}
	}

	private void recreate_wifi_list() {
		wifiNetworkList.get_children().foreach((row) => {
			row.destroy();
		});

		var table = new HashTable<string, NM.AccessPoint>(str_hash, str_equal);

		wifiDevices.foreach((device) => {
			var activeAP = device.get_active_access_point();
			if (activeAP != null && activeAP.ssid != null) {
				var row_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
				var icon = new Gtk.Image.from_icon_name(wireless_icon_name_from_state(device, activeAP), Gtk.IconSize.MENU);
				var label = new Gtk.Label(NM.Utils.ssid_to_utf8(activeAP.ssid.get_data())) {
					xalign = 0.0f,
					max_width_chars = 1,
					ellipsize = Pango.EllipsizeMode.END,
					hexpand = true,
				};
				row_box.pack_start(icon, false, false, 0);
				row_box.pack_start(label, true, true, 0);

				string? connectedText = connected_string_from_state(device);
				if (connectedText != null) {
					var connectedLabel = new Gtk.Label(null);
					connectedLabel.set_markup("<small><span alpha='50%'>%s</span></small>".printf(connectedText));
					row_box.pack_end(connectedLabel, false, false, 0);
				}

				row_box.set_border_width(4);
				wifiNetworkList.add(row_box);
			}

			device.get_access_points().foreach((ap) => {
				if (ap.ssid != null && ap != activeAP) {
					var identifier = gen_ap_identifier(ap);

					if (!table.contains(identifier)) {
						table.insert(identifier, ap);
					} else if (ap.get_strength() > table.get(identifier).get_strength()) {
						table.replace(identifier, ap);
					}
				}
			});
		});

		var remainingAPs = new List<NM.AccessPoint>();
		table.foreach((id, ap) => {
			remainingAPs.insert_sorted(ap, (a, b) =>  b.get_strength() - a.get_strength());
		});

		remainingAPs.foreach((ap) => {
			var row_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
			var icon = new Gtk.Image.from_icon_name(get_signal_icon_name_from_ap_strength(ap), Gtk.IconSize.MENU);
			var label = new Gtk.Label(NM.Utils.ssid_to_utf8(ap.ssid.get_data())) {
				xalign = 0.0f,
				max_width_chars = 1,
				ellipsize = Pango.EllipsizeMode.END,
				hexpand = true,
			};
			row_box.pack_start(icon, false, false, 0);
			row_box.pack_start(label, true, true, 0);
			row_box.set_border_width(4);
			wifiNetworkList.add(row_box);
		});

		if (wifiNetworkList.get_children().length() == 0) {
			wifiNetworkList.hide();
			wifiPlaceholderBox.show_all();
			wifiPlaceholderSpinner.start();
		} else {
			wifiPlaceholderBox.hide();
			wifiNetworkList.show_all();
		}
	}

	private string wireless_icon_name_from_state(NM.DeviceWifi device, NM.AccessPoint ap) {
		if (device.get_mode() == NM.@80211Mode.AP) {
			return "network-wireless-hotspot-symbolic";
		} else {
			return get_signal_icon_name_from_ap_strength(ap);
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

	private string? connected_string_from_state(NM.DeviceWifi device) {
		if (device.get_mode() == NM.@80211Mode.AP) {
			return _("Hotspot");
		} else {
			switch (device.get_state()) {
				case NM.DeviceState.UNAVAILABLE:
				case NM.DeviceState.UNKNOWN:
				case NM.DeviceState.UNMANAGED:
				case NM.DeviceState.DISCONNECTED:
					return null;
				case NM.DeviceState.ACTIVATED:
					return _("Connected");
				case NM.DeviceState.CONFIG:
				case NM.DeviceState.IP_CHECK:
				case NM.DeviceState.IP_CONFIG:
				case NM.DeviceState.NEED_AUTH:
				case NM.DeviceState.PREPARE:
				case NM.DeviceState.SECONDARIES:
					return _("Connecting...");
				case NM.DeviceState.DEACTIVATING:
				case NM.DeviceState.FAILED:
					return _("Disconnecting...");
			}
		}

		return null;
	}

	private string gen_ap_identifier(NM.AccessPoint ap) {
		return "%s-%u-%u-%u".printf(
			NM.Utils.ssid_to_utf8(ap.ssid.get_data()),
			ap.get_mode(),
			ap.get_rsn_flags(),
			ap.get_wpa_flags()
		);
	}

	public signal void settings_activated();


}
