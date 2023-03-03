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

public class SimpleTasklistPlugin : Budgie.Plugin, Peas.ExtensionBase {
	public Budgie.Applet get_panel_widget(string uuid) {
		return new SimpleTasklistApplet();
	}
}

public class SimpleTasklistApplet : Budgie.Applet {

	public string uuid { public set; public get; }

	private Gtk.ScrolledWindow? scroller;

	private Gtk.Box? container;

	private Budgie.Abomination.Abomination? abomination;
	private HashTable<string, Button> buttons;

	public SimpleTasklistApplet() {
		this.buttons = new HashTable<string, Button>(str_hash, str_equal);

		this.scroller = new Gtk.ScrolledWindow(null, null);

		this.scroller.overlay_scrolling = true;
		this.scroller.propagate_natural_height = true;
		this.scroller.propagate_natural_width = true;
		this.scroller.shadow_type = Gtk.ShadowType.NONE;
		this.scroller.hscrollbar_policy = Gtk.PolicyType.EXTERNAL;
		this.scroller.vscrollbar_policy = Gtk.PolicyType.NEVER;

		this.container = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);

		this.scroller.add(this.container);

		this.add(this.scroller);

		this.abomination = new Budgie.Abomination.Abomination();

		this.abomination.added_app.connect((group, app) => this.on_app_opened(app));
		this.abomination.removed_app.connect((group, app) => this.on_app_closed(app));
		this.abomination.active_app_changed.connect(this.on_active_app_changed);
		this.abomination.active_workspace_changed.connect(this.on_active_workspace_changed);
	}

	/**
	 * Update the tasklist orientation to match the panel direction
	 */
	public override void panel_position_changed(Budgie.PanelPosition position) {
		Gtk.Orientation orientation = Gtk.Orientation.HORIZONTAL;
		if (position == Budgie.PanelPosition.LEFT || position == Budgie.PanelPosition.RIGHT) {
			orientation = Gtk.Orientation.VERTICAL;
		}

		this.container.set_orientation(orientation);

		if (orientation == Gtk.Orientation.HORIZONTAL) {
			this.scroller.hscrollbar_policy = Gtk.PolicyType.EXTERNAL;
			this.scroller.vscrollbar_policy = Gtk.PolicyType.NEVER;
		} else {
			this.scroller.hscrollbar_policy = Gtk.PolicyType.NEVER;
			this.scroller.vscrollbar_policy = Gtk.PolicyType.EXTERNAL;
		}
	}

	/**
	 * Create a button for the newly opened app and add it to our tracking map.
	 */
	private void on_app_opened(Budgie.Abomination.RunningApp app) {
		if (this.buttons.contains(app.id.to_string())) {
			return;
		}

		app.workspace_changed.connect(() => this.on_app_workspace_changed(app));

		var button = new Button(app);
		this.container.pack_start(button);
		this.show_all();

		this.buttons.insert(app.id.to_string(), button);
	}

	/**
	 * Gracefully remove button associated with app and remove it from our
	 * tracking map.
	 */
	private void on_app_closed(Budgie.Abomination.RunningApp app) {
		var button = this.buttons.get(app.id.to_string());
		if (button == null) {
			return;
		}

		button.gracefully_die();

		this.buttons.remove(app.id.to_string());
	}

	/**
	 * Manage active state of buttons, mark button associated with new active
	 * app as active and previous active button as inactive.
	 */
	private void on_active_app_changed(Budgie.Abomination.RunningApp? previous_app, Budgie.Abomination.RunningApp? current_app) {
		if (previous_app != null) {
			var button = this.buttons.get(previous_app.id.to_string());
			if (button == null) {
				return;
			}
			button.set_active(false);
		}
		if (current_app != null) {
			var button = this.buttons.get(current_app.id.to_string());
			if (button == null) {
				return;
			}
			button.set_active(true);
		}
	}

	/**
	 * Go through the managed buttons list and check if they should be
	 * displayed for the current workspace.
	 */
	private void on_active_workspace_changed() {
		foreach (Button button in this.buttons.get_values()) {
			this.on_app_workspace_changed(button.app);
		}
	}

	/**
	 * Show / Hide button attached to the app depending on if it is in the
	 * current workspace.
	 */
	private void on_app_workspace_changed(Budgie.Abomination.RunningApp app) {
		var button = this.buttons.get(app.id.to_string());
		if (button == null) {
			return;
		}

		if (app.workspace.get_number() == this.abomination.get_active_workspace().get_number()) {
			button.show();
			button.set_no_show_all(false);
		} else {
			button.hide();
			button.set_no_show_all(true); // make sure we don't randomly show buttons not belonging to the current workspace
		}
	}
}

[ModuleInit]
public void peas_register_types(TypeModule module) {
	// boilerplate - all modules need this
	var objmodule = module as Peas.ObjectModule;
	objmodule.register_extension_type(typeof(Budgie.Plugin), typeof(SimpleTasklistPlugin));
}
