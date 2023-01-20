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

	public BluetoothIndicator() {
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
		devices_box = new ListBox();
		scrolled_window.add(devices_box);
		main_page.pack_start(scrolled_window);

		// Create our Bluetooth client
		client = new BluetoothClient();
		client.device_added.connect((device) => {
			message("Bluetooth device added: %s", device.alias);
		});

		client.device_removed.connect((device) => {
			message("Bluetooth device removed: %s", device.alias);
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
}
