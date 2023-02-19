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
		image = new Image.from_icon_name("bluetooth-active-symbolic", IconSize.MENU);

		ebox = new EventBox();
		ebox.add(image);
		ebox.add_events(EventMask.BUTTON_RELEASE_MASK);
		ebox.button_release_event.connect(on_button_released);

		// Create our popover
		popover = new Budgie.Popover(ebox);
		popover.set_size_request(300, -1);
		popover.get_style_context().add_class("bluetooth-popover");
		var box = new Box(VERTICAL, 0);

		// Header
		var header = new Box(HORIZONTAL, 0);
		header.get_style_context().add_class("bluetooth-header");

		// Header label
		var switch_label = new Label(_("Bluetooth")) {
			halign = START,
			margin_start = 4,
		};
		switch_label.get_style_context().add_class(STYLE_CLASS_DIM_LABEL);

		// Settings button
		var button = new Button.from_icon_name("preferences-system-symbolic", MENU) {
			tooltip_text = _("Bluetooth Settings")
		};
		button.get_style_context().add_class(STYLE_CLASS_FLAT);
		button.get_style_context().remove_class(STYLE_CLASS_BUTTON);
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
			((BTDeviceRow) row).try_connect_device();
		});

		// Placeholder
		var placeholder = new Box(Orientation.VERTICAL, 18) {
			margin_top = 18,
		};
		var placeholder_label = new Label(_("No paired Bluetooth devices found.\n\nVisit Bluetooth settings to pair a device.")) {
			justify = CENTER,
		};
		placeholder_label.get_style_context().add_class(STYLE_CLASS_DIM_LABEL);
		placeholder_label.get_style_context().add_class("bluetooth-placeholder");

		var placeholder_button = new Button.with_label(_("Open Bluetooth Settings")) {
			relief = HALF,
		};
		placeholder_button.get_style_context().add_class(STYLE_CLASS_SUGGESTED_ACTION);
		placeholder_button.clicked.connect(on_settings_activate);

		placeholder.pack_start(placeholder_label, false);
		placeholder.pack_start(placeholder_button, false);
		placeholder.show_all(); // Without this, it never shows. Because... reasons?
		devices_box.set_placeholder(placeholder);
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

		// Handle when a UPower device has been added
		client.upower_device_added.connect((up_device) => {
			devices_box.foreach((row) => {
				var device_row = row as BTDeviceRow;
				if (device_row.device.address == up_device.serial) {
					device_row.up_device = up_device;
				}
			});
		});

		// Handle when a UPower device has been removed
		client.upower_device_removed.connect((path) => {
			devices_box.foreach((row) => {
				var device_row = row as BTDeviceRow;
				if (((DBusProxy) device_row.device).get_object_path() == path) {
					device_row.up_device = null;
				}
			});
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
			warning("Unable to launch budgie-bluetooth-panel.desktop: %s", e.message);
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

		var widget = new BTDeviceRow(device);

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
			var child = row as BTDeviceRow;
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
		var a_device = a as BTDeviceRow;
		var b_device = b as BTDeviceRow;

		if (a_device.device.connected && b_device.device.connected) return strcmp(a_device.device.alias, b_device.device.alias);
		else if (a_device.device.connected) return -1; // A should go before B
		else if (b_device.device.connected) return 1; // B should go before A
		else return strcmp(a_device.device.alias, b_device.device.alias);
	}

	/**
	 * Filters out any unpaired devices from our listbox.
	 */
	private bool filter_paired_devices(ListBoxRow row) {
		return ((BTDeviceRow) row).device.paired || ((BTDeviceRow) row).device.connected;
	}
}

/**
 * Widget for displaying a Bluetooth device in a ListBox.
 */
public class BTDeviceRow : ListBoxRow {
	private Image? image = null;
	private Label? name_label = null;
	private Revealer? battery_revealer = null;
	private Image? battery_icon = null;
	private Label? battery_label = null;
	private Revealer? revealer = null;
	private Spinner? spinner = null;
	private Label? status_label = null;
	private Button? connection_button = null;

	public Device1 device { get; construct; }

	private Up.Device? _up_device;
	public Up.Device? up_device {
		get { return _up_device; }
		set {
			_up_device = value;
			_up_device.notify.connect(() => {
				update_battery();
			});
			update_battery();
		}
	}

	public signal void properties_updated();

