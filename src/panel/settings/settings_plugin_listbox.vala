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

namespace Budgie {
	/**
	* SettingsPluginListboxItem is used to represent a Budgie plugin in the listbox
	*/
	public class SettingsPluginListboxItem : Gtk.Box {
		public string instance_uuid;
		private Gtk.Image image;
		private Gtk.Label label;

		/**
		* Construct a new AppletItem for the given applet
		*/
		public SettingsPluginListboxItem(string uuid, string name, string icon, bool builtin) {
			Object(orientation: Gtk.Orientation.HORIZONTAL);

			get_style_context().add_class("plugin-item");
			instance_uuid = uuid;

			margin_top = 2;
			margin_bottom = 2;

			image = new Gtk.Image.from_icon_name(icon, Gtk.IconSize.MENU) {
				margin_start = 8,
				margin_end = 12,
				pixel_size = 24,
			};

			var label_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);

			label = new Gtk.Label(null) {
				valign = Gtk.Align.CENTER,
				xalign = 0.0f,
				max_width_chars = 1,
				ellipsize = Pango.EllipsizeMode.END,
				hexpand = true,
			};
			label.set_markup(Markup.escape_text(name));
			label_box.add(label);

			if (builtin) {
				var builtin_label = new Gtk.Label(null) {
					valign = Gtk.Align.CENTER,
					xalign = 0.0f,
					max_width_chars = 1,
					ellipsize = Pango.EllipsizeMode.END,
					hexpand = true,
				};
				builtin_label.set_markup("<i><small>%s</small></i>".printf(_("Built-in")));
				builtin_label.get_style_context().add_class("dim-label");
				label_box.add(builtin_label);
			} else {
				label.vexpand = true;
			}

			add(image);
			add(label_box);

			show_all();
		}
	}
}
