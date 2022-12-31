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
	private Gtk.Switch ethernetSwitch = null;
	private NetworkIndicatorWifiSection wifiSection;

	public NetworkIndicatorPopover(Gtk.EventBox ebox, NM.Client client) {
		Object(relative_to: ebox);

		get_style_context().add_class("budgie-network-popover");
		set_size_request(275, -1);

		this.client = client;

		build_contents();

		box.show_all();
		wifiSection.hide_placeholder();
	}

	private void build_contents() {
		box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
		box.margin = 6;

		// Ethernet
		var ethernetLabel = new Gtk.Label("<b><big>%s</big></b>".printf(_("Ethernet"))) {
			use_markup = true,
			valign = Gtk.Align.CENTER,
			margin_start = 4
		};

		var ethernetSettings = new Gtk.Button.from_icon_name("settings-symbolic", Gtk.IconSize.BUTTON);
		ethernetSettings.get_style_context().add_class(Gtk.STYLE_CLASS_FLAT);
		ethernetSettings.set_tooltip_text(_("Open Network Settings"));
		ethernetSettings.clicked.connect(() => on_settings_activate("budgie-network-panel.desktop"));

		ethernetSwitch = new Gtk.Switch() {
			halign = Gtk.Align.END,
			valign = Gtk.Align.CENTER
		};

		var ethernetHeaderBox = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
		ethernetHeaderBox.pack_start(ethernetLabel, false, false, 0);
		ethernetHeaderBox.pack_end(ethernetSwitch, false, false, 0);
		ethernetHeaderBox.pack_end(ethernetSettings, false, false, 0);
		ethernetHeaderBox.margin_bottom = 6;

		// Wifi
		wifiSection = new NetworkIndicatorWifiSection(client);
		wifiSection.settings_activated.connect(() => on_settings_activate("budgie-wifi-panel.desktop"));

		// Settings
		var settingsLabel = new Gtk.Label("<b><big>%s</big></b>".printf(_("Settings")));
		settingsLabel.set_use_markup(true);
		settingsLabel.margin_start = 4;

		box.pack_start(ethernetHeaderBox);
		box.pack_start(new Gtk.Separator(Gtk.Orientation.HORIZONTAL));
		box.pack_start(wifiSection);

		add(box);
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
}
