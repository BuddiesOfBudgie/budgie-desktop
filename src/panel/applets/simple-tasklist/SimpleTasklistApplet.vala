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

public const int MAX_BUTTON_LENGTH = 200;
public const int MIN_BUTTON_LENGTH = MAX_BUTTON_LENGTH / 4;
public const int ARROW_BUTTON_SIZE = 20;

public class SimpleTasklistPlugin : Budgie.Plugin, Peas.ExtensionBase {
	public Budgie.Applet get_panel_widget(string uuid) {
		return new SimpleTasklistApplet();
	}
}

public class SimpleTasklistApplet : Budgie.Applet {
	public string uuid { public set; public get; }

	private ScrolledWindow scroller;
	private Box container;
	private Gtk.Button back_button;
	private Gtk.Button forward_button;
	private Gtk.Button arrow_button;

	private Budgie.Abomination.Abomination? abomination;
	private HashTable<string, Button> buttons;

	private int num_windows;

	construct {
		//  this.hexpand = true;

		this.buttons = new HashTable<string, Button>(str_hash, str_equal);

		this.scroller = new ScrolledWindow(null, null) {
			overlay_scrolling = true,
			propagate_natural_height = true,
			propagate_natural_width = true,
			shadow_type = ShadowType.NONE,
			hscrollbar_policy = PolicyType.EXTERNAL,
			vscrollbar_policy = PolicyType.NEVER,
		};

		this.container = new Box(Orientation.HORIZONTAL, 4) {
			homogeneous = true,
		};

		//  this.scroller.add(this.container);

		back_button = new Gtk.Button.from_icon_name("go-previous-symbolic", IconSize.BUTTON) {
			sensitive = false, // The scroller starts at the start edge, so mark as non-sensitive
		};
		back_button.get_style_context().add_class("tasklist-scroll-button");

		back_button.clicked.connect(() => {
			scroller.scroll_child(ScrollType.STEP_BACKWARD, true);
		});

		forward_button = new Gtk.Button.from_icon_name("go-next-symbolic", IconSize.BUTTON);
		forward_button.get_style_context().add_class("tasklist-scroll-button");

		forward_button.clicked.connect(() => {
			scroller.scroll_child(ScrollType.STEP_FORWARD, true);
		});

		scroller.edge_reached.connect(on_edge_reached);

		scroller.scroll_child.connect(on_scroll_child);

		var grid = new Grid() {
			row_homogeneous = true,
		};

		//  grid.attach(back_button, 0, 0);
		//  grid.attach(scroller, 1, 0);
		//  grid.attach(forward_button, 2, 0);

		//  this.add(grid);

		arrow_button = new Gtk.Button.from_icon_name("go-next-symbolic", IconSize.BUTTON);
		arrow_button.get_style_context().add_class("tasklist-arrow-button");

		add(container);

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
		Orientation orientation = Orientation.HORIZONTAL;
		if (position == Budgie.PanelPosition.LEFT || position == Budgie.PanelPosition.RIGHT) {
			orientation = Orientation.VERTICAL;
		}

		this.container.set_orientation(orientation);

		if (orientation == Orientation.HORIZONTAL) {
			this.scroller.hscrollbar_policy = PolicyType.EXTERNAL;
			this.scroller.vscrollbar_policy = PolicyType.NEVER;
		} else {
			this.scroller.hscrollbar_policy = PolicyType.NEVER;
			this.scroller.vscrollbar_policy = PolicyType.EXTERNAL;
		}
	}

	public override void get_preferred_width(out int minimum_width, out int natural_width) {
		int length;
		int num_windows = 0;

		// Count the number of open windows
		foreach (var button in buttons.get_values()) {
			if (!button.is_visible()) continue;

			num_windows++;
		}

		this.num_windows = num_windows;

		// Calculate our current length
		if (num_windows == 0) {
			length = 0;
		} else {
			length = num_windows * MAX_BUTTON_LENGTH;
		}

		// Set our out values
		minimum_width = (num_windows == 0) ? 0 : ARROW_BUTTON_SIZE;
		natural_width = length;
	}

