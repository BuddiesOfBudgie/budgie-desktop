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
	/**
	* RavenPage shows options for configuring Raven
	*/
	public class RavenPage : Budgie.SettingsPage {
		private Gtk.Stack stack;
		private Gtk.StackSwitcher switcher;

		public RavenPage(Budgie.DesktopManager? manager) {
			Object(group: SETTINGS_GROUP_APPEARANCE,
				content_id: "raven",
				title: "Raven",
				display_weight: 3,
				icon_name: "preferences-calendar-and-tasks" // Subject to change
			);

			border_width = 0;
			margin_top = 8;
			margin_bottom = 8;
			halign = Gtk.Align.FILL;

			var swbox = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
			pack_start(swbox, false, false, 0);

			/* Main layout bits */
			switcher = new Gtk.StackSwitcher();
			switcher.halign = Gtk.Align.CENTER;
			stack = new Gtk.Stack();
			stack.margin_top = 12;
			stack.margin_bottom = 12;
			stack.set_homogeneous(false);
			switcher.set_stack(stack);
			swbox.pack_start(switcher, true, true, 0);
			pack_start(stack, true, true, 0);

			stack.add_titled(new Budgie.RavenWidgetsPage(manager), "widgets", _("Widgets"));
			stack.add_titled(new Budgie.RavenSettingsPage(), "settings", _("Settings"));

			show_all();
		}
	}
}
