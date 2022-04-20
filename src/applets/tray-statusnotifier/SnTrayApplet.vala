/*
 * This file is part of budgie-desktop
 *
 * Copyright © 2015-2022 Budgie Desktop Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

public class SnTrayPlugin : Budgie.Plugin, Peas.ExtensionBase {
	public Budgie.Applet get_panel_widget(string uuid) {
		return new SnTrayApplet(uuid);
	}
}

[GtkTemplate (ui="/org/buddiesofbudgie/sntray/settings.ui")]
public class SnTraySettings : Gtk.Grid {
	Settings? settings = null;

	[GtkChild]
	private unowned Gtk.SpinButton? spinbutton_spacing;

	public SnTraySettings(Settings? settings) {
		this.settings = settings;
		settings.bind("spacing", spinbutton_spacing, "value", SettingsBindFlags.DEFAULT);
	}
}

public class SnTrayApplet : Budgie.Applet {
	public string uuid { public set; public get; }
	private Settings? settings;
	private Gtk.EventBox box;
	private Gtk.Orientation orient;

	private static StatusNotifierWatcher? watcher;
	private static int ref_counter;

	public SnTrayApplet(string uuid) {
		Object(uuid: uuid);

		get_style_context().add_class("system-tray-applet");

		box = new Gtk.EventBox();
		add(box);

		settings_schema = "org.buddiesofbudgie.sntray";
		settings_prefix = "/org/buddiesofbudgie/budgie-panel/instance/sntray";

		settings = get_applet_settings(uuid);

		AtomicInt.inc(ref ref_counter);
		if (watcher == null) {
			watcher = new StatusNotifierWatcher();
		}

		show_all();
	}

	~SnTrayApplet() {
		// if this is the last applet left and it's being deleted, we don't need the watcher
		if (AtomicInt.dec_and_test(ref ref_counter)) {
			watcher = null;
		}
	}

	public override void panel_position_changed(Budgie.PanelPosition position) {
		if (position == Budgie.PanelPosition.LEFT || position == Budgie.PanelPosition.RIGHT) {
			orient = Gtk.Orientation.VERTICAL;
		} else {
			orient = Gtk.Orientation.HORIZONTAL;
		}
	}

	public override bool supports_settings() {
		return true;
	}

	public override Gtk.Widget? get_settings_ui() {
		return new SnTraySettings(get_applet_settings(uuid));
	}
}

[ModuleInit]
public void peas_register_types(TypeModule module) {
	// boilerplate - all modules need this
	var objmodule = module as Peas.ObjectModule;
	objmodule.register_extension_type(typeof(Budgie.Plugin), typeof(SnTrayPlugin));
}