	private void size_layout(out Allocation allocation, out int num_cols, out int arrow_position) {
		int cols = this.num_windows;
		int min_button_length, max_button_length;
		int num_buttons = 0;
		int target_num_buttons;

		min_button_length = MIN_BUTTON_LENGTH;

		arrow_position = -1; // Hide the arrow button

		foreach (var button in buttons.get_values()) {
			// TODO: Set the child type to Window instead of OverflowMenu
		}

		if (min_button_length * cols < allocation.width) {
			// All of the windows seem to fit
			num_cols = cols;
		} else {
			max_button_length = MAX_BUTTON_LENGTH;

			num_buttons = this.num_windows;
			target_num_buttons = (allocation.width - ARROW_BUTTON_SIZE) / min_button_length;

			if (num_buttons > target_num_buttons) {
				debug("Putting %d window buttons in the overflow menu", num_buttons - target_num_buttons);

				// TODO: Add buttons to overflow menu

				/* Try to position the arrow widget at the end of the allocation area. *
				 * If that's impossible (because buttons cannot be expanded enough),   *
				 * position it just after the buttons.                                 */
				arrow_position = int.min(allocation.width - ARROW_BUTTON_SIZE, target_num_buttons * max_button_length);
			}

			cols = num_buttons;
			num_cols = cols;
		}
	}

	public override void size_allocate(Allocation allocation) {
		// TODO: Check for arrow button visibility?

		int cols = 0;
		Allocation area = allocation;
		Allocation child_allocation = new Allocation();
		int w = 0, x = 0, y = 0, h = 0;
		int area_x, area_width;
		int arrow_position;
		Requisition child_req;

		set_allocation(allocation);

		size_layout(out area, out cols, out arrow_position);

		// Allocate the arrow button for the overflow menu
		child_allocation.width = ARROW_BUTTON_SIZE;
		child_allocation.height = area.height;

		if (arrow_position != -1) {
			child_allocation.x = area.x;
			child_allocation.y = area.y;

			child_allocation.x += arrow_position;

			area.width = arrow_position;
		} else {
			child_allocation.x = -9999;
			child_allocation.y = -9999;
		}

		arrow_button.size_allocate(child_allocation);

		area_x = area.x;
		area_width = area.width;
		h = area.height;

		// Allocate all the children
		foreach (var button in buttons.get_values()) {
			// Skip hidden buttons
			if (!button.is_visible()) continue;

			// if (button.type == WINDOW) {
			x = area_x;
			y = area.y;

			if (cols < 1) {
				cols = 1;
			}

			message ("arrow_position = %d", arrow_position);
			message ("area_width = %d", area_width);
			message ("cols = %d", cols);

			w = area_width / cols--;

			if (w > MAX_BUTTON_LENGTH) {
				w = MAX_BUTTON_LENGTH;
			}

			area_width -= w;
			area_x += w;

			message("w = %d", w);

			// Set the child allocation values
			child_allocation.x = x;
			child_allocation.y = y;
			child_allocation.width = int.max(w, 1);
			child_allocation.height = h;

			y += h;

			// TODO: Handle RTL
			// }

			// TODO: Handle overflow buttons

			button.size_allocate(child_allocation);
		}
	}

	/**
	 * Create a button for the newly opened app and add it to our tracking map.
	 */
	private void on_app_opened(Budgie.Abomination.RunningApp app) {
		if (this.buttons.contains(app.id.to_string())) return;

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
		if (button == null) return;

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
			if (button == null) return;
			button.set_active(false);
		}
		if (current_app != null) {
			var button = this.buttons.get(current_app.id.to_string());
			if (button == null) return;
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
		if (button == null) return;

		if (app.workspace.get_number() == this.abomination.get_active_workspace().get_number()) {
			button.show();
			button.set_no_show_all(false);
		} else {
			button.hide();
			button.set_no_show_all(true); // make sure we don't randomly show buttons not belonging to the current workspace
		}
	}

	private void on_edge_reached(PositionType position) {
		switch (position) {
			case PositionType.LEFT:
				back_button.sensitive = false;
				break;
			case PositionType.RIGHT:
				forward_button.sensitive = false;
				break;
			default:
				break;
		}
	}

	private bool on_scroll_child(ScrollType type, bool horizontal) {
		if (!horizontal) return true;

		switch (type) {
			case ScrollType.PAGE_BACKWARD:
			case ScrollType.PAGE_LEFT:
			case ScrollType.PAGE_UP:
			case ScrollType.STEP_BACKWARD:
			case ScrollType.STEP_LEFT:
			case ScrollType.STEP_UP:
			case ScrollType.START:
				forward_button.sensitive = true;
				break;
			case ScrollType.PAGE_FORWARD:
			case ScrollType.PAGE_RIGHT:
			case ScrollType.PAGE_DOWN:
			case ScrollType.STEP_FORWARD:
			case ScrollType.STEP_RIGHT:
			case ScrollType.STEP_DOWN:
			case ScrollType.END:
				back_button.sensitive = true;
				break;
			default:
				break;
		}

		return true;
	}
}

[ModuleInit]
public void peas_register_types(TypeModule module) {
	// boilerplate - all modules need this
	var objmodule = module as Peas.ObjectModule;
	objmodule.register_extension_type(typeof(Budgie.Plugin), typeof(SimpleTasklistPlugin));
}
