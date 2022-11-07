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

		private Gtk.ListBox listbox_widgets;
		Gtk.Button button_add;
		private Gtk.Button button_move_widget_up;
		private Gtk.Button button_move_widget_down;
		private Gtk.Button button_remove_widget;

		/* Allow us to display settings when each item is selected */
		Gtk.Stack settings_stack;

		public RavenWidgetsPage(Budgie.DesktopManager manager) {
			Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);

			this.manager = manager;

			valign = Gtk.Align.FILL;
			margin = 6;

			var frame_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);

			var move_box = new Gtk.ButtonBox(Gtk.Orientation.HORIZONTAL);
			move_box.set_layout(Gtk.ButtonBoxStyle.START);
			move_box.get_style_context().add_class(Gtk.STYLE_CLASS_INLINE_TOOLBAR);

			button_move_widget_up = new Gtk.Button.from_icon_name("go-up-symbolic", Gtk.IconSize.MENU);
			move_box.add(button_move_widget_up);

			button_move_widget_down = new Gtk.Button.from_icon_name("go-down-symbolic", Gtk.IconSize.MENU);
			move_box.add(button_move_widget_down);

			button_remove_widget = new Gtk.Button.from_icon_name("edit-delete-symbolic", Gtk.IconSize.MENU);
			move_box.add(button_remove_widget);

			frame_box.pack_start(move_box, false, false, 0);

			var frame = new Gtk.Frame(null);
			frame.vexpand = false;
			frame.margin_end = 20;
			frame.margin_top = 12;
			frame.add(frame_box);

			listbox_widgets = new Gtk.ListBox();
			listbox_widgets.set_activate_on_single_click(true);

			Gtk.ScrolledWindow scroll = new Gtk.ScrolledWindow(null, null);
			scroll.add(listbox_widgets);
			scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
			frame_box.pack_start(scroll, true, true, 0);
			this.pack_start(frame, false, true, 0);

			move_box.get_style_context().set_junction_sides(Gtk.JunctionSides.BOTTOM);
			listbox_widgets.get_style_context().set_junction_sides(Gtk.JunctionSides.TOP);

			configure_actions();
		}

		/**
		* Configure the action grid to manipulation the widgets
		*/
		void configure_actions() {
			var grid = new SettingsGrid();
			grid.small_mode = true;
			this.pack_start(grid, false, false, 0);

			/* Allow adding new widgets */
			button_add = new Gtk.Button.from_icon_name("list-add-symbolic", Gtk.IconSize.MENU);
			button_add.valign = Gtk.Align.CENTER;
			button_add.vexpand = false;
			button_add.get_style_context().add_class(Gtk.STYLE_CLASS_SUGGESTED_ACTION);
			button_add.get_style_context().add_class("round-button");
			button_add.clicked.connect(this.add_widget);
			grid.add_row(new SettingsRow(button_add,
				_("Add widget"),
				_("Choose a new widget to add to the Widgets view")));

			settings_stack = new Gtk.Stack();
			settings_stack.set_homogeneous(false);
			settings_stack.halign = Gtk.Align.FILL;
			settings_stack.valign = Gtk.Align.START;
			settings_stack.margin_top = 24;
			grid.attach(settings_stack, 0, ++grid.current_row, 2, 1);


			/* Placeholder for no settings */
			var placeholder = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
			placeholder.valign = Gtk.Align.START;
			var placeholder_img = new Gtk.Image.from_icon_name("dialog-information-symbolic", Gtk.IconSize.MENU);
			var placeholder_text = new Gtk.Label(_("No settings available"));
			placeholder_text.set_margin_start(10);
			placeholder.pack_start(placeholder_img, false, false, 0);
			placeholder.pack_start(placeholder_text, false, false, 0);
			placeholder.show_all();
			placeholder_img.valign = Gtk.Align.CENTER;
			placeholder_text.valign = Gtk.Align.CENTER;
			settings_stack.add_named(placeholder, "no-settings");

			/* Empty placeholder for no selection .. */
			var empty = new Gtk.EventBox();
			settings_stack.add_named(empty, "main");
		}

		void add_widget() {
			// no-op
		}
	}
}
