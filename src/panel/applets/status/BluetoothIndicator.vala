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
	private Button? pairing_button = null;

	private BluetoothClient client;

	public bool pairing { get; private set; default = false; }

	construct {
		get_style_context().add_class("bluetooth-applet-popover");

		image = new Image.from_icon_name("bluetooth-active-symbolic", IconSize.MENU);

		ebox = new EventBox();
		ebox.add(image);
		ebox.add_events(EventMask.BUTTON_RELEASE_MASK);
		ebox.button_release_event.connect(on_button_released);

		// Create our popover
		popover = new Budgie.Popover(ebox);
		var box = new Box(VERTICAL, 0);

		// Header
		var header = new Box(HORIZONTAL, 0);
		header.get_style_context().add_class("bluetooth-applet-header");

		// Header label
		var switch_label = new Label(_("Bluetooth"));
		switch_label.get_style_context().add_class("dim-label");

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
		header.pack_end(bluetooth_switch);
		header.pack_end(button, false, false, 0);

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
		devices_box.set_filter_func(filter_paired);
		devices_box.get_style_context().add_class("bluetooth-devices-listbox");

		devices_box.row_activated.connect((row) => {
			var widget = row.get_child() as BluetoothDeviceWidget;
			widget.toggle_revealer();
		});

		scrolled_window.add(devices_box);

		// Footer
		var footer = new Box(HORIZONTAL, 0);
		pairing_button = new Button.with_label(_("Pairing"));
		pairing_button.clicked.connect(on_pairing_clicked);
		footer.pack_start(pairing_button);

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
		box.pack_start(new Separator(HORIZONTAL), false, false, 1);
		box.pack_start(scrolled_window);
		box.pack_start(new Separator(HORIZONTAL), false, false, 1);
		box.pack_end(footer);
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

	private void on_pairing_clicked() {
		// Iterate over all of the adapters, ignoring unpowered ones
		client.get_adapters().foreach((adapter) => {
			if (!adapter.powered) return;

			if (!pairing) {
				// Set the discovery filter
				var properties = new HashTable<string,Variant>(str_hash, str_equal);
				properties["Discoverable"] = new Variant.boolean(true);
				adapter.set_discovery_filter.begin(properties, (obj, res) => {
					try {
						adapter.set_discovery_filter.end(res);

						// Start Bluetooth discovery
						adapter.start_discovery.begin((obj, res) => {
							try {
								adapter.start_discovery.end(res);

								// Set the pairing filter and update our state
								devices_box.set_filter_func(filter_unpaired);
								pairing_button.label = _("Stop Pairing");
								pairing = true;
							} catch (Error e) {
								warning("Error beginning discovery on adapter %s: %s", adapter.alias, e.message);
							}
						});
					} catch (Error e) {
						warning("Error setting discovery filter on %s: %s", adapter.alias, e.message);
					}
				});
			} else {
				// Stop Bluetooth discovery
				adapter.stop_discovery.begin((obj, res) => {
					try {
						adapter.stop_discovery.end(res);

						// Set the normal filter and update our state
						devices_box.set_filter_func(filter_paired);
						pairing_button.label = _("Pairing");
						pairing = false;
					} catch (Error e) {
						warning("Error stopping discovery on adapter %s: %s", adapter.alias, e.message);
					}
				});
			}
		});

		devices_box.invalidate_filter();
		devices_box.invalidate_sort();
	}

	private void add_device(Device1 device) {
		debug("Bluetooth device added: %s", device.alias);

		// Get the adapter that this device is paired with
		Adapter1? adapter = null;
		client.get_adapters().foreach((a) => {
			if (((DBusProxy) a).get_object_path() == device.adapter) {
				adapter = a;
				return; // Exit the lambda
			}
		});

		var widget = new BluetoothDeviceWidget(device, adapter);

		widget.properties_updated.connect(() => {
			client.check_powered();
			devices_box.invalidate_filter();
			devices_box.invalidate_sort();
		});

		devices_box.add(widget);
		devices_box.invalidate_filter();
		devices_box.invalidate_sort();
	}

	private void remove_device(Device1 device) {
		debug("Bluetooth device removed: %s", device.alias);

		devices_box.foreach((row) => {
			var child = ((ListBoxRow) row).get_child() as BluetoothDeviceWidget;
			if (child.device.address == device.address) {
				row.destroy();
			}
		});

		devices_box.invalidate_filter();
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

		if (a_device.device.connected && b_device.device.connected) return strcmp(a_device.device.alias, b_device.device.alias);
		else if (a_device.device.connected) return -1; // A should go before B
		else if (b_device.device.connected) return 1; // B should go before A
		else return strcmp(a_device.device.alias, b_device.device.alias);
	}

	private bool filter_paired(ListBoxRow row) {
		var widget = row.get_child() as BluetoothDeviceWidget;

		return widget.device.paired;
	}

	private bool filter_unpaired(ListBoxRow row) {
		var widget = row.get_child() as BluetoothDeviceWidget;

		return !widget.device.paired;
	}
}

