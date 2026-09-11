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

/**
 * Factory widget to represent a category
 */
public class CategoryButton : Gtk.RadioButton {
	public Budgie.Category? category { public get; construct; default = null; }

	/**
	 * Whether this button selects the favorited applications rather than
	 * a category of the application index.
	 */
	public bool favorites { public get; construct; default = false; }

	public CategoryButton(Budgie.Category? category) {
		Object(category: category);
	}

	public CategoryButton.for_favorites() {
		Object(category: null, favorites: true);
	}

	construct {
		var layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);

		var label = new Gtk.Label(null) {
			halign = Gtk.Align.START,
			valign = Gtk.Align.CENTER,
			margin_start = 10,
			margin_end = 15
		};

		if (favorites) {
			label.label = _("Favorites");
		} else if (category == null) {
			label.label = _("All");
		} else {
			label.label = category.name;
		}

		layout.pack_start(label);

		get_style_context().add_class("flat");
		get_style_context().add_class("category-button");

		if (favorites) {
			get_style_context().add_class("favorites-category-button");
		}

		set_property("draw-indicator", false); // Makes us look like a normal button

		add(layout);

		// no_show_all stops show_all() from reaching the children, so show them here
		layout.show_all();
	}
}
