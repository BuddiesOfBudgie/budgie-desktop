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

public class SpacerPlugin : Budgie.Plugin, Peas.ExtensionBase {
	public Budgie.Applet get_panel_widget(string uuid) {
		return new SpacerApplet(uuid);
	}
}

[GtkTemplate (ui="/com/solus-project/spacer/settings.ui")]
public class SpacerSettings : Gtk.Grid {
	Settings? settings = null;

	[GtkChild]
	private unowned Gtk.SpinButton? spinbutton_size;

	public SpacerSettings(Settings? settings) {
		this.settings = settings;
		settings.bind("size", spinbutton_size, "value", SettingsBindFlags.DEFAULT);
	}
}

public class SpacerApplet : Budgie.Applet {
	public int space_size { public set; public get; default = 5; }

	public string uuid { public set; public get; }

	private Settings? settings;
	private Budgie.PanelPosition panel_position = Budgie.PanelPosition.BOTTOM;

	public override bool supports_settings() {
		return true;
	}

	public override Gtk.Widget? get_settings_ui() {
		return new SpacerSettings(this.get_applet_settings(uuid));
	}

	public SpacerApplet(string uuid) {
		Object(uuid: uuid);

		settings_schema = "com.solus-project.spacer";
		settings_prefix = "/com/solus-project/budgie-panel/instance/spacer";

		settings = this.get_applet_settings(uuid);
		settings.changed.connect(on_settings_change);
		on_settings_change("size");

		show_all();
	}

	void on_settings_change(string key) {
		if (key != "size") {
			return;
		}
		this.space_size = settings.get_int(key);
		queue_resize();
	}

	/**
	 * Our panel has moved somewhere, stash the position
	 */
	public override void panel_position_changed(Budgie.PanelPosition position) {
		this.panel_position = position;
		queue_resize();
	}

	private bool on_vertical_panel() {
		return this.panel_position == Budgie.PanelPosition.LEFT ||
			this.panel_position == Budgie.PanelPosition.RIGHT;
	}

	public override void get_preferred_width(out int min, out int nat) {
		// On a horizontal panel our width is the configured spacing; on a vertical one the panel decides our width, so request 0
		min = nat = on_vertical_panel() ? 0 : space_size;
	}

	public override void get_preferred_width_for_height(int h, out int min, out int nat) {
		// Same as get_preferred_width
		min = nat = on_vertical_panel() ? 0 : space_size;
	}

	public override void get_preferred_height(out int min, out int nat) {
		// On a vertical panel our height is the configured spacing; on a horizontal one the panel decides our height, so request 0
		min = nat = on_vertical_panel() ? space_size : 0;
	}

	public override void get_preferred_height_for_width(int h, out int min, out int nat) {
		// Same as get_preferred_height
		min = nat = on_vertical_panel() ? space_size : 0;
	}
}

[ModuleInit]
public void peas_register_types(TypeModule module) {
	// boilerplate - all modules need this
	var objmodule = module as Peas.ObjectModule;
	objmodule.register_extension_type(typeof(Budgie.Plugin), typeof(SpacerPlugin));
}
