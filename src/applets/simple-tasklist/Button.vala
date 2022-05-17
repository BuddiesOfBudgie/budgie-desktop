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

public class Button : Gtk.ToggleButton {
	private Gtk.Box container;
	private Gtk.Label label;

	private Budgie.Abomination.RunningApp? app;

	public Button(Budgie.Abomination.RunningApp app) {
		this.app = app;

		this.container = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
		this.add(this.container);

		this.label = new Gtk.Label(null);
		this.label.set_ellipsize(Pango.EllipsizeMode.END);
		this.label.set_max_width_chars(25); // TODO: make it a const

		this.container.add(this.label);

		this.on_app_name_changed();
		this.on_app_icon_changed();

		this.show_all();

		this.app.renamed_app.connect(() => this.on_app_name_changed());
		this.app.icon_changed.connect(() => this.on_app_icon_changed());

		// TODO: size request
	}

	public void gracefully_die() {
		// TODO: disconnect signal handlers

		//  if (!this.get_settings().gtk_enable_animations) {
			this.hide();
			this.destroy();
		//  }

		//  TODO: slick animation from ButtonWrapper
	}

	public override bool button_release_event(Gdk.EventButton event) {
		if (event.button == 3) { // Right click
			//  TODO: show popover
			return Gdk.EVENT_STOP;
		}

		if (event.button == 2) { // Middle click
			// TODO: Close app
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
