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
using Pango;

private const int BUTTON_MAX_WIDTH = 232;
private const int BUTTON_MIN_WIDTH = 164;
private const int LABEL_MAX_WIDTH = 24;
private const int BUTTON_PADDING = 8;

private const int DEFAULT_ICON_SIZE = 32;
private const int TARGET_ICON_PADDING = 18;
private const double TARGET_ICON_SCALE = 2.0 / 3.0;
private const int FORMULA_SWAP_POINT = TARGET_ICON_PADDING * 3;

public class TasklistButton : ToggleButton {
	private new Label label;
	private Image icon;
	private GLib.Settings settings;
	private ButtonPopover popover;

	private Allocation definite_allocation;

	public Budgie.PopoverManager popover_manager { get; construct; }
	public libxfce4windowing.Window window { get; construct; }

	private int64 last_scroll_time = 0;
	private int target_icon_size = 0;

	public TasklistButton(libxfce4windowing.Window window, Budgie.PopoverManager popover_manager, GLib.Settings settings) {
		Object(window: window, popover_manager: popover_manager);

		this.settings = settings;
		settings.bind("show-icons", this.icon, "visible", SettingsBindFlags.GET);
		settings.bind("show-labels", this.label, "visible", SettingsBindFlags.GET);

		popover = new ButtonPopover(this, window);
		popover_manager.register_popover(this, popover);
	}

	construct {
		get_style_context().add_class("launcher");
		add_events(Gdk.EventMask.SCROLL_MASK);

		var container = new Box(Orientation.HORIZONTAL, 0);
		add(container);

		this.icon = new Image() {
			margin_start = BUTTON_PADDING,
			margin_end = BUTTON_PADDING,
		};
		this.icon.get_style_context().add_class("icon");

		this.label = new Label(null) {
			halign = CENTER,
			valign = CENTER,
			max_width_chars = LABEL_MAX_WIDTH,
			ellipsize = EllipsizeMode.END,
			hexpand = true,
		};

		container.pack_start(this.icon, false);
		container.pack_start(this.label);

		on_window_name_changed();
		on_window_icon_changed();

		this.show_all(); // Only show after setting the name

		// SIGNALS
		size_allocate.connect(on_size_allocate);
		window.name_changed.connect(on_window_name_changed);
		window.icon_changed.connect(on_window_icon_changed);

		// set_size_request is for MINIMUM size. How to set maximum size?
		// Also how to make it so that the parent scale this maximum size? i.e. that button takes the most it can when opened if it has room?

		// TODO: How to set consistent default width w/out relying on that? If we set that we pretty much don't have the widget compression mechanism
		// this.set_size_request(BUTTON_MIN_WIDTH, -1);

		// TODO: size request. We should respect parent max width and max height like a good citizen and properly set our size request
	}

	public void gracefully_die() {
		if (!this.get_settings().gtk_enable_animations) {
			this.hide();
			this.destroy();
			return;
		}

		//  TODO: slick animation from ButtonWrapper
		this.hide();
		this.destroy();
	}

	protected override bool button_release_event(EventButton event) {
		var time = event.time;

		if (event.button == BUTTON_SECONDARY) {
			popover_manager.show_popover(this);
			return Gdk.EVENT_STOP;
		}

		if (event.button == BUTTON_MIDDLE) {
			try {
				window.close(time);
			} catch (GLib.Error e) {
				warning("Unable to close window '%s': %s", window.get_name(), e.message);
			}
			return Gdk.EVENT_STOP;
		}

		if (event.button == BUTTON_PRIMARY) {
			if (window.state == libxfce4windowing.WindowState.ACTIVE) {
				try {
					window.set_minimized(true);
				} catch (GLib.Error e) {
					warning("Unable to minimize window '%s': %s", window.get_name(), e.message);
				}
			} else {
				try {
					window.activate(null, time);
				} catch (GLib.Error e) {
					warning("Unable to activate window '%s': %s", window.get_name(), e.message);
				}
			}

			// Don't return on purpose
		}

		return base.button_release_event(event);
	}

	public override bool scroll_event(Gdk.EventScroll event) {
		if (get_monotonic_time() - last_scroll_time < 300000) {
			return Gdk.EVENT_STOP;
		}

		switch (event.direction) {
			case ScrollDirection.UP:
				try {
					window.activate(null, event.time);
				} catch (GLib.Error e) {
					warning("Unable to activate window '%s': %s", window.get_name(), e.message);
				}
				break;
			case ScrollDirection.DOWN:
				try {
					window.set_minimized(true);
				} catch (GLib.Error e) {
					warning("Unable to minimize window '%s': %s", window.get_name(), e.message);
				}
				break;
			default:
				break;
		}

		last_scroll_time = get_monotonic_time();
		return Gdk.EVENT_STOP;
	}

	private void on_size_allocate(Allocation allocation) {
		if (this.definite_allocation == allocation) {
			return;
		}

		this.definite_allocation = allocation;

		// Determine icon size
		int max = (int) Math.fmin(allocation.width, allocation.height);

		if (max > FORMULA_SWAP_POINT) {
			target_icon_size = max - TARGET_ICON_PADDING;
		} else {
			target_icon_size = (int) Math.round(TARGET_ICON_SCALE * max);
		}

		on_window_icon_changed();
		base.size_allocate(definite_allocation);
	}

	private void on_window_name_changed() {
		var name = window.get_name();
		label.set_label(name);
		set_tooltip_text(name);
	}

	private void on_window_icon_changed() {
		var size = target_icon_size == 0 ? DEFAULT_ICON_SIZE : target_icon_size;
		unowned var pixbuf = window.get_icon(size, get_scale_factor());
		icon.set_from_pixbuf(pixbuf);
	}
}
