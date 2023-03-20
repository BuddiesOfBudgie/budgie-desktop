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

			margin_top = 4;
			margin_bottom = 4;

			image = new Gtk.Image.from_icon_name(icon, Gtk.IconSize.MENU) {
				margin_start = 12,
				margin_end = 14,
			};
			pack_start(image, false, false, 0);

			label = new Gtk.Label(name) {
				margin_end = 18,
				halign = Gtk.Align.START,
			};
			pack_start(label, false, false, 0);

			show_all();
		}
	}
}
