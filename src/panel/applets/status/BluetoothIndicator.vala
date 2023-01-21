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
	private Stack? stack = null;
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

		// Create our stack
		stack = new Stack() {
			border_width = 6,
			hhomogeneous = true,
			transition_duration = 250,
			transition_type = SLIDE_LEFT_RIGHT
		};

		// Create the main stack page
		var main_page = new Box(VERTICAL, 0);
		stack.add_named(main_page, "main");

		// Main header
		var main_header = new Box(HORIZONTAL, 0);
		main_header.get_style_context().add_class("bluetooth-applet-header");

		// Header label
		var switch_label = new Label(_("Bluetooth"));
		switch_label.get_style_context().add_class("dim-label");
		main_header.pack_start(switch_label);

		// Settings button
		var button = new Button.from_icon_name("preferences-system-symbolic", MENU) {
			tooltip_text = _("Bluetooth Settings")
		};
		button.get_style_context().add_class(STYLE_CLASS_FLAT);
		button.clicked.connect(on_settings_activate);
		main_header.pack_end(button, false, false, 0);

		// Bluetooth switch
		bluetooth_switch = new Switch() {
			tooltip_text = _("Turn Bluetooth on or off")
		};
		bluetooth_switch.notify["active"].connect(on_switch_activate);
		main_header.pack_end(bluetooth_switch);

		main_page.pack_start(main_header);
		main_page.pack_start(new Separator(HORIZONTAL), false, false, 1);

		// Devices
		var scrolled_window = new ScrolledWindow(null, null) {
			hscrollbar_policy = NEVER,
			min_content_height = 250,
			max_content_height = 250
		};
		devices_box = new ListBox() {
			selection_mode = NONE
		};
		devices_box.set_sort_func(sort_devices);
		devices_box.get_style_context().add_class("bluetooth-devices-listbox");

		devices_box.row_activated.connect((row) => {
			var widget = row.get_child() as BluetoothDeviceWidget;
			widget.toggle_revealer();
		});

		scrolled_window.add(devices_box);
		main_page.pack_start(scrolled_window);

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

		// Pack and show
		add(ebox);
		popover.add(stack);
		stack.show_all();
		stack.set_visible_child_name("main");
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

		BluetoothType type = 0;
		string? icon = null;
		client.get_type_and_icon_for_device(device, out type, out icon);

		var device_obj = new BluetoothDevice(device, type, icon);
		var widget = new BluetoothDeviceWidget(device_obj);

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
			var child = ((ListBoxRow) row).get_child() as BluetoothDeviceWidget;
			var proxy = child.device.proxy as Device1;
			if (proxy.address == device.address) {
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
		var a_device = a.get_child() as BluetoothDeviceWidget;
		var b_device = b.get_child() as BluetoothDeviceWidget;

		if (((Device1) a_device.device.proxy).connected && ((Device1) b_device.device.proxy).connected) return strcmp(a_device.device.alias, b_device.device.alias);
		else if (((Device1) a_device.device.proxy).connected) return -1; // A should go before B
		else if (((Device1) b_device.device.proxy).connected) return 1; // B should go before A
		else return strcmp(a_device.device.alias, b_device.device.alias);
	}
}

public class BluetoothDeviceWidget : Box {
	private Image? image = null;
	private Label? name_label = null;
	private Label? status_label = null;
	private Revealer? revealer = null;
	private Button? connection_button = null;

	public BluetoothDevice device { get; construct; }

	public signal void properties_updated();

	construct {
		get_style_context().add_class("bluetooth-widget");

		// Body
		var grid = new Grid();

		image = new Image.from_icon_name(device.icon, LARGE_TOOLBAR) {
			halign = START,
			margin_end = 6
		};

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
			hexpand = true
		};
		status_label.get_style_context().add_class("dim-label");

		// Revealer stuff
		revealer = new Revealer() {
			reveal_child = false,
			transition_duration = 250,
			transition_type = RevealerTransitionType.SLIDE_DOWN
		};
		revealer.get_style_context().add_class("bluetooth-widget-revealer");

		var revealer_body = new Box(HORIZONTAL, 0);
		connection_button = new Button.with_label("");
		connection_button.clicked.connect(on_connection_button_clicked);

		revealer_body.pack_start(connection_button);
		revealer.add(revealer_body);

		// Signals
		device.proxy.g_properties_changed.connect(update_status);

		// Packing
		grid.attach(image, 0, 0);
		grid.attach(name_label, 1, 0);
		grid.attach(status_label, 1, 1);

		pack_start(grid);
		pack_start(revealer);

		update_status();
		show_all();
	}

	public BluetoothDeviceWidget(BluetoothDevice device) {
		Object(
			device: device,
			orientation: Orientation.VERTICAL,
			spacing: 0
		);
	}

	public void toggle_revealer() {
		revealer.reveal_child = !revealer.reveal_child;
	}

	private void on_connection_button_clicked() {
		connection_button.sensitive = false;

		if (((Device1) device.proxy).connected) {
			((Device1) device.proxy).disconnect.begin((obj, res) => {
				try {
					((Device1) device.proxy).disconnect.end(res);
				} catch (Error e) {
					warning("Failed to disconnect Bluetooth device %s: %s", device.alias, e.message);
				}

				connection_button.sensitive = true;
			});
		} else {
			((Device1) device.proxy).connect.begin((obj, res) => {
				try {
					((Device1) device.proxy).connect.end(res);
				} catch (Error e) {
					warning("Failed to connect to Bluetooth device %s: %s", device.alias, e.message);
				}

				connection_button.sensitive = true;
			});
		}
	}

	private void update_status() {
		if (((Device1) device.proxy).connected) {
			status_label.set_text(_("Connected"));
			connection_button.label = _("Disconnect");
		} else {
			status_label.set_text(_("Disconnected"));
			connection_button.label = _("Connect");
		}

		// Device isn't paired
		if (!((Device1) device.proxy).paired) {
			status_label.set_text(_("Not paired"));
			connection_button.sensitive = false;
		}

		properties_updated();
	}
}
