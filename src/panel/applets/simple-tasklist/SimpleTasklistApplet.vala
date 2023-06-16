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

using Gdk;
using Gtk;
using libxfce4windowing;

public const int MAX_BUTTON_LENGTH = 200;
public const int MIN_BUTTON_LENGTH = MAX_BUTTON_LENGTH / 4;
public const int ARROW_BUTTON_SIZE = 20;

public class SimpleTasklistPlugin : Budgie.Plugin, Peas.ExtensionBase {
	public Budgie.Applet get_panel_widget(string uuid) {
		return new SimpleTasklistApplet(uuid);
	}
}

public class SimpleTasklistApplet : Budgie.Applet {
	public string uuid { public set; public get; }

	private Box container;

	private HashTable<string, Button> buttons;
	private libxfce4windowing.Screen screen;
	private unowned libxfce4windowing.WorkspaceManager workspace_manager;

	public SimpleTasklistApplet(string uuid) {
		Object(uuid: uuid, hexpand: false);
	}

	construct {
		get_style_context().add_class("simple-tasklist");

		this.buttons = new HashTable<string, Button>(str_hash, str_equal);

		this.container = new Box(Orientation.HORIZONTAL, 0) {
			homogeneous = true,
		};

		add(container);

		this.screen = libxfce4windowing.Screen.get_default();

		this.screen.window_opened.connect(on_app_opened);
		this.screen.window_closed.connect(on_app_closed);
		this.screen.active_window_changed.connect(on_active_window_changed);

		setup_workspace_listener();

		show_all();
	}

	private void setup_workspace_listener() {
		this.workspace_manager = screen.get_workspace_manager();
		unowned var groups = workspace_manager.list_workspace_groups();
		if (groups == null) return;

		unowned var element = groups.first();
		var group = element.data as libxfce4windowing.WorkspaceGroup;

		if (group == null) return;

		group.active_workspace_changed.connect(on_active_workspace_changed);
	}

	/**
	 * Update the tasklist orientation to match the panel direction
	 */
	public override void panel_position_changed(Budgie.PanelPosition position) {
		Orientation orientation = Orientation.HORIZONTAL;
		if (position == Budgie.PanelPosition.LEFT || position == Budgie.PanelPosition.RIGHT) {
			orientation = Orientation.VERTICAL;
		}

		this.container.set_orientation(orientation);
	}

	/**
	 * Create a button for the newly opened app and add it to our tracking map.
	 */
	private void on_app_opened(libxfce4windowing.Window window) {
		if (window.is_skip_tasklist()) return;
		if (buttons.contains(window.get_id().to_string().to_string())) return;

		window.workspace_changed.connect(() => this.on_app_workspace_changed(window));

		var button = new Button(window);
		this.container.pack_start(button);

		//  if (window.get_workspace().)

		this.buttons.insert(window.get_id().to_string(), button);
	}

	/**
	 * Gracefully remove button associated with app and remove it from our
	 * tracking map.
	 */
	private void on_app_closed(libxfce4windowing.Window window) {
		var button = this.buttons.get(window.get_id().to_string());
		if (button == null) {
			return;
		}

		button.gracefully_die();

		this.buttons.remove(window.get_id().to_string());
	}

	/**
	 * Manage active state of buttons, mark button associated with new active
	 * app as active and previous active button as inactive.
	 */
	private void on_active_window_changed(libxfce4windowing.Window? old_window) {
		if (old_window != null) {
			var button = this.buttons.get(old_window.get_id().to_string());
			if (button == null) return;
			button.set_active(false);
		}

		var window = screen.get_active_window();

		if (window != null) {
			var button = this.buttons.get(window.get_id().to_string());
			if (button == null) return;
			button.set_active(true);
		}
	}

	/**
	 * Go through the managed buttons list and check if they should be
	 * displayed for the current workspace.
	 */
	private void on_active_workspace_changed(libxfce4windowing.Workspace? previous_workspace) {
		foreach (Button button in this.buttons.get_values()) {
			this.on_app_workspace_changed(button.window);
		}
	}

	/**
	 * Show / Hide button attached to the app depending on if it is in the
	 * current workspace.
	 */
	private void on_app_workspace_changed(libxfce4windowing.Window window) {
		var button = this.buttons.get(window.get_id().to_string());
		if (button == null) return;

		if (window.workspace.get_state() == libxfce4windowing.WorkspaceState.ACTIVE) {
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
