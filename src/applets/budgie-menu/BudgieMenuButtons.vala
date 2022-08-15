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

/**
 * Factory widget to represent a category
 */
public class CategoryButton : Gtk.RadioButton {
	public new Budgie.Category? category { public get ; protected set; }

	public CategoryButton(Budgie.Category? category) {
		this.category = category;

		string name = null;
		if (category != null) {
			name = category.name;
		} else {
			name = _("All");
		}

		Gtk.Label label = new Gtk.Label(name) {
			halign = Gtk.Align.START,
			valign = Gtk.Align.CENTER,
			margin_start = 10,
			margin_end = 15
		};

		var layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
		layout.pack_start(label, true, true, 0);
		add(layout);

		get_style_context().add_class("flat");
		get_style_context().add_class("category-button");
		// Makes us look like a normal button :)
		set_property("draw-indicator", false);
		set_can_focus(false);
	}
}

/**
 * Factory widget to represent a menu item
 */
public class MenuButton : Gtk.Button {
	public Budgie.Application app { get; private set; }
	public Budgie.Category category { get; private set; }

	public MenuButton(Budgie.Application app, Budgie.Category category, int icon_size) {
		this.app = app;
		this.category = category;

		var img = new Gtk.Image.from_gicon(app.icon, Gtk.IconSize.INVALID) {
			pixel_size = icon_size,
			margin_end = 7
		};

		var lab = new Gtk.Label(app.name) {
			halign = Gtk.Align.START,
			valign = Gtk.Align.CENTER
		};

		const Gtk.TargetEntry[] drag_targets = { {"text/uri-list", 0, 0 }, {"application/x-desktop", 0, 0 } };
		Gtk.drag_source_set(this, Gdk.ModifierType.BUTTON1_MASK, drag_targets, Gdk.DragAction.COPY);
		base.drag_begin.connect(this.drag_begin);
		base.drag_end.connect(this.drag_end);
		base.drag_data_get.connect(this.drag_data_get);

		set_can_focus(false);

		var layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
		layout.pack_start(img, false, false, 0);
		layout.pack_start(lab, true, true, 0);
		add(layout);

		set_tooltip_text(app.description);

		get_style_context().add_class("flat");
	}

	/**
	 * Check if this item is for a control center panel.
	 */
	public bool is_control_center_panel() {
		var control_center = "budgie-control-center";
		return (
			control_center in app.exec &&
			app.exec.length != control_center.length
		);
	}

	private bool hide_toplevel() {
		this.get_toplevel().hide();
		return false;
	}

	private new void drag_begin(Gdk.DragContext context) {
		Gtk.drag_set_icon_gicon(context, this.app.icon, 0, 0);
	}

	private new void drag_end(Gdk.DragContext context) {
		Idle.add(this.hide_toplevel);
	}

	private new void drag_data_get(Gdk.DragContext context, Gtk.SelectionData data, uint info, uint timestamp) {
		try {
			string[] urls = { Filename.to_uri(this.app.desktop_path) };
			data.set_uris(urls);
		} catch (Error e) {
			warning("Failed to set copy data: %s", e.message);
		}
	}
}
