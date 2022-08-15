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
 * Wraps a `Gtk.Button` so we can have more control over the menu
 * item widgets and layout.
 */
public class MenuItem : Gtk.Button {
	private Gtk.Box? menu_item = null;
	private Gtk.Image? button_image = null;
	private Gtk.Label? button_label = null;

	private string? _image_source = null;
	public string? image_source {
		get { return _image_source; }
		set {
			this._image_source = image_source;
			this.set_image(image_source);
		}
	}

	private string? _label_text = null;
	public string? label_text {
		get { return _label_text; }
		set {
			this.set_label(label_text);
		}
	}

	public MenuItem(string label_text, string image_source) {
		Object(can_focus: true);

		this.set_image(image_source);
		this.set_label(label_text);

		this.menu_item = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
		this.menu_item.pack_start(this.button_image, false, false, 6);
		this.menu_item.pack_end(this.button_label, true, true, 0);

		this.add(this.menu_item);
	}

	construct {
		this.get_style_context().add_class("flat");
		this.get_style_context().add_class("menuitem");

		this.show_all();
	}

	/**
	 * Set the image for this item.
	 */
	public new void set_image(string source) {
		if (this.button_image == null) {
			this.button_image = new Gtk.Image();
		}

		this.button_image.set_from_icon_name(source, Gtk.IconSize.BUTTON); // 16px
	}

	/**
	 * Sets the label for this item.
	 */
	public new void set_label(string text) {
		this._label_text = text.dup();

		if (this.button_label == null) {
			this.button_label = new Gtk.Label(this._label_text) {
				halign = Gtk.Align.START
			};
		} else {
			this.button_label.set_text(this._label_text);
		}
	}
}
