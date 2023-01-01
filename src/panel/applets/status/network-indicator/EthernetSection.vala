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

 public class NetworkIndicatorEthernetSection : Gtk.Box {
	private unowned NM.Client client;

	private Gtk.Switch ethernetSwitch = null;

	public NetworkIndicatorEthernetSection(NM.Client client) {
		Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);

		this.client = client;

		var ethernetLabel = new Gtk.Label("<b><big>%s</big></b>".printf(_("Ethernet"))) {
			use_markup = true,
			valign = Gtk.Align.CENTER,
			margin_start = 4
		};

		var ethernetSettings = new Gtk.Button.from_icon_name("settings-symbolic", Gtk.IconSize.BUTTON);
		ethernetSettings.get_style_context().add_class(Gtk.STYLE_CLASS_FLAT);
		ethernetSettings.set_tooltip_text(_("Open Network Settings"));
		ethernetSettings.clicked.connect(() => settings_activated());

		ethernetSwitch = new Gtk.Switch() {
			halign = Gtk.Align.END,
			valign = Gtk.Align.CENTER
		};

		var ethernetHeaderBox = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
		ethernetHeaderBox.pack_start(ethernetLabel, false, false, 0);
		ethernetHeaderBox.pack_end(ethernetSwitch, false, false, 0);
		ethernetHeaderBox.pack_end(ethernetSettings, false, false, 0);

		pack_start(ethernetHeaderBox);

		on_networking_state_changed();
		client.notify["networking-enabled"].connect(on_networking_state_changed);
	}

	private void on_networking_state_changed() {
		var networking_state = client.networking_get_enabled();

		if (!networking_state) {
			ethernetSwitch.set_state(false);
		}
		ethernetSwitch.set_sensitive(networking_state);
	}

	public signal void settings_activated();
}
