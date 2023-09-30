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

public class IconButton : Gtk.ToggleButton {
	private const double DEFAULT_OPACITY = 0.1;
	private const int INDICATOR_SIZE = 2;
	private const int INDICATOR_SPACING = 1;
	private const int INACTIVE_INDICATOR_SPACING = 2;

	private const int DEFAULT_ICON_SIZE = 32;
	private const int TARGET_ICON_PADDING = 18;
	private const double TARGET_ICON_SCALE = 2.0 / 3.0;
	private const int FORMULA_SWAP_POINT = TARGET_ICON_PADDING * 3;

	public Budgie.Application app { get; construct; }
	public Budgie.Windowing.WindowGroup? window_group { get; construct set; default = null; }
	public unowned Budgie.PopoverManager popover_manager { get; construct; }

	private Icon? icon;
	private ButtonPopover? popover;

	private Gtk.Allocation definite_allocation;
	private int target_icon_size = 0;

	private bool pinned = false;

	public IconButton(Budgie.Application app, Budgie.PopoverManager popover_manager) {
		Object(
			app: app,
			popover_manager: popover_manager,
			relief: Gtk.ReliefStyle.NONE
		);
	}

	public IconButton.with_group(Budgie.Application app, Budgie.Windowing.WindowGroup window_group, Budgie.PopoverManager popover_manager) {
		Object(
			app: app,
			window_group: window_group,
			popover_manager: popover_manager,
			relief: Gtk.ReliefStyle.NONE
		);
	}

	construct {
		get_style_context().remove_class(Gtk.STYLE_CLASS_BUTTON);
		get_style_context().remove_class("toggle");
		get_style_context().add_class("launcher");

		definite_allocation.width = 0;
		definite_allocation.height = 0;

		icon = new Icon();

		icon.get_style_context().add_class("icon");

		popover = new ButtonPopover(this, app, window_group);

		// TODO: connect signals

		popover_manager.register_popover(this, popover);

		add(icon);

		size_allocate.connect(on_size_allocate);
	}

	private void on_size_allocate(Gtk.Allocation allocation) {
		if (definite_allocation != allocation) {
			int max = (int) Math.fmin(allocation.width, allocation.height);

			if (max > FORMULA_SWAP_POINT) {
				target_icon_size = max - TARGET_ICON_PADDING;
			} else {
				target_icon_size = (int) Math.round(TARGET_ICON_SCALE * max);
			}

			update_icon();
		}

		definite_allocation = allocation;
		base.size_allocate(definite_allocation);

		// If this button has active windows, set their button geometry
		if (window_group != null && window_group.has_windows()) {
			foreach (var win in window_group.get_windows()) {
				try {
					set_window_button_geometry(win);
				} catch (Error e) {
					warning("Unable to set button geometry for window %s: %s", win.get_name(), e.message);
				}
			}
		}
	}

	/**
	 * Sets the button geometry for a window.
	 *
	 * What this means is that when a window is minimized, it will minimize to
	 * the icon button's location on the screen.
	 *
	 * Throws: if the button geometry could not be set
	 */
	private void set_window_button_geometry(libxfce4windowing.Window window) throws Error {
		int x, y;
		var toplevel = get_toplevel();

		if (toplevel == null || toplevel.get_window() == null) return;

		translate_coordinates(toplevel, 0, 0, out x, out y);
		toplevel.get_window().get_root_coords(x, y, out x, out y);

		Gdk.Rectangle rect = {
			x,
			y,
			definite_allocation.width,
			definite_allocation.height
		};

		window.set_button_geometry(toplevel.get_window(), rect);
	}

	public Icon? get_icon() {
		return icon;
	}

	public void set_window_group(Budgie.Windowing.WindowGroup? window_group) {
		this.window_group = window_group;

		if (window_group == null) return;

		window_group.app_icon_changed.connect_after(() => {
			update_icon();
		});

		window_group.window_added.connect((window) => {
			var id = window.get_id();
			var name = window.get_name() ?? "Loading...";

			popover.add_window(window);

			update();
		});

		window_group.window_removed.connect(() => {
			update();
		});
	}

	public void update() {
		if (window_group != null && window_group.has_windows()) {
			get_style_context().add_class("running");
		} else {
			get_style_context().remove_class("running");

			if (pinned) {
				window_group = null;
			} else {
				return;
			}
		}

		update_icon();
		// queue_redraw();
	}

	public void update_icon() {
		if (window_group != null && window_group.has_windows()) {
			icon.waiting = false;
		}

		unowned GLib.Icon? app_icon = app.icon;
		Gdk.Pixbuf? pixbuf_icon = null;

		if (window_group != null) {
			var size = target_icon_size == 0 ? DEFAULT_ICON_SIZE : target_icon_size;
			pixbuf_icon = window_group.get_icon(size, 1);
		}

		if (app_icon != null) {
			icon.set_from_gicon(app_icon, Gtk.IconSize.INVALID);
		} else if (pixbuf_icon != null) {
			icon.set_from_pixbuf(pixbuf_icon);
		} else {
			icon.set_from_icon_name("image-missing", Gtk.IconSize.INVALID);
		}

		if (target_icon_size > 0) {
			icon.pixel_size = target_icon_size;
		} else {
			// prevents apps making the panel massive when the icon initially gets added
			icon.pixel_size = DEFAULT_ICON_SIZE;
		}
	}
}
