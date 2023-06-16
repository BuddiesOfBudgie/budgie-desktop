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

/** Valid targets for drag-n-dropping tasklist buttons. */
public const Gtk.TargetEntry[] SOURCE_TARGETS  = {
	{ "application/x-wnck-window-id", 0, 0 }
};

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
	 * Handles the drag_data_get signal for a tasklist button.
	 *
	 * This sets the button's window XID as the drag data.
	 */
	private void button_drag_data_get(Widget widget, DragContext context, SelectionData data, uint info, uint time) {
		var button = widget as Button;
		var xid = button.window.get_id();
		data.set(data.get_target(), 8, (uint8[]) xid);
	}

	/**
	 * Handles the drag_begin signal for a tasklist button.
	 *
	 * This sets the icon at the cursor when the button is dragged.
	 */
	private void button_drag_begin(Widget widget, DragContext context) {
		var button = widget as Button;
		int size = 0;

		if (!Gtk.icon_size_lookup(IconSize.DND, out size, null)) {
			size = 32;
		}

		var scale_factor = button.get_scale_factor();
		var pixbuf = button.window.get_icon(size, scale_factor);

		if (pixbuf == null) return;

		var surface = Gdk.cairo_surface_create_from_pixbuf(pixbuf, scale_factor, null);
		Gtk.drag_set_icon_surface(context, surface);
	}

	/**
	 * Handles when a drag item is dropped on a tasklist button.
	 *
	 * If the source widget is another tasklist button, reorder the widgets in
	 * our container so that the dropped button is put in the place of this
	 * button.
	 */
	private void button_drag_data_received(Widget widget, DragContext context, int x, int y, SelectionData data, uint info, uint time) {
		var button = widget as Button;
		var source = Gtk.drag_get_source_widget(context);
		if (!(source is Button)) return; // Make sure the source is a tasklist button

		List<weak Widget> children = container.get_children(); // Get the list of child buttons
		unowned var self = children.find(button); // Find this button in the list
		var position = children.position(self); // Get our position
		container.reorder_child(source, position); // Put the source button in our position
	}

	/**
	 * Handles when the cursor leaves the space of a button during a drag.
	 */
	private void button_drag_leave(Widget widget, DragContext context, uint time) {
		Gtk.drag_unhighlight(widget);
	}

	/**
	 * Handles when a widget is dragged over a tasklist button.
	 */
	private bool button_drag_motion(Widget widget, DragContext context, int x, int y, uint time) {
		var button = widget as Button;
		var source = Gtk.drag_get_source_widget(context);

		// Only respond to dragging tasklist buttons
		if (source == null || !(source is Button)) {
			Gdk.drag_status(context, 0, time); // Keep emitting the signal
			return true; // Make sure we receive the Leave signal
		}

		// Check if this button is a valid drop target
		var ret = Gtk.drag_dest_find_target(button, context, null);
		if (ret != Atom.NONE) {
			Gtk.drag_highlight(button); // Highlight this button
			Gdk.drag_status(context, DragAction.MOVE, time); // Drag-n-drop to reorder buttons
			return true;
		}

		return false; // Send drag-motion to other widgets
	}

	/**
	 * Create a button for the newly opened app and add it to our tracking map.
	 */
	private void on_app_opened(libxfce4windowing.Window window) {
		if (window.is_skip_tasklist()) return;
		if (buttons.contains(window.get_id().to_string().to_string())) return;

		window.workspace_changed.connect(() => this.on_app_workspace_changed(window));

		var button = new Button(window);

		Gtk.drag_source_set(button, ModifierType.BUTTON1_MASK, SOURCE_TARGETS, DragAction.MOVE);
		Gtk.drag_dest_set(button, (DestDefaults.DROP|DestDefaults.HIGHLIGHT), SOURCE_TARGETS, DragAction.MOVE);

		button.drag_data_get.connect(button_drag_data_get);
		button.drag_begin.connect(button_drag_begin);
		button.drag_data_received.connect(button_drag_data_received);
		button.drag_motion.connect(button_drag_motion);
		button.drag_leave.connect(button_drag_leave);

		this.container.pack_start(button);

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
