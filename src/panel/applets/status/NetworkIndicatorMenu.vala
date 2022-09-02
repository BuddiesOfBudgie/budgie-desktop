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
	private Gtk.ListBox wifiList = null;

	public NetworkIndicatorPopover(Gtk.EventBox ebox, NM.Client client) {
		Object(relative_to: ebox);

		this.client = client;

		build_contents();

		wifiSwitch.set_state(client.wireless_get_enabled());
		wifiListRevealer.set_reveal_child(client.wireless_get_enabled());
		client.notify["wireless-enabled"].connect(() => wifiSwitch.set_state(client.wireless_get_enabled()));
		wifiSwitch.state_set.connect((state) => {
			client.dbus_set_property.begin(
				"/org/freedesktop/NetworkManager", "org.freedesktop.NetworkManager",
				"WirelessEnabled", state,
				-1, null, () => {
					wifiSwitch.set_state(state);
					wifiListRevealer.set_reveal_child(state);
					recreate_wifi_list();
				}
			);

			return true;
		});

		recreate_wifi_list();
		Timeout.add_seconds(2, () => {
			if (visible) {
				recreate_wifi_list();
			}

			return Source.CONTINUE;
		});

		box.show_all();
	}

	private void recreate_wifi_list() {
		wifiList.get_children().foreach((row) => {
			row.destroy();
		});

		var table = new HashTable<string, NM.AccessPoint>(str_hash, str_equal);

		client.get_devices().foreach((device) => {
			if (device.device_type == NM.DeviceType.WIFI) {
				var wifiDevice = device as NM.DeviceWifi;

				wifiDevice.get_access_points().foreach((ap) => {
					if (ap.ssid != null) {
						var identifier = "%s-%u-%u-%u".printf(
							NM.Utils.ssid_to_utf8(ap.ssid.get_data()),
							ap.get_mode(),
							ap.get_rsn_flags(),
							ap.get_wpa_flags()
						);

						if (!table.contains(identifier)) {
							table.insert(identifier, ap);
						} else if (ap.get_strength() > table.get(identifier).get_strength()) {
							table.replace(identifier, ap);
						}
					}
				});
			}
		});

		table.get_values().foreach((ap) => {
			var row_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
			var icon = new Gtk.Image.from_icon_name(get_signal_icon_name_from_ap_strength(ap), Gtk.IconSize.MENU);
			var label = new Gtk.Label(NM.Utils.ssid_to_utf8(ap.ssid.get_data()));
			label.xalign = 0.0f;
			row_box.pack_start(icon, false, false, 0);
			row_box.pack_start(label, false, false, 0);
			row_box.set_border_width(4);
			wifiList.add(row_box);
		});

		wifiList.show_all();
	}

	private void build_contents() {
		box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
		box.border_width = 12;

		// Wifi
		wifiSwitch = new Gtk.Switch();
		wifiSwitch.set_halign(Gtk.Align.END);

		var wifiLabel = new Gtk.Label("<b>%s</b>".printf(_("Wi-Fi")));
		wifiLabel.set_use_markup(true);

		var wifiBox = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
		wifiBox.pack_start(wifiLabel, false, false, 0);
		wifiBox.pack_end(wifiSwitch, false, false, 0);
		box.pack_start(wifiBox, false, false, 0);

		wifiListRevealer = new Gtk.Revealer();
		box.pack_start(wifiListRevealer, false, false, 0);

		wifiList = new Gtk.ListBox();
		wifiListRevealer.add(wifiList);

		// Separator
		box.pack_start(new Gtk.Separator(Gtk.Orientation.HORIZONTAL));

		// Settings button
		var button = new Gtk.Button.with_label(_("Network Settings"));
		button.get_child().set_halign(Gtk.Align.START);
		button.get_style_context().add_class(Gtk.STYLE_CLASS_FLAT);
		button.clicked.connect(on_settings_activate);
		box.pack_start(button, false, false, 0);

		add(box);
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

	private void on_settings_activate() {
		hide();

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
