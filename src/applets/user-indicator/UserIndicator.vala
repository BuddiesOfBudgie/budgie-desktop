/*
 * This file is part of budgie-desktop
 *
 * Copyright Budgie Desktop Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

public const string USER_SYMBOLIC_ICON = "system-shutdown-symbolic";

public class UserIndicator : Budgie.Plugin, Peas.ExtensionBase {
	public Budgie.Applet get_panel_widget(string uuid) {
		return new UserIndicatorApplet(uuid);
	}
}

public class UserIndicatorApplet : Budgie.Applet {
	private Gtk.Button? button = null;

	private PowerDialogInterface? power_dialog = null;

	public string uuid { public set ; public get; }

	public UserIndicatorApplet(string uuid) {
		Object(uuid: uuid);

		button = new Gtk.Button.from_icon_name(USER_SYMBOLIC_ICON, Gtk.IconSize.MENU);

		Bus.get_proxy.begin<PowerDialogInterface>(
			GLib.BusType.SESSION,
			"org.buddiesofbudgie.PowerDialog",
			"/org/buddiesofbudgie/PowerDialog",
			GLib.DBusProxyFlags.NONE,
			null,
			on_dialog_acquired
		);

		button.clicked.connect(on_button_clicked);

		add(button);
		show_all();
	}

	private void on_dialog_acquired(Object? obj, AsyncResult? res) {
		try {
			power_dialog = Bus.get_proxy.end<PowerDialogInterface>(res);
		} catch (Error e) {
			critical("Unable to get PowerDialog proxy: %s", e.message);
		}
	}

	private void on_button_clicked() {
		if (power_dialog == null) {
			warning("Attempted to open PowerDialog, but we don't have a DBus proxy!");
			return;
		}

		try {
			power_dialog.Show();
		} catch (Error e) {
			critical("Error showing PowerDialog: %s", e.message);
		}
	}
}

[ModuleInit]
public void peas_register_types(TypeModule module) {
	// boilerplate - all modules need this
	var objmodule = module as Peas.ObjectModule;
	objmodule.register_extension_type(typeof(Budgie.Plugin), typeof(UserIndicator));
}
