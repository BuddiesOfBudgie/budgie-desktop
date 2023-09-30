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
	public unowned Budgie.PopoverManager popover_manager { get; construct; }
	public bool pinned { get; set; default = false; }

	private Budgie.Windowing.WindowGroup? window_group = null;

	private Icon? icon;
	private ButtonPopover? popover;

	private Gtk.Allocation definite_allocation;
	private int target_icon_size = 0;

	private Budgie.PanelPosition panel_position;

	private bool has_active_window = false;
	private bool needs_attention = false;

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
			popover_manager: popover_manager,
			relief: Gtk.ReliefStyle.NONE
		);

		set_window_group(window_group);
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

	public override bool draw(Cairo.Context ctx) {
		int x = definite_allocation.x;
		int y = definite_allocation.y;
		int width = definite_allocation.width;
		int height = definite_allocation.height;

		List<unowned libxfce4windowing.Window> windows;

		if (window_group != null && window_group.has_windows()) {
			windows = window_group.get_windows();
		} else {
			windows = new List<unowned libxfce4windowing.Window>();
		}

		if (windows.is_empty()) {
			return base.draw(ctx);
		}

		int count = windows.length() > 5 ? 5 : (int) windows.length();
		var styles = get_style_context();

		Gdk.RGBA color;

		if (!styles.lookup_color("budgie_tasklist_indicator_color", out color)) {
			color.parse("#3C6DA6");
		}

		if (get_active()) {
			if (!styles.lookup_color("budgie_tasklist_indicator_color_active", out color)) {
				color.parse("#5294E2");
			}
		} else {
			if (needs_attention) {
				if (!styles.lookup_color("budgie_tasklist_indicator_color_attention", out color)) {
					color.parse("#D84E4E");
				}
			}

			draw_inactive(ctx, color);
			return base.draw(ctx);
		}

		int counter = 0;
		int previous_x = 0;
		int previous_y = 0;
		int spacing = width % count;
		spacing = (spacing == 0) ? 1 : spacing;

		foreach (var window in windows) {
			if (counter == count) break;

			if (window.is_skip_tasklist()) continue;

			// Set the position of our window indicators
			int indicator_x = 0;
			int indicator_y = 0;

			switch (panel_position) {
				case Budgie.PanelPosition.LEFT:
					if (counter == 0) {
						indicator_y = y;
					} else {
						previous_y = indicator_y = previous_y + (height/count);
						indicator_y += spacing;
					}
					indicator_x = x;
					break;
				case Budgie.PanelPosition.RIGHT:
					if (counter == 0) {
						indicator_y = y;
					} else {
						previous_y = indicator_y = previous_y + (height/count);
						indicator_y += spacing;
					}
					indicator_x = x + width;
					break;
				case Budgie.PanelPosition.TOP:
					if (counter == 0) {
						indicator_x = x;
					} else {
						previous_x = indicator_x = previous_x + (width/count);
						indicator_x += spacing;
					}
					indicator_y = y;
					break;
				case Budgie.PanelPosition.BOTTOM:
					if (counter == 0) {
						indicator_x = x;
					} else {
						previous_x = indicator_x = previous_x + (width/count);
						indicator_x += spacing;
					}
					indicator_y = y + height;
					break;
				default:
					break;
			}

			ctx.set_line_width(6);

			if (count > 1 && has_active_window) {
				Gdk.RGBA color2 = color;

				if (!get_style_context().lookup_color("budgie_tasklist_indicator_color_active_window", out color2)) {
					color2.parse("#6BBFFF");
				}

				ctx.set_source_rgba(color2.red, color2.green, color2.blue, 1);
			} else {
				ctx.set_source_rgba(color.red, color.green, color.blue, 1);
			}

			ctx.move_to(indicator_x, indicator_y);

			switch (panel_position) {
				case Budgie.PanelPosition.LEFT:
				case Budgie.PanelPosition.RIGHT:
					int to = 0;

					if (counter == count-1) {
						to = y + height;
					} else {
						to = previous_y + (height / count);
					}

					ctx.line_to(indicator_x, to);
					break;
				default:
					int to = 0;

					if (counter == count-1) {
						to = x + width;
					} else {
						to = previous_x + (width / count);
					}

					ctx.line_to(to, indicator_y);
					break;
			}

			ctx.stroke();
			counter ++;
		}

		return base.draw(ctx);
	}

	public void draw_inactive(Cairo.Context ctx, Gdk.RGBA color) {
		int x = definite_allocation.x;
		int y = definite_allocation.y;
		int width = definite_allocation.width;
		int height = definite_allocation.height;

		List<unowned libxfce4windowing.Window> windows;

		if (window_group != null && window_group.has_windows()) {
			windows = window_group.get_windows();
		} else {
			windows = new List<unowned libxfce4windowing.Window>();
		}

		if (windows.is_empty()) return;

		int count = windows.length() > 5 ? 5 : (int) windows.length();
		int counter = 0;

		foreach (var window in windows) {
			if (counter == count) break;

			if (window.is_skip_pager() || window.is_skip_tasklist()) continue;

			int indicator_x = 0;
			int indicator_y = 0;

			switch (panel_position) {
				case Budgie.PanelPosition.TOP:
					indicator_x = x + (width / 2);
					indicator_x -= ((count * (INDICATOR_SIZE + INACTIVE_INDICATOR_SPACING)) / 2) - INACTIVE_INDICATOR_SPACING;
					indicator_x += (((INDICATOR_SIZE) + INACTIVE_INDICATOR_SPACING) * counter);
					indicator_y = y + (INDICATOR_SIZE / 2);
					break;
				case Budgie.PanelPosition.BOTTOM:
					indicator_x = x + (width / 2);
					indicator_x -= ((count * (INDICATOR_SIZE + INACTIVE_INDICATOR_SPACING)) / 2) - INACTIVE_INDICATOR_SPACING;
					indicator_x += (((INDICATOR_SIZE) + INACTIVE_INDICATOR_SPACING) * counter);
					indicator_y = y + height - (INDICATOR_SIZE / 2);
					break;
				case Budgie.PanelPosition.LEFT:
					indicator_y = x + (height / 2);
					indicator_y -= ((count * (INDICATOR_SIZE + INACTIVE_INDICATOR_SPACING)) / 2) - (INACTIVE_INDICATOR_SPACING * 2);
					indicator_y += (((INDICATOR_SIZE) + INACTIVE_INDICATOR_SPACING) * counter);
					indicator_x = y + (INDICATOR_SIZE / 2);
					break;
				case Budgie.PanelPosition.RIGHT:
					indicator_y = x + (height / 2);
					indicator_y -= ((count * (INDICATOR_SIZE + INACTIVE_INDICATOR_SPACING)) / 2) - INACTIVE_INDICATOR_SPACING;
					indicator_y += ((INDICATOR_SIZE + INACTIVE_INDICATOR_SPACING) * counter);
					indicator_x = y + width - (INDICATOR_SIZE / 2);
					break;
				default:
					break;
			}

			ctx.set_source_rgba(color.red, color.green, color.blue, 1);
			ctx.arc(indicator_x, indicator_y, INDICATOR_SIZE, 0, Math.PI * 2);
			ctx.fill();

			counter++;
		}
	}

	public bool has_window(libxfce4windowing.Window window) {
		return window_group != null && window_group.has_window(window);
	}

	public Icon? get_icon() {
		return icon;
	}

	public void set_active_window(bool active) {
		has_active_window = active;
	}

	public void set_panel_position(Budgie.PanelPosition position) {
		panel_position = position;
	}

	public Budgie.Windowing.WindowGroup? get_window_group() {
		return window_group;
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
