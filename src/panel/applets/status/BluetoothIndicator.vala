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

public class BluetoothIndicator : Gtk.Bin {
	public Gtk.Image? image = null;

	public Gtk.EventBox? ebox = null;
#if with_bluetooth
	private Bluetooth.Client? client = null;
#endif
	private Gtk.TreeModel? model = null;
	public Budgie.Popover? popover = null;


	Gtk.CheckButton radio_airplane;
	ulong radio_id;
	Gtk.Button send_to;

	public BluetoothIndicator() {
		image = new Gtk.Image.from_icon_name("bluetooth-active-symbolic", Gtk.IconSize.MENU);

		ebox = new Gtk.EventBox();
		add(ebox);

		ebox.add(image);

		ebox.add_events(Gdk.EventMask.BUTTON_RELEASE_MASK);
		ebox.button_release_event.connect(on_button_release_event);

		// Create our popover
		popover = new Budgie.Popover(ebox);
		var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 1);
		box.border_width = 6;
		popover.add(box);

		// Settings button
		var button = new Gtk.Button.with_label(_("Bluetooth Settings"));
		button.get_child().set_halign(Gtk.Align.START);
		button.get_style_context().add_class(Gtk.STYLE_CLASS_FLAT);
		button.clicked.connect(on_settings_activate);
		box.pack_start(button, false, false, 0);

		// Send files button
		send_to = new Gtk.Button.with_label(_("Send Files"));
		send_to.get_child().set_halign(Gtk.Align.START);
		send_to.get_style_context().add_class(Gtk.STYLE_CLASS_FLAT);
		//  send_to.clicked.connect(on_send_file);
		box.pack_start(send_to, false, false, 0);

		var sep = new Gtk.Separator(Gtk.Orientation.HORIZONTAL);
		box.pack_start(sep, false, false, 1);

		// Airplane mode
		radio_airplane = new Gtk.CheckButton.with_label(_("Bluetooth Airplane Mode"));
		radio_airplane.get_child().set_property("margin", 4);
		box.pack_start(radio_airplane, false, false, 0);

		// Ensure all content is shown
		box.show_all();

#if with_bluetooth
		client = new Bluetooth.Client();
		model = client.get_model();
#endif
		model.row_changed.connect(() => { resync(); });
		model.row_deleted.connect(() => { resync(); });
		model.row_inserted.connect(() => { resync(); });

		this.resync();

		this.setup_dbus.begin(() => {

		});

		show_all();
	}

	private bool on_button_release_event(Gdk.EventButton e) {
		if (e.button == Gdk.BUTTON_MIDDLE) { // Middle click

		} else {
			return Gdk.EVENT_PROPAGATE;
		}

		return Gdk.EVENT_STOP;
	}

	async void setup_dbus() {
		try {
		} catch (Error e) {
			return;
		}
	}

	bool get_default_adapter(out Gtk.TreeIter? adapter) {
		adapter = null;
		Gtk.TreeIter iter;

		if (!model.get_iter_first(out iter)) {
			return false;
		}

#if with_bluetooth
		while (true) {
			bool is_default;
			model.get(iter, Bluetooth.Column.DEFAULT, out is_default, -1);
			if (is_default) {
				adapter = iter;
				return true;
			}
			if (!model.iter_next(ref iter)) {
				break;
			}
		}
#endif
		return false;
	}

	int get_n_devices() {
		Gtk.TreeIter iter;
		Gtk.TreeIter? adapter;
		int n_devices = 0;

		if (!get_default_adapter(out adapter)) {
			return -1;
		}

		if (!model.iter_children(out iter, adapter)) {
			return 0;
		}

#if with_bluetooth
		while (true) {
			bool con = true;
			model.get(iter, Bluetooth.Column.CONNECTED, out con, -1);
			if (con) {
				n_devices++;
			}
			if (!model.iter_next(ref iter)) {
				break;
			}
		}

#endif
		return n_devices;
	}

	private void resync() {
		var n_devices = get_n_devices();
		string? lbl = null;

		if (killer != null) {
			if (killer.BluetoothAirplaneMode) {
				image.set_from_icon_name("bluetooth-disabled-symbolic", Gtk.IconSize.MENU);
				lbl = _("Bluetooth is disabled");
				n_devices = 0;
			} else {
				image.set_from_icon_name("bluetooth-active-symbolic", Gtk.IconSize.MENU);
				lbl = _("Bluetooth is active");
			}
		}

		if (n_devices > 0) {
			lbl = ngettext("Connected to %d device", "Connected to %d devices", n_devices).printf(n_devices);
			send_to.set_sensitive(true);
		} else if (n_devices < 0) {
			hide();
			return;
		} else {
			send_to.set_sensitive(false);
		}

		/* TODO: Determine if bluetooth is actually active (rfkill) */
		show();
		image.set_tooltip_text(lbl);
	}

	void on_settings_activate() {
		this.popover.hide();

		var app_info = new DesktopAppInfo("budgie-bluetooth-panel.desktop");
		if (app_info == null) {
			return;
		}
		try {
			app_info.launch(null, null);
		} catch (Error e) {
			message("Unable to launch budgie-bluetooth-panel.desktop: %s", e.message);
		}
	}
}
