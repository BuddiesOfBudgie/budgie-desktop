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

public class Button : Gtk.ToggleButton {
	private Gtk.Box container;
	private Gtk.Label label;

	public Budgie.Abomination.RunningApp? app { get; private set; }

	public Button(Budgie.Abomination.RunningApp app) {
		this.container = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
		this.add(this.container);

		this.label = new Gtk.Label(null);
		this.label.set_ellipsize(Pango.EllipsizeMode.END);
		this.label.set_max_width_chars(LABEL_MAX_WIDTH);

		this.container.add(this.label);

		this.app = app;

		this.on_app_name_changed();
		this.on_app_icon_changed();

		this.show_all(); // Only show after setting the name

		this.app.renamed_app.connect(this.on_app_name_changed);
		this.app.icon_changed.connect(this.on_app_icon_changed);

		this.set_size_request(232, 36); // FIXME: Need to be done better than that

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

	public override bool button_release_event(Gdk.EventButton event) {
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

	private void on_app_name_changed() {
		var name = this.app.name;
		this.label.set_label(name);
		this.set_tooltip_text(name);
	}

	private void on_app_icon_changed() {

	}
}
