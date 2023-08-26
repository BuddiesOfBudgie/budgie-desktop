/*
 * This file is part of budgie-desktop
 *
 * Copyright Budgie Desktop Developers, elementary LLC
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

public class DeviceRow : Gtk.ListBoxRow {
	public unowned Bluetooth.Adapter adapter { get; construct; }
	public Bluetooth.Device device { get; construct; }

	private static Gtk.SizeGroup size_group;

	private Gtk.Button send_button;
	private Gtk.Label state_label;

	public signal void send_clicked(Bluetooth.Device device);

	public DeviceRow(Bluetooth.Device device, Bluetooth.Adapter adapter) {
		Object(device: device, adapter: adapter);
	}

	static construct {
		size_group = new Gtk.SizeGroup(Gtk.SizeGroupMode.HORIZONTAL);
	}

	construct {
		var image = new Gtk.Image.from_icon_name(device.icon ?? "bluetooth-active", Gtk.IconSize.DND);

		state_label = new Gtk.Label(null) {
			use_markup = true,
			xalign = 0,
		};

		string? device_name = device.alias;
		if (device_name == null) {
			if (device.icon == null) {
				device_name = get_name_from_icon();
			} else {
				device_name = device.address;
			}
		}

		var label = new Gtk.Label(device_name) {
			ellipsize = Pango.EllipsizeMode.END,
			hexpand = true,
			xalign = 0,
		};

		send_button = new Gtk.Button() {
			valign = Gtk.Align.CENTER,
			label = _("Send"),
		};

		size_group.add_widget(send_button);

		var grid = new Gtk.Grid() {
			margin = 6,
			column_spacing = 6,
			orientation = Gtk.Orientation.HORIZONTAL,
		};

		grid.attach(image, 0, 0, 1, 2);
		grid.attach(label, 1, 0, 1, 1);
		grid.attach(state_label, 1, 1, 1, 1);
		grid.attach(send_button, 4, 0, 1, 2);

		add(grid);

		show_all();

		set_sensitive(adapter.powered);

		((DBusProxy) adapter).g_properties_changed.connect((changed, invalid) => {
			var powered = changed.lookup_value("Powered", new VariantType("b"));
			if (powered != null) {
				set_sensitive(adapter.powered);
			}
		});

		((DBusProxy) device).g_properties_changed.connect((changed, invalid) => {
			var name = changed.lookup_value("Name", new VariantType("s"));
			if (name != null) {
				label.label = device.alias;
			}

			var icon = changed.lookup_value("Icon", new VariantType("s"));
			if (icon != null) {
				image.icon_name = device.icon ?? "bluetooth-active";
			}
		});

		state_label.label = Markup.printf_escaped("<span font_size='small'>%s</span>", get_name_from_icon());

		// Connect the send button
		send_button.clicked.connect(() => {
			send_clicked(device);
			get_toplevel().destroy();
		});
	}

	private string get_name_from_icon() {
		switch (device.icon) {
			case "audio-card":
				return _("Speaker");
			case "input-gaming":
				return _("Controller");
			case "input-keyboard":
				return _("Keyboard");
			case "input-mouse":
				return _("Mouse");
			case "input-tablet":
				return _("Tablet");
			case "input-touchpad":
				return _("Touchpad");
			case "phone":
				return _("Phone");
			default:
				return device.address;
		}
	}
}
