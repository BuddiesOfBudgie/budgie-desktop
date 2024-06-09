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
	private Label? placeholder_label = null;
	private Label? placeholder_sublabel = null;

	private BluetoothClient client;
	private ObexManager obex_manager;

	private ulong switch_handler_id;

	construct {
		image = new Image();

		ebox = new EventBox();
		ebox.add(image);
		ebox.add_events(EventMask.BUTTON_RELEASE_MASK);
		ebox.button_release_event.connect(on_button_released);

		// Create our Bluetooth client
		client = new BluetoothClient();
		obex_manager = new ObexManager();

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

		// Handle changes to airplane mode
		client.airplane_mode_changed.connect(update_state_ui);

		// Show or hide the panel widget if we have a Bluetooth adapter or not
		client.notify["has-adapter"].connect(() => {
			if (client.has_adapter) show_all();
			else hide();
		});

		// Create our popover
		popover = new Budgie.Popover(ebox);
		popover.set_size_request(275, -1);
		popover.get_style_context().add_class("bluetooth-popover");
		var box = new Box(VERTICAL, 0);

		// Header
		var header = new Box(HORIZONTAL, 0) {
			margin_start = 4,
			margin_end = 4,
		};
		header.get_style_context().add_class("bluetooth-header");

		// Header label
		var header_attributes = new Pango.AttrList();
		var weight_attr = new Pango.FontDescription();
		weight_attr.set_weight(Pango.Weight.BOLD);
		header_attributes.insert(new Pango.AttrFontDesc(weight_attr));

		var switch_label = new Label(_("Bluetooth")) {
			attributes = header_attributes,
			halign = START,
			margin_start = 4,
		};
		switch_label.get_style_context().add_class(STYLE_CLASS_DIM_LABEL);

		// Settings button
		var settings_button = new Button.from_icon_name("preferences-system-symbolic", MENU) {
			relief = ReliefStyle.NONE,
			tooltip_text = _("Bluetooth Settings")
		};
		settings_button.clicked.connect(on_settings_activate);

		// Bluetooth switch
		bluetooth_switch = new Switch() {
			tooltip_text = _("Turn Bluetooth on or off"),
		};
		switch_handler_id = bluetooth_switch.notify["active"].connect(on_switch_activate);

		header.pack_start(switch_label);
		header.pack_end(bluetooth_switch, false, false);
		header.pack_end(settings_button, false, false);

		// Devices
		var scrolled_window = new ScrolledWindow(null, null) {
			hscrollbar_policy = NEVER,
			min_content_height = 190,
			max_content_height = 190,
			propagate_natural_height = true
		};
		devices_box = new ListBox() {
			selection_mode = NONE
		};
		devices_box.set_filter_func(filter_paired_devices);
		devices_box.set_sort_func(sort_devices);
		devices_box.get_style_context().add_class("bluetooth-device-listbox");

		devices_box.row_activated.connect((row) => {
			((BTDeviceRow) row).toggle_connection.begin();
		});

		// Placeholder
		var placeholder = new Box(Orientation.VERTICAL, 18) {
			margin_top = 18,
		};

		var label_attributes = new Pango.AttrList();
		label_attributes.insert(new Pango.AttrFontDesc(weight_attr));

		placeholder_label = new Label(null) {
			attributes = label_attributes,
			justify = CENTER,
		};

		placeholder_label.get_style_context().add_class(STYLE_CLASS_DIM_LABEL);
		placeholder_label.get_style_context().add_class("bluetooth-placeholder");

		placeholder_sublabel = new Label(null) {
			justify = CENTER,
			wrap = true,
		};

		placeholder.pack_start(placeholder_label, false);
		placeholder.pack_start(placeholder_sublabel, false);
		placeholder.show_all(); // Without this, it never shows. Because... reasons?
		devices_box.set_placeholder(placeholder);
		scrolled_window.add(devices_box);

		// Make sure our starting icon is correct
		update_state_ui();

		add(ebox);
		box.pack_start(header);
		box.pack_start(new Separator(HORIZONTAL), true, true, 4);
		box.pack_start(scrolled_window);
		box.show_all();
		popover.add(box);

		// Only show if we have an adapter present
		if (client.has_adapter) show_all();
	}

	private bool on_button_released(EventButton e) {
		if (e.button != BUTTON_MIDDLE) return EVENT_PROPAGATE;

		// Disconnect all Bluetooth on middle click
		var enabled = client.airplane_mode_enabled();
		client.set_airplane_mode(!enabled);

		return Gdk.EVENT_STOP;
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
		var active = bluetooth_switch.active;
		client.set_airplane_mode(!active); // If the switch is active, then Bluetooth is enabled. So invert the value
	}

	private void add_device(Device1 device) {
		debug("Bluetooth device added: %s", device.alias);

		var widget = new BTDeviceRow(device, obex_manager);

		widget.properties_updated.connect(() => {
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
			var child = row as BTDeviceRow;
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
		if (client.airplane_mode_enabled()) return false;

		return ((BTDeviceRow) row).device.paired || ((BTDeviceRow) row).device.connected;
	}

	/**
	 * Update the tray icon and Bluetooth switch state to reflect the current
	 * state of airplane mode.
	 */
	private void update_state_ui() {
		var enabled = client.airplane_mode_enabled();

		// Update the tray icon and placeholder text
		if (enabled) { // Airplane mode is on, so Bluetooth is disabled
			image.set_from_icon_name("bluetooth-disabled-symbolic", IconSize.MENU);
			placeholder_label.label = _("Airplane mode is on.");
			placeholder_sublabel.label = _("Bluetooth is disabled while airplane mode is on.");
		} else { // Airplane mode is off, so Bluetooth is enabled
			image.set_from_icon_name("bluetooth-active-symbolic", IconSize.MENU);
			placeholder_label.label = _("No paired Bluetooth devices found.");
			placeholder_sublabel.label = _("Visit Bluetooth settings to pair a device.");
		}

		// Update our switch state
		SignalHandler.block(bluetooth_switch, switch_handler_id);
		bluetooth_switch.active = !enabled; // Airplane mode value is opposite of our switch state
		SignalHandler.unblock(bluetooth_switch, switch_handler_id);

		devices_box.invalidate_filter();
		devices_box.invalidate_sort();
	}
}

/**
 * Widget for displaying a Bluetooth device in a ListBox.
 */
public class BTDeviceRow : ListBoxRow {
	private const string OBEX_AGENT = "org.bluez.obex.Agent1";
	private const string OBEX_PATH = "/org/bluez/obex/budgie";
	private const uint32 SMARTPHONE_MASK = 0x20C;
	private const uint32 DESKTOP_MASK = 0x104;
	private const uint32 LAPTOP_MASK = 0x10C;

	private Image? image = null;
	private Label? name_label = null;
	private Revealer? battery_revealer = null;
	private Image? battery_icon = null;
	private Label? battery_label = null;
	private Revealer? revealer = null;
	private Spinner? spinner = null;
	private Label? status_label = null;
	private Button? send_button = null;
	private Button? connection_button = null;
	private Revealer? progress_revealer = null;
	private Label? file_label = null;
	private Label? progress_label = null;
	private ProgressBar? progress_bar = null;

	public Device1 device { get; construct; }
	public ObexManager obex_manager { get; construct; }
	public Transfer transfer;

	private ulong up_handler_id = 0;
	private Up.Device? _up_device;
	public Up.Device? up_device {
		get { return _up_device; }
		set {
			// Disconnect previous signal handler
			if (up_handler_id != 0) {
				_up_device.disconnect(up_handler_id);
				up_handler_id = 0;
			}
			// Set new UPower device
			_up_device = value;
			update_battery();
			// Connect to signal if the new device isn't null
			if (_up_device == null) return;
			up_handler_id = _up_device.notify.connect(() => {
				update_battery();
			});
		}
	}

	public signal void properties_updated();

	construct {
		get_style_context().add_class("bluetooth-device-row");

		// Obex manager for file transfers
		obex_manager.transfer_active.connect(transfer_active);
		obex_manager.transfer_added.connect(transfer_added);
		obex_manager.transfer_removed.connect(transfer_removed);

		// Body
		var box = new Box(Orientation.VERTICAL, 0);
		var grid = new Grid() {
			column_spacing = 6,
		};

		var icon_name = device.icon ?? "bluetooth-active";
		if (!icon_name.has_suffix("-symbolic")) icon_name += "-symbolic";
		image = new Image.from_icon_name(icon_name, MENU) {
			margin_start = 4,
			margin_end = 4,
		};
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
			margin_top = 2,
		};

		var battery_box = new Box(Orientation.HORIZONTAL, 0);

		battery_icon = new Image();

		var label_attributes = new Pango.AttrList();
		var desc = new Pango.FontDescription();
		desc.set_stretch(Pango.Stretch.ULTRA_CONDENSED);
		desc.set_weight(Pango.Weight.SEMILIGHT);
		label_attributes.insert(new Pango.AttrFontDesc(desc));

		battery_label = new Label(null) {
			attributes = label_attributes,
			halign = START,
		};
		battery_label.get_style_context().add_class(STYLE_CLASS_DIM_LABEL);
		battery_label.get_style_context().add_class("bluetooth-battery-label");

		battery_box.pack_start(battery_icon, false, false, 2);
		battery_box.pack_start(battery_label, false, false, 2);

		battery_revealer.add(battery_box);

		// Status area stuff
		var status_box = new Box(HORIZONTAL, 6);

		revealer = new Revealer() {
			reveal_child = false,
			transition_duration = 250,
			transition_type = RevealerTransitionType.CROSSFADE,
		};
		revealer.get_style_context().add_class("bluetooth-device-revealer");

		spinner = new Spinner();

		status_label = new Label(null) {
			attributes = label_attributes,
			halign = START,
		};
		status_label.get_style_context().add_class("bluetooth-device-status");
		status_label.get_style_context().add_class(STYLE_CLASS_DIM_LABEL);

		revealer.add(spinner);
		status_box.pack_start(status_label, false);
		status_box.pack_start(revealer, false);

		var button_box = new Box(Orientation.HORIZONTAL, 0) {
			homogeneous = false,
		};

		// Send button
		send_button = new Button.from_icon_name("folder-download-symbolic") {
			relief = ReliefStyle.NONE,
			tooltip_text = _("Send file"),
		};
		send_button.get_style_context().add_class("circular");
		send_button.clicked.connect(() => {
			string[] args = { "org.buddiesofbudgie.sendto", "-a", device.address, "-f" };
			var env = Environ.get();
			Pid pid;

			try {
				Process.spawn_async(
					null,
					args,
					env,
					SEARCH_PATH_FROM_ENVP,
					null,
					out pid
				);
			} catch (SpawnError e) {
				warning("Error starting sendto: %s", e.message);
			}
		});

		// Disconnect button
		connection_button = new Button.from_icon_name("bluetooth-disabled-symbolic", IconSize.BUTTON) {
			relief = ReliefStyle.NONE,
			tooltip_text = _("Disconnect"),
		};
		connection_button.get_style_context().add_class("circular");
		connection_button.get_style_context().add_class("bluetooth-connection-button");
		connection_button.clicked.connect(() => {
			toggle_connection.begin();
		});

		button_box.pack_start(send_button, true, true, 0);
		button_box.pack_start(connection_button, true, true, 0);

		// Progress stuff
		progress_revealer = new Revealer() {
			reveal_child = false,
			transition_duration = 250,
			transition_type = RevealerTransitionType.SLIDE_DOWN,
			margin_left = 4,
			margin_right = 4,
		};

		progress_label = new Label(null) {
			halign = Align.START,
			valign = Align.END,
			use_markup = true,
			hexpand = true,
		};

		progress_bar = new ProgressBar() {
			hexpand = true,
			margin_top = 6,
			margin_bottom = 6,
		};

		file_label = new Label(null) {
			ellipsize = Pango.EllipsizeMode.MIDDLE,
			halign = Align.START,
			valign = Align.END,
			use_markup = true,
			hexpand = true,
		};

		var progress_grid = new Grid();
		progress_grid.attach(file_label, 0, 0);
		progress_grid.attach(progress_bar, 0, 1);
		progress_grid.attach(progress_label, 0, 2);
		progress_revealer.add(progress_grid);

		// Signals
		((DBusProxy) device).g_properties_changed.connect(update_status);

		// Packing
		grid.attach(image, 0, 0, 2, 2);
		grid.attach(name_label, 2, 0, 2, 1);
		grid.attach(button_box, 4, 0, 1, 2);
		grid.attach(status_box, 2, 1, 2, 1);
		grid.attach(battery_revealer, 2, 2, 1, 1);

		var box_grid = new Grid();
		box_grid.attach(grid, 0, 0);
		box_grid.attach(progress_revealer, 0, 1);

		box.pack_start(box_grid);
		add(box);

		show_all();
		send_button.hide();
		update_status();
	}

	public BTDeviceRow(Device1 device, ObexManager obex_manager) {
		Object(device: device, obex_manager: obex_manager);
	}

	private void hide_progress_revealer() {
		progress_label.label = "";
		progress_revealer.reveal_child = false;
	}

	/**
	 * Attempts to either connect to or disconnect from the Bluetooth
	 * device depending on its current connection state.
	 */
	public async void toggle_connection() {
		// Show transfer progress dialog on click if a transfer is
		// in progress
		if (progress_revealer.child_revealed) {
			try {
				var conn = yield Bus.get(BusType.SESSION);
				yield conn.call(
					OBEX_AGENT,
					OBEX_PATH,
					OBEX_AGENT,
					"TransferActive",
					new Variant("(s)", transfer.session),
					null,
					DBusCallFlags.NONE,
					-1
				);
			} catch (Error e) {
				warning("Error activating Bluetooth file transfer: %s", e.message);
			}

			return;
		}

		if (spinner.active) return;

		spinner.active = true;
		revealer.reveal_child = true;

		try {
			if (device.connected) {
				status_label.label = _("Disconnecting…");
				yield device.disconnect();
			} else {
				status_label.label = _("Connecting…");
				yield device.connect();
			}
		} catch (Error e) {
			warning("Failed to connect or disconnect Bluetooth device %s: %s", device.alias, e.message);
			status_label.label = device.connected ? _("Failed to disconnect") : _("Failed to connect");
		}

		revealer.reveal_child = true;
		spinner.active = false;
	}

	private void transfer_active(string address) {
		if (address == device.address) update_transfer_progress();
	}

	private void transfer_added(string address, Transfer transfer) {
		if (address == device.address) this.transfer = transfer;
	}

	private void transfer_removed(Transfer transfer) {
		hide_progress_revealer();
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
			fallback_icon_name = "battery-caution";
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
		status_label.set_text(device.connected ? _("Connected") : _("Disconnected"));

		if (device.connected) {
			connection_button.show();

			// We only want to show the send button if the device
			// can actually receive files.
			if ((device.@class & SMARTPHONE_MASK) == SMARTPHONE_MASK ||
				(device.@class & DESKTOP_MASK) == DESKTOP_MASK ||
				(device.@class & LAPTOP_MASK) == LAPTOP_MASK) {
				send_button.show();
			}

			update_battery();
		} else {
			connection_button.hide();
			send_button.hide();
			battery_revealer.reveal_child = false;
		}

		// Update the name if changed
		if (device.alias != name_label.label) {
			name_label.label = device.alias;
			name_label.tooltip_text = device.alias;
		}

		properties_updated();
	}

	private void update_transfer_progress() {
		switch (transfer.status) {
			case "error":
				hide_progress_revealer();
				break;
			case "queued":
				hide_progress_revealer();
				break;
			case "active":
				// Update the progress bar
				progress_bar.fraction = (double) transfer.transferred / (double) transfer.size;
				progress_revealer.reveal_child = true;
				activatable = true;

				// Update the filename label
				var name = transfer.name;
				if (name != null) {
					file_label.set_markup(_("<b>Filename</b>: %s").printf(Markup.escape_text(name)));
				}

				// Update the progress label
				var file_name = transfer.filename;
				if (file_name != null) {
					if (file_name.contains("/.cache/obexd")) {
						progress_label.label = _("Receiving… %s of %s").printf(
							format_size(transfer.transferred),
							format_size(transfer.size)
						);
					} else {
						progress_label.label = _("Sending… %s of %s").printf(
							format_size(transfer.transferred),
							format_size(transfer.size)
						);
					}
				}
				break;
			case "complete":
				hide_progress_revealer();
				if (device.connected) {
					activatable = false;
				}
				break;
		}
	}
}
