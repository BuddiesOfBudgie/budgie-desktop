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

public class ScanDialog : Gtk.Dialog {
	public Bluetooth.ObjectManager manager { get; construct; }

	private Gtk.Revealer status_revealer;
	private Gtk.Spinner spinner;
	private Gtk.ListBox devices_box;

	public signal void send_file(Bluetooth.Device device);

	public ScanDialog(Gtk.Application application, Bluetooth.ObjectManager manager) {
		Object(application: application, manager: manager, resizable: false);
	}

	construct {
		title = _("Bluetooth File Transfer");

		var icon_image = new Gtk.Image.from_icon_name("bluetooth-active", Gtk.IconSize.DIALOG) {
			valign = Gtk.Align.CENTER,
			halign = Gtk.Align.CENTER,
		};

		var info_label = new Gtk.Label(_("Select a Bluetooth device to send files to")) {
			max_width_chars = 45,
			use_markup = true,
			wrap = true,
			xalign = 0,
		};

		status_revealer = new Gtk.Revealer() {
			reveal_child = false,
			transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN,
		};

		spinner = new Gtk.Spinner() {
			margin = 4,
		};

		var status_label = new Gtk.Label(_("Discovering…")) {
			max_width_chars = 45,
			wrap = true,
			xalign = 0,
		};

		var status_grid = new Gtk.Grid();
		status_grid.attach(spinner, 0, 0, 1, 1);
		status_grid.attach(status_label, 1, 0, 1, 1);

		status_revealer.add(status_grid);

		var placeholder = new Gtk.Box(Gtk.Orientation.VERTICAL, 18) {
			margin_top = 125,
		};
		var placeholder_title = new Gtk.Label(_("<b>No devices found</b>")) {
			use_markup = true,
		};
		placeholder_title.get_style_context().add_class(Gtk.STYLE_CLASS_DIM_LABEL);
		var placeholder_text = new Gtk.Label(_("Ensure that your devices are visable and ready for pairing"));
		placeholder_text.get_style_context().add_class(Gtk.STYLE_CLASS_DIM_LABEL);

		placeholder.pack_start(placeholder_title, false);
		placeholder.pack_start(placeholder_text, false);
		placeholder.show_all();

		devices_box = new Gtk.ListBox() {
			activate_on_single_click = true,
			selection_mode = Gtk.SelectionMode.BROWSE,
		};

		devices_box.set_header_func((Gtk.ListBoxUpdateHeaderFunc) title_rows);
		devices_box.set_sort_func((Gtk.ListBoxSortFunc) compare_rows);
		devices_box.set_filter_func((Gtk.ListBoxFilterFunc) filter_row);
		devices_box.set_placeholder(placeholder);

		var scrolled_window = new Gtk.ScrolledWindow(null, null) {
			expand = true,
		};
		scrolled_window.add(devices_box);

		var grid = new Gtk.Grid() {
			margin_top = 10,
			margin_bottom = 10,
		};

		grid.attach(icon_image, 0, 0, 1, 2);
		grid.attach(info_label, 1, 0, 1, 1);
		grid.attach(status_revealer, 1, 1, 1, 1);

		var devices_grid = new Gtk.Grid() {
			orientation = Gtk.Orientation.VERTICAL,
			valign = Gtk.Align.CENTER,
			margin_left = 10,
			margin_right = 10,
			width_request = 350,
			height_request = 350,
		};

		// devices_grid.add(frame);
		devices_grid.add(scrolled_window);

		get_content_area().add(grid);
		get_content_area().add(devices_grid);

		add_button(_("Close"), Gtk.ResponseType.CLOSE);
		response.connect((response_id) => {
			manager.stop_discovery.begin();
			destroy();
		});

		// Connect manager signals
		manager.device_added.connect(add_device);
		manager.device_removed.connect(device_removed);
		manager.status_discovering.connect(update_status);
	}

	public override void show() {
		base.show();
		var devices = manager.get_devices();

		foreach (var device in devices) {
			add_device(device);
		}

		manager.start_discovery.begin();
		update_status();
	}

	private void update_status() {
		if (manager.check_discovering()) {
			spinner.start();
			status_revealer.set_reveal_child(true);
		} else {
			spinner.stop();
			status_revealer.set_reveal_child(false);
		}
	}

	private void add_device(Bluetooth.Device device) {
		bool exists = false;

		// Check if this device has already been added
		foreach (var row in devices_box.get_children()) {
			if (((DeviceRow) row).device == device) {
				exists = true;
				break;
			}
		}

		if (exists) return;

		var row = new DeviceRow(device, manager.get_adapter_from_path(device.adapter));
		devices_box.add(row);

		if (devices_box.get_selected_row() == null) {
			devices_box.select_row(row);
			devices_box.row_activated(row);
		}

		row.send_clicked.connect((device) => {
			manager.stop_discovery.begin();
			send_file(device);
		});

		((DBusProxy) row.device).g_properties_changed.connect((changed, invalid) => {
			var paired = changed.lookup_value("Paired", new VariantType("b"));
			if (paired != null) {
				invalidate_filters();
			}

			var connected = changed.lookup_value("Connected", new VariantType("b"));
			if (connected != null) {
				invalidate_filters();
			}
		});

		invalidate_filters();
	}

	private void device_removed(Bluetooth.Device device) {
		foreach (var row in devices_box.get_children()) {
			if (((DeviceRow) row).device == device) {
				devices_box.remove(row);
				break;
			}
		}

		invalidate_filters();
	}

	private void invalidate_filters() {
		devices_box.invalidate_filter();
		devices_box.invalidate_headers();
		devices_box.invalidate_sort();
	}

	[CCode (instance_pos = -1)]
	private int compare_rows(DeviceRow row1, DeviceRow row2) {
		unowned Bluetooth.Device device1 = row1.device;
		unowned Bluetooth.Device device2 = row2.device;

		if (device1.paired && !device2.paired) return -1;

		if (!device1.paired && device2.paired) return 1;

		if (device1.connected && !device2.connected) return -1;

		if (!device1.connected && device2.connected) return 1;

		if (device1.name != null && device2.name == null) return -1;

		if (device1.name == null && device2.name != null) return 1;

		var name1 = device1.name ?? device1.address;
		var name2 = device2.name ?? device2.address;
		return name1.collate(name2);
	}

	[CCode (instance_pos = -1)]
	private void title_rows(DeviceRow row1, DeviceRow? row2) {
		if (row2 == null) {
			var label = new Gtk.Label(_("Available Devices")) {
				margin = 3,
				xalign = 0,
			};

			label.get_style_context().add_class(Gtk.STYLE_CLASS_TITLE);
			row1.set_header(label);
		} else {
			row1.set_header(null);
		}
	}

	[CCode (instance_pos = -1)]
	private bool filter_row(DeviceRow row) {
		unowned Bluetooth.Device device = row.device;

		return device.paired && device.connected;
	}
}
