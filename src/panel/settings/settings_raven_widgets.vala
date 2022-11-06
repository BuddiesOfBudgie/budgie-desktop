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

namespace Budgie {
	public class RavenWidgetsPage : Gtk.Box {
		private unowned Budgie.DesktopManager? manager = null;

		private Gtk.ListBox listbox_applets;
		private Gtk.Button button_move_applet_up;
		private Gtk.Button button_move_applet_down;
		private Gtk.Button button_remove_applet;

		public RavenWidgetsPage(Budgie.DesktopManager manager) {
			Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);

			this.manager = manager;

			valign = Gtk.Align.FILL;
			margin = 6;

			var frame_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);

			var move_box = new Gtk.ButtonBox(Gtk.Orientation.HORIZONTAL);
			move_box.set_layout(Gtk.ButtonBoxStyle.START);
			move_box.get_style_context().add_class(Gtk.STYLE_CLASS_INLINE_TOOLBAR);

			button_move_applet_up = new Gtk.Button.from_icon_name("go-up-symbolic", Gtk.IconSize.MENU);
			move_box.add(button_move_applet_up);

			button_move_applet_down = new Gtk.Button.from_icon_name("go-down-symbolic", Gtk.IconSize.MENU);
			move_box.add(button_move_applet_down);

			button_remove_applet = new Gtk.Button.from_icon_name("edit-delete-symbolic", Gtk.IconSize.MENU);
			move_box.add(button_remove_applet);

			frame_box.pack_start(move_box, false, false, 0);

			var frame = new Gtk.Frame(null);
			frame.vexpand = false;
			frame.margin_end = 20;
			frame.margin_top = 12;
			frame.add(frame_box);

			listbox_applets = new Gtk.ListBox();
			listbox_applets.set_activate_on_single_click(true);

			Gtk.ScrolledWindow scroll = new Gtk.ScrolledWindow(null, null);
			scroll.add(listbox_applets);
			scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
			frame_box.pack_start(scroll, true, true, 0);
			this.pack_start(frame, false, true, 0);

			move_box.get_style_context().set_junction_sides(Gtk.JunctionSides.BOTTOM);
			listbox_applets.get_style_context().set_junction_sides(Gtk.JunctionSides.TOP);
		}
	}
}
