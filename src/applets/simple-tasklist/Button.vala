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

private const int LABEL_MAX_WIDTH = 25;
private const int BUTTON_PADDING = 4;

public class Button : Gtk.ToggleButton {
	private Gtk.Box container;
	private Gtk.Label label;
	private Gtk.Image icon;

	private Gtk.Allocation definite_allocation;

	public Budgie.Abomination.RunningApp? app { get; private set; }

	public Button(Budgie.Abomination.RunningApp app) {
		this.container = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
		this.add(this.container);

		this.icon = new Gtk.Image();
		this.icon.get_style_context().add_class("icon");
		this.icon.set_margin_start(BUTTON_PADDING);
		this.icon.set_margin_end(BUTTON_PADDING);
		this.icon.set_pixel_size(16); // TODO: We should be able to handle panel resize and icon only mode

		this.label = new Gtk.Label(null);
		this.label.set_ellipsize(Pango.EllipsizeMode.END);
		this.label.set_max_width_chars(LABEL_MAX_WIDTH);
		this.label.set_margin_start(BUTTON_PADDING);
		this.label.set_margin_end(BUTTON_PADDING);

		this.container.add(this.icon);
		this.container.add(this.label);

		this.app = app;

		this.on_app_name_changed();
		this.on_app_icon_changed();

		this.show_all(); // Only show after setting the name

		// SIGNALS
		this.size_allocate.connect(this.on_size_allocate);
		this.app.renamed_app.connect(this.on_app_name_changed);
		this.app.icon_changed.connect(this.on_app_icon_changed);
		this.app.app_info_changed.connect(() => {
			warning("App Info changed for %s", this.app.name);

			this.on_app_name_changed();
			this.on_app_icon_changed();
		});

		// set_size_request is for MINIMUM size. How to set maximum size?
		// Also how to make it so that the parent scale this maximum size? i.e. that button takes the most it can when opened if it has room?

		// TODO: How to set consistent default width w/out relying on that? If we set that we pretty much don't have the widget compression mechanism
		//  this.set_size_request(232, 36); // FIXME: Need to be done better than that

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

	protected override bool button_release_event(Gdk.EventButton event) {
		if (event.button == 3) { // Right click
			//  TODO: show popover
			return Gdk.EVENT_STOP;
		}

		if (event.button == 2) { // Middle click
			this.app.close();
			return Gdk.EVENT_STOP;
		}

		if (event.button == 1) { // Left click
			this.app.toggle();

			// Don't return on purpose
		}

		return base.button_release_event(event);
	}

	private void on_size_allocate(Gtk.Allocation allocation) {
		if (this.definite_allocation == allocation) {
			return;
		}

		this.definite_allocation = allocation;

		// TODO: Determine icon size

		base.size_allocate(definite_allocation);
	}

	private void on_app_name_changed() {
		var name = this.app.name;
		while (name.char_count() < LABEL_MAX_WIDTH - 1) { // Dirty way to ensure that button occupy it's max size when created
			name = name.concat("\u2800");
		} // FIXME: Find a better way, this is ugly when reaching size where we compress the button

		this.label.set_label(name);
		this.set_tooltip_text(name);
	}

	private void on_app_icon_changed() {
		Gdk.Pixbuf icon_pixbuf = this.app.get_icon();

		icon_pixbuf = icon_pixbuf.scale_simple(16, 16, Gdk.InterpType.BILINEAR);

		this.icon.set_from_pixbuf(icon_pixbuf);
	}
}
