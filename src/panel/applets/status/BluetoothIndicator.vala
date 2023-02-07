/*
 * This file is part of budgie-desktop
 *
 * Copyright Budgie Desktop Developers
 * Copyright © 2015 Alberts Muktupāvels
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * BluetoothIndicator is largely inspired by gnome-flashback.
 */

using Gdk;
using Gtk;

public class BluetoothIndicator : Bin {
	public Image? image = null;
	public EventBox? ebox = null;
	public Budgie.Popover? popover = null;

	private ListBox? devices_box = null;
	private Switch? bluetooth_switch = null;

	private BluetoothClient client;

	construct {
		get_style_context().add_class("bluetooth-applet-popover");

		image = new Image.from_icon_name("bluetooth-active-symbolic", IconSize.MENU);

		ebox = new EventBox();
		ebox.add(image);
		ebox.add_events(EventMask.BUTTON_RELEASE_MASK);
		ebox.button_release_event.connect(on_button_released);

		// Create our popover
		popover = new Budgie.Popover(ebox);
		popover.set_size_request(200, -1);
		popover.hide.connect(() => {
			reset_revealers();
		});
		var box = new Box(VERTICAL, 0);

		// Header
		var header = new Box(HORIZONTAL, 0);
		header.get_style_context().add_class("bluetooth-popover-header");

		// Header label
		var switch_label = new Label(_("Bluetooth")) {
			halign = START,
		};
		switch_label.get_style_context().add_class(STYLE_CLASS_DIM_LABEL);

		// Settings button
		var button = new Button.from_icon_name("preferences-system-symbolic", MENU) {
			tooltip_text = _("Bluetooth Settings")
		};
		button.get_style_context().add_class(STYLE_CLASS_FLAT);
		button.clicked.connect(on_settings_activate);

		// Bluetooth switch
		bluetooth_switch = new Switch() {
			tooltip_text = _("Turn Bluetooth on or off")
		};
		bluetooth_switch.notify["active"].connect(on_switch_activate);

		header.pack_start(switch_label);
		header.pack_end(bluetooth_switch, false, false);
		header.pack_end(button, false, false);

		// Devices
		var scrolled_window = new ScrolledWindow(null, null) {
			hscrollbar_policy = NEVER,
			min_content_height = 250,
			max_content_height = 250,
			propagate_natural_height = true
		};
		devices_box = new ListBox() {
			selection_mode = NONE
		};
		devices_box.set_filter_func(filter_paired_devices);
		devices_box.set_sort_func(sort_devices);
		devices_box.get_style_context().add_class("bluetooth-device-listbox");

		devices_box.row_activated.connect((row) => {
			var widget = row as BluetoothDeviceWidget;
			widget.toggle_revealer();
		});

		scrolled_window.add(devices_box);

		// Create our Bluetooth client
		client = new BluetoothClient();

		client.device_added.connect((device) => {
			// Remove any existing rows for this device
			remove_device(device);
			// Add the new device to correctly update its status
			add_device(device);
		});

		client.device_removed.connect((device) => {
			remove_device(device);
		});

		client.global_state_changed.connect(on_client_state_changed);

		add(ebox);
		box.pack_start(header);
		box.pack_start(new Separator(HORIZONTAL), true, true, 2);
		box.pack_start(scrolled_window);
		box.pack_start(new Separator(HORIZONTAL), true, true, 2);
		box.show_all();
		popover.add(box);
		show_all();
	}

	private bool on_button_released(EventButton e) {
		if (e.button != BUTTON_MIDDLE) return EVENT_PROPAGATE;

		// Disconnect all Bluetooth on middle click
		client.set_all_powered.begin(!client.get_powered(), (obj, res) => {
			client.check_powered();
		});

		return Gdk.EVENT_STOP;
	}

	private void on_client_state_changed(bool enabled, bool connected) {
		bluetooth_switch.active = enabled;
	}

	private void on_settings_activate() {
		this.popover.hide();

		var app_info = new DesktopAppInfo("budgie-bluetooth-panel.desktop");
		if (app_info == null) return;

		try {
			app_info.launch(null, null);
		} catch (Error e) {
			message("Unable to launch budgie-bluetooth-panel.desktop: %s", e.message);
		}
	}

	private void on_switch_activate() {
		// Turn Bluetooth on or off
		client.set_all_powered.begin(bluetooth_switch.active, (obj, res) => {
			client.check_powered();
		});
	}

	private void add_device(Device1 device) {
		debug("Bluetooth device added: %s", device.alias);

		var widget = new BluetoothDeviceWidget(device);

		widget.properties_updated.connect(() => {
			client.check_powered();
			devices_box.invalidate_sort();
		});

		devices_box.add(widget);
		devices_box.invalidate_sort();
	}