	construct {
		get_style_context().add_class("bluetooth-device-row");

		// Body
		var box = new Box(Orientation.VERTICAL, 0);
		var grid = new Grid() {
			column_spacing = 6,
		};

		var icon_name = device.icon ?? "bluetooth-active";
		if (!icon_name.has_suffix("-symbolic")) icon_name += "-symbolic";
		image = new Image.from_icon_name(icon_name, MENU);
		image.get_style_context().add_class("bluetooth-device-image");

		name_label = new Label(device.alias) {
			valign = CENTER,
			xalign = 0.0f,
			max_width_chars = 1,
			ellipsize = END,
			hexpand = true,
			tooltip_text = device.alias
		};
		name_label.get_style_context().add_class("bluetooth-device-name");

		battery_revealer = new Revealer() {
			reveal_child = false,
			transition_duration = 250,
			transition_type = RevealerTransitionType.SLIDE_DOWN,
		};

		var battery_box = new Box(Orientation.HORIZONTAL, 0);

		battery_icon = new Image();
		battery_label = new Label(null) {
			halign = START,
		};
		battery_label.get_style_context().add_class(STYLE_CLASS_DIM_LABEL);
		battery_label.get_style_context().add_class("bluetooth-battery-label");

		battery_box.pack_start(battery_label, false, false, 2);
		battery_box.pack_start(battery_icon, false, false, 2);

		battery_revealer.add(battery_box);

		// Revealer stuff
		revealer = new Revealer() {
			reveal_child = false,
			transition_duration = 250,
			transition_type = RevealerTransitionType.SLIDE_DOWN
		};
		revealer.get_style_context().add_class("bluetooth-device-revealer");

		var revealer_body = new Box(HORIZONTAL, 0);

		spinner = new Spinner();
		status_label = new Label(null) {
			halign = START,
			margin_start = 6,
		};
		status_label.get_style_context().add_class("bluetooth-device-status");
		status_label.get_style_context().add_class(STYLE_CLASS_DIM_LABEL);

		revealer_body.pack_start(spinner, false, false, 0);
		revealer_body.pack_start(status_label);
		revealer.add(revealer_body);

		// Disconnect button
		connection_button = new Button.with_label(_("Disconnect"));
		connection_button.get_style_context().add_class(STYLE_CLASS_FLAT);
		connection_button.get_style_context().add_class("bluetooth-connection-button");
		connection_button.clicked.connect(on_connection_button_clicked);

		// Signals
		((DBusProxy) device).g_properties_changed.connect(update_status);

		// Packing
		grid.attach(image, 0, 0, 2, 2);
		grid.attach(name_label, 2, 0, 2, 1);
		grid.attach(connection_button, 4, 0, 1, 1);
		grid.attach(battery_revealer, 2, 2, 1, 1);
		grid.attach(revealer, 2, 3, 1, 1);

		box.pack_start(grid);
		add(box);

		update_status();
		show_all();
		if (!device.connected) connection_button.hide();
	}

	public BTDeviceRow(Device1 device) {
		Object(device: device);
	}

	/**
	 * Try to connect to the Bluetooth device.
	 */
	public void try_connect_device() {
		if (device.connected) return;
		if (spinner.active) return;

		spinner.start();
		status_label.label = _("Connecting…");
		revealer.reveal_child = true;

		device.connect.begin((obj, res) => {
			try {
				device.connect.end(res);
				connection_button.show();
				activatable = false;
			} catch (Error e) {
				warning("Failed to connect to Bluetooth device %s: %s", device.alias, e.message);
			}

			revealer.reveal_child = false;
			spinner.stop();
		});
	}

	private void on_connection_button_clicked() {
		if (!device.connected) return;
		if (spinner.active) return;

		spinner.start();
		status_label.label = _("Disconnecting…");
		revealer.reveal_child = true;

		device.disconnect.begin((obj, res) => {
			try {
				device.disconnect.end(res);
				connection_button.hide();
				activatable = true;
			} catch (Error e) {
				warning("Failed to disconnect Bluetooth device %s: %s", device.alias, e.message);
			}

			revealer.reveal_child = false;
			spinner.stop();
		});
	}

	private void update_battery() {
		if (up_device == null) {
			battery_revealer.reveal_child = false;
			return;
		}

		string? fallback_icon_name = null;
		string? icon_name = null;

		// round to nearest 10
		int rounded = (int) Math.round(up_device.percentage / 10) * 10;

		// Calculate our icon fallback if we don't have stepped battery icons
		if (up_device.percentage <= 10) {
			fallback_icon_name = "battery-empty";
		} else if (up_device.percentage <= 25) {
			fallback_icon_name = "battery-critical";
		} else if (up_device.percentage <= 50) {
			fallback_icon_name = "battery-low";
		} else if (up_device.percentage <= 75) {
			fallback_icon_name = "battery-good";
		} else {
			fallback_icon_name = "battery-full";
		}

		icon_name = "battery-level-%d".printf(rounded);

		// Fully charged or charging
		if (up_device.state == 4) {
			icon_name = "battery-full-charged";
		} else if (up_device.state == 1) {
			icon_name += "-charging-symbolic";
			fallback_icon_name += "-charging-symbolic";
		} else {
			icon_name += "-symbolic";
		}

		var theme = IconTheme.get_default();
		var icon_info = theme.lookup_icon(icon_name, IconSize.MENU, 0);

		if (icon_info == null) {
			battery_icon.set_from_icon_name(fallback_icon_name, IconSize.MENU);
		} else {
			battery_icon.set_from_icon_name(icon_name, IconSize.MENU);
		}

		battery_label.label = "%d%%".printf((int) up_device.percentage);

		battery_revealer.reveal_child = true;
	}

	private void update_status() {
		if (device.connected) {
			status_label.set_text(_("Connected"));
		} else {
			status_label.set_text(_("Disconnected"));
		}

		// Update the name if changed
		if (device.alias != name_label.label) {
			name_label.label = device.alias;
			name_label.tooltip_text = device.alias;
		}

		properties_updated();
	}
}
