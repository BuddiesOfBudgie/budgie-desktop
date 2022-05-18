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
		this.abomination.active_workspace_changed.connect((previous, current) => this.on_active_workspace_changed(current));
	}

	public override bool scroll_event(Gdk.EventScroll event) {
		if (event.direction == Gdk.ScrollDirection.UP) { // Scrolling up
			scroller.hadjustment.value -= 50;
		} else { // Scrolling down
			scroller.hadjustment.value += 50; // Always increment by 50
		}

		return Gdk.EVENT_STOP;
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

	private void on_app_opened(Budgie.Abomination.RunningApp app) {
		if (this.buttons.contains(app.id.to_string())) {
			return;
		}

		var button = new Button(app);
		this.container.pack_start(button);
		this.show_all();

		this.buttons.insert(app.id.to_string(), button);
	}

	private void on_app_closed(Budgie.Abomination.RunningApp app) {
		var button = this.buttons.get(app.id.to_string());
		if (button == null) {
			return;
		}

		button.gracefully_die();

		this.buttons.remove(app.id.to_string());
	}

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

	private void on_active_workspace_changed(Budgie.Abomination.Workspace current_workspace) {
		// TODO: Iterate through the buttons & check if button is part of the workspace or not
	}
}

[ModuleInit]
public void peas_register_types(TypeModule module) {
	// boilerplate - all modules need this
	var objmodule = module as Peas.ObjectModule;
	objmodule.register_extension_type(typeof(Budgie.Plugin), typeof(SimpleTasklistPlugin));
}