	private void remove_device(Device1 device) {
		debug("Bluetooth device removed: %s", device.alias);

		devices_box.foreach((row) => {
			var child = row as BluetoothDeviceWidget;
			if (child.device.address == device.address) {
				row.destroy();
			}
		});

		devices_box.invalidate_sort();
	}

	/**
	 * Sorts items based on their names and connection status.
	 *
	 * Items are sorted alphabetically, with connected devices at the top of the list.
	 */
	private int sort_devices(ListBoxRow a, ListBoxRow b) {
		var a_device = a as BluetoothDeviceWidget;
		var b_device = b as BluetoothDeviceWidget;

		if (a_device.device.connected && b_device.device.connected) return strcmp(a_device.device.alias, b_device.device.alias);
		else if (a_device.device.connected) return -1; // A should go before B
		else if (b_device.device.connected) return 1; // B should go before A
		else return strcmp(a_device.device.alias, b_device.device.alias);
	}

	/**
	 * Filters out any unpaired devices from our listbox.
	 */
	private bool filter_paired_devices(ListBoxRow row) {
		return ((BluetoothDeviceWidget) row).device.paired;
	}

	/**
	 * Iterate over all devices in the list box and closes any open
	 * revealers.
	 */
	private void reset_revealers() {
		devices_box.foreach((row) => {
			var widget = row as BluetoothDeviceWidget;
			if (widget.revealer_showing()) {
				widget.toggle_revealer();
			}
		});
	}
}

public class BluetoothDeviceWidget : ListBoxRow {
	private Image? image = null;
	private Label? name_label = null;
	private Label? status_label = null;
	private Revealer? revealer = null;
	private Button? connection_button = null;

	public Device1 device { get; construct; }

	public signal void properties_updated();

	construct {
		get_style_context().add_class("bluetooth-device-row");

		// Body
		var box = new Box(Orientation.VERTICAL, 0);
		var grid = new Grid() {
			column_spacing = 6,
		};

		image = new Image.from_icon_name(device.icon ?? "bluetooth", LARGE_TOOLBAR);

		name_label = new Label(device.alias) {
			valign = CENTER,
			xalign = 0.0f,
			max_width_chars = 1,
			ellipsize = END,
			hexpand = true,
			tooltip_text = device.alias
		};

		status_label = new Label(null) {
			halign = START,
		};
		status_label.get_style_context().add_class(STYLE_CLASS_DIM_LABEL);

		// Revealer stuff
		revealer = new Revealer() {
			reveal_child = false,
			transition_duration = 250,
			transition_type = RevealerTransitionType.SLIDE_DOWN
		};
		revealer.get_style_context().add_class("bluetooth-device-row-revealer");

		var revealer_body = new Box(HORIZONTAL, 0);
		connection_button = new Button.with_label("");
		connection_button.clicked.connect(on_connection_button_clicked);

		revealer_body.pack_start(connection_button);
		revealer.add(revealer_body);

		// Signals
		((DBusProxy) device).g_properties_changed.connect(update_status);

		// Packing
		grid.attach(image, 0, 0, 2, 2);
		grid.attach(name_label, 2, 0, 2, 1);
		grid.attach(status_label, 2, 1, 2, 1);

		box.pack_start(grid);
		box.pack_start(revealer);
		add(box);

		update_status();
		show_all();
	}

	public BluetoothDeviceWidget(Device1 device) {
		Object(device: device);
	}

	public bool revealer_showing() {
		return revealer.reveal_child;
	}

	public void toggle_revealer() {
		revealer.reveal_child = !revealer.reveal_child;
	}

	private void on_connection_button_clicked() {
		connection_button.sensitive = false;

		if (device.connected) { // Device is connected; disconnect it
			device.disconnect.begin((obj, res) => {
				try {
					device.disconnect.end(res);

					toggle_revealer();
				} catch (Error e) {
					warning("Failed to disconnect Bluetooth device %s: %s", device.alias, e.message);
				}

				connection_button.sensitive = true;
			});
		} else if (!device.connected) { // Device isn't connected; connect it
			device.connect.begin((obj, res) => {
				try {
					device.connect.end(res);

					toggle_revealer();
				} catch (Error e) {
					warning("Failed to connect to Bluetooth device %s: %s", device.alias, e.message);
				}

				connection_button.sensitive = true;
			});
		}
	}

	private void update_status() {
		if (device.connected) {
			status_label.set_text(_("Connected"));
			connection_button.label = _("Disconnect");
		} else {
			status_label.set_text(_("Disconnected"));
			connection_button.label = _("Connect");
		}

		properties_updated();
	}
}