public class BluetoothDeviceWidget : Box {
	private Image? image = null;
	private Label? name_label = null;
	private Label? status_label = null;
	private Revealer? revealer = null;
	private Button? connection_button = null;
	private Button? forget_button = null;

	public Adapter1 adapter { get; construct; }
	public Device1 device { get; construct; }

	public signal void properties_updated();

	construct {
		get_style_context().add_class("bluetooth-widget");

		// Body
		var grid = new Grid();

		image = new Image.from_icon_name(device.icon ?? "bluetooth", LARGE_TOOLBAR) {
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

		forget_button = new Button.with_label(_("Forget Device"));
		forget_button.get_style_context().add_class(STYLE_CLASS_DESTRUCTIVE_ACTION);
		forget_button.clicked.connect(on_forget_clicked);

		revealer_body.pack_start(connection_button);
		revealer_body.pack_end(forget_button);
		revealer.add(revealer_body);

		// Signals
		((DBusProxy) device).g_properties_changed.connect(update_status);

		// Packing
		grid.attach(image, 0, 0);
		grid.attach(name_label, 1, 0);
		grid.attach(status_label, 1, 1);

		pack_start(grid);
		pack_start(revealer);

		update_status();
		show_all();
	}

	public BluetoothDeviceWidget(Device1 device, Adapter1 adapter) {
		Object(
			device: device,
			adapter: adapter,
			orientation: Orientation.VERTICAL,
			spacing: 0
		);
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
				} catch (Error e) {
					warning("Failed to disconnect Bluetooth device %s: %s", device.alias, e.message);
				}

				connection_button.sensitive = true;
			});
		} else if (!device.connected) { // Device isn't connected; connect it
			device.connect.begin((obj, res) => {
				try {
					device.connect.end(res);
				} catch (Error e) {
					warning("Failed to connect to Bluetooth device %s: %s", device.alias, e.message);
				}

				connection_button.sensitive = true;
			});
		} else if (!device.paired) { // Device isn't paired; pair it
			device.pair.begin((obj, res) => {
				try {
					device.pair.end(res);
				} catch (Error e) {
					warning("Error pairing Bluetooth device %s: %s", device.alias, e.message);
				}

				connection_button.sensitive = true;
			});
		}
	}

	/**
	 * Handles when the forget device button is clicked.
	 *
	 * A dialog box will be shown to confirm that the user wishes to forget
	 * the device, meaning it will be unpaired from the adapter and have to
	 * be re-paired before being able to use it again.
	 */
	private void on_forget_clicked() {
		var dialog = new MessageDialog(
			null,
			DialogFlags.MODAL,
			MessageType.QUESTION,
			ButtonsType.OK_CANCEL,
			_("Are you sure you want to forget this device? You will have to pair it to use it again.")
		);

		// Register a handler for the response to the dialog
		dialog.response.connect((response) => {
			switch (response) {
				case ResponseType.OK: // User confirmed removal of the device
					// Get the path to this device
					var path_str = ((DBusProxy) device).get_object_path();
					var path = new ObjectPath(path_str);
					// Remove the device from the adapter it's connected to
					adapter.remove_device.begin(path, (obj, res) => {
						try {
							adapter.remove_device.end(res);
						} catch (Error e) {
							warning("Error forgetting device %s: %s", device.alias, e.message);
						}
					});
					break;
				default: // Any other response; do nothing
					debug("Bluetooth forget dialog had result other than OK");
					break;
			}

			// Destroy the dialog after a response has been received
			dialog.destroy();
		});

		// Show the dialog
		dialog.show();
	}

	private void update_status() {
		if (device.connected) {
			status_label.set_text(_("Connected"));
			connection_button.label = _("Disconnect");
		} else {
			status_label.set_text(_("Disconnected"));
			connection_button.label = _("Connect");
		}

		// Device isn't paired
		if (!device.paired) {
			status_label.set_text(_("Not paired"));
			connection_button.label = _("Pair Devices");
			forget_button.hide();
		} else {
			forget_button.show();
		}

		properties_updated();
	}
}
