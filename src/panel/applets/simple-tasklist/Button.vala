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
private const int BUTTON_PADDING = 4;

public class Button : ToggleButton {
	private Label label;
	private Image icon;

	private Allocation definite_allocation;

	public libxfce4windowing.Window window{ get; construct; }

	public Button(libxfce4windowing.Window window) {
		Object(window: window);
	}

	construct {
		get_style_context().add_class("launcher");

		var container = new Box(Orientation.HORIZONTAL, 0);
		add(container);

		this.icon = new Image() {
			margin_start = BUTTON_PADDING,
			margin_end = BUTTON_PADDING,
			pixel_size = 16, // TODO: We should be able to handle panel resize and icon only mode
		};
		this.icon.get_style_context().add_class("icon");

		this.label = new Label(null) {
			halign = START,
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

		if (event.button == 3) { // Right click
			//  TODO: show popover
			return Gdk.EVENT_STOP;
		}

		if (event.button == 2) { // Middle click
			try {
				window.close(time);
			} catch (GLib.Error e) {
				warning("Unable to close window '%s': %s", window.get_name(), e.message);
			}
			return Gdk.EVENT_STOP;
		}

		if (event.button == 1) { // Left click
			if (window.state == libxfce4windowing.WindowState.ACTIVE) {
				try {
					window.set_minimized(true);
				} catch (GLib.Error e) {
					warning("Unable to minimize window '%s': %s", window.get_name(), e.message);
				}
			} else {
				try {
					window.activate(time);
				} catch (GLib.Error e) {
					warning("Unable to activate window '%s': %s", window.get_name(), e.message);
				}
			}

			// Don't return on purpose
		}

		return base.button_release_event(event);
	}

	private void on_size_allocate(Allocation allocation) {
		if (this.definite_allocation == allocation) {
			return;
		}

		this.definite_allocation = allocation;

		// TODO: Determine icon size

		base.size_allocate(definite_allocation);
	}

	private void on_window_name_changed() {
		var name = window.get_name();
		label.set_label(name);
		set_tooltip_text(name);
	}

	private void on_window_icon_changed() {
		Pixbuf icon_pixbuf = window.get_icon(24, 1); // TODO: Icon sizes
		icon.set_from_pixbuf(icon_pixbuf);
	}
}
