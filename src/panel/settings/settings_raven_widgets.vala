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
	* RavenWidgetSettingsFrame provides a UI wrapper for widget instance settings
	*/
	public class RavenWidgetSettingsFrame : Gtk.Box {
		public RavenWidgetSettingsFrame() {
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);

			Gtk.Label lab = new Gtk.Label(null);
			lab.set_markup("<big>%s</big>".printf(_("Widget Settings")));
			lab.halign = Gtk.Align.START;
			lab.margin_bottom = 6;
			valign = Gtk.Align.START;

			this.get_style_context().add_class("settings-frame");
			lab.get_style_context().add_class("settings-title");

			var sep = new Gtk.Separator(Gtk.Orientation.HORIZONTAL);
			sep.margin_bottom = 6;
			this.pack_start(lab, false, false, 0);
			this.pack_start(sep, false, false, 0);
		}

		public override void add(Gtk.Widget widget) {
			this.pack_start(widget, false, false, 0);
		}
	}

	public class RavenWidgetsPage : Gtk.Box {
		private unowned Budgie.DesktopManager? manager = null;
		private unowned Budgie.Raven? raven = null;

		private Gtk.ListBox listbox_widgets;
		private HashTable<string, RavenWidgetItem?> items;
		Gtk.Button button_add;
		private Gtk.Button button_move_widget_up;
		private Gtk.Button button_move_widget_down;
		private Gtk.Button button_remove_widget;

		/* Allow us to display settings when each item is selected */
		Gtk.Stack settings_stack;

		public RavenWidgetsPage(Budgie.DesktopManager manager) {
			Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);

			this.manager = manager;
			this.raven = Budgie.Raven.get_instance();

			valign = Gtk.Align.FILL;
			margin = 6;

			var frame_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);

			var move_box = new Gtk.ButtonBox(Gtk.Orientation.HORIZONTAL);
			move_box.set_layout(Gtk.ButtonBoxStyle.START);
			move_box.get_style_context().add_class(Gtk.STYLE_CLASS_INLINE_TOOLBAR);

			button_move_widget_up = new Gtk.Button.from_icon_name("go-up-symbolic", Gtk.IconSize.MENU);
			button_move_widget_up.clicked.connect(move_widget_up);
			move_box.add(button_move_widget_up);

			button_move_widget_down = new Gtk.Button.from_icon_name("go-down-symbolic", Gtk.IconSize.MENU);
			button_move_widget_down.clicked.connect(move_widget_down);
			move_box.add(button_move_widget_down);

			button_remove_widget = new Gtk.Button.from_icon_name("edit-delete-symbolic", Gtk.IconSize.MENU);
			button_remove_widget.clicked.connect(remove_widget);
			move_box.add(button_remove_widget);

			frame_box.pack_start(move_box, false, false, 0);

			var frame = new Gtk.Frame(null);
			frame.vexpand = false;
			frame.margin_end = 20;
			frame.margin_top = 12;
			frame.add(frame_box);

			items = new HashTable<string, RavenWidgetItem?>(str_hash, str_equal);

			listbox_widgets = new Gtk.ListBox();
			listbox_widgets.set_activate_on_single_click(true);
			listbox_widgets.row_selected.connect(row_selected);

			Gtk.ScrolledWindow scroll = new Gtk.ScrolledWindow(null, null);
			scroll.add(listbox_widgets);
			scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
			frame_box.pack_start(scroll, true, true, 0);
			this.pack_start(frame, false, true, 0);

			move_box.get_style_context().set_junction_sides(Gtk.JunctionSides.BOTTOM);
			listbox_widgets.get_style_context().set_junction_sides(Gtk.JunctionSides.TOP);

			configure_actions();

			this.raven.on_widget_added.connect(add_widget_item);
			this.raven.get_existing_widgets().foreach(add_widget_item);
		}

		private void add_widget_item(RavenWidgetData widget_data) {
			if (items.contains(widget_data.uuid)) {
				return;
			}

			/* Allow viewing settings on demand */
			if (widget_data.supports_settings) {
				var frame = new RavenWidgetSettingsFrame();
				var ui = (widget_data.widget_instance as Budgie.RavenWidget).build_settings_ui();
				frame.add(ui);
				ui.show();
				frame.show();
				settings_stack.add_named(frame, widget_data.uuid);
			}

			var item = new RavenWidgetItem(widget_data);
			item.show_all();
			listbox_widgets.add(item);
			items[widget_data.uuid] = item;
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
			Idle.add(() => {
				settings_stack.set_visible_child_name("main");
				return false;
			});
		}

		/**
		* Changed the row so update the UI
		*/
		private void row_selected(Gtk.ListBoxRow? row) {
			if (row == null) {
				this.settings_stack.set_visible_child_name("main");
				return;
			}

			update_action_buttons();
			unowned RavenWidgetItem? item = row.get_child() as RavenWidgetItem;
			if (!item.widget_data.supports_settings) {
				settings_stack.set_visible_child_name("no-settings");
				return;
			}

			unowned Gtk.Widget? lookup = settings_stack.get_child_by_name(item.widget_data.uuid);
			settings_stack.set_visible_child(lookup);
		}

		/**
		* Update the sensitivity of the action buttons based on the current
		* selection.
		*/
		void update_action_buttons() {
			unowned var selected_row = listbox_widgets.get_selected_row();

			/* Require widget info to be useful. */
			if (selected_row == null) {
				button_remove_widget.set_sensitive(false);
				button_move_widget_up.set_sensitive(false);
				button_move_widget_down.set_sensitive(false);
				return;
			}

			button_remove_widget.set_sensitive(true);
			button_move_widget_up.set_sensitive(can_move_row_up(selected_row));
			button_move_widget_down.set_sensitive(can_move_row_down(selected_row));
		}

		void add_widget() {
			var dlg = new RavenWidgetChooser(this.get_toplevel() as Gtk.Window);
			dlg.set_plugin_list(this.manager.get_raven_plugins());
			string? widget_id = dlg.run();
			dlg.destroy();
			if (widget_id == null) {
				return;
			}

			raven.create_widget_instance(widget_id);
		}

		/**
		* User requested we delete this widget. Make sure they meant it!
		*/
		void remove_widget() {
			var row = listbox_widgets.get_selected_row();
			if (row == null) {
				return;
			}

			var dlg = new RemoveAppletDialog(this.get_toplevel() as Gtk.Window);
			bool del = dlg.run();
			dlg.destroy();
			if (del) {
				raven.remove_widget(get_current_data());
				listbox_widgets.remove(row);
				update_action_buttons();
			}
		}

		private bool can_move_row_up(Gtk.ListBoxRow? row) {
			return row == null ? false : row.get_index() > 0;
		}

		private bool can_move_row_down(Gtk.ListBoxRow? row) {
			return row == null ? false : row.get_index() < listbox_widgets.get_children().length() - 1;
		}

		private void move_widget_up() {
			Gtk.ListBoxRow? row = listbox_widgets.get_selected_row();

			if (can_move_row_up(row)) {
				listbox_widgets.unselect_row(row);

				var new_index = row.get_index() - 1;
				listbox_widgets.remove(row);
				listbox_widgets.insert(row, new_index);

				listbox_widgets.select_row(row);

				raven.move_widget_up(((RavenWidgetItem) row.get_child()).widget_data);
			}
		}

		private void move_widget_down() {
			Gtk.ListBoxRow? row = listbox_widgets.get_selected_row();

			if (can_move_row_down(row)) {
				listbox_widgets.unselect_row(row);

				var new_index = row.get_index() + 1;
				listbox_widgets.remove(row);
				listbox_widgets.insert(row, new_index);

				listbox_widgets.select_row(row);

				raven.move_widget_down(((RavenWidgetItem) row.get_child()).widget_data);
			}
		}

		private RavenWidgetData get_current_data() {
			unowned Gtk.ListBoxRow? row = listbox_widgets.get_selected_row();
			return ((RavenWidgetItem) row.get_child()).widget_data;
		}
	}

	/**
	* WidgetItem is used to represent a Budgie Widget in the list
	*/
	public class RavenWidgetItem : Gtk.Box {
		public Budgie.RavenWidgetData widget_data;

		private Gtk.Image image;
		private Gtk.Label label;

		/**
		* Construct a new WidgetItem for the given widget
		*/
		public RavenWidgetItem(Budgie.RavenWidgetData widget_data) {
			this.widget_data = widget_data;

			get_style_context().add_class("widget-item");

			margin_top = 4;
			margin_bottom = 4;

			image = new Gtk.Image.from_icon_name(widget_data.plugin_info.get_icon_name(), Gtk.IconSize.MENU);
			image.margin_start = 12;
			image.margin_end = 14;
			pack_start(image, false, false, 0);

			label = new Gtk.Label(widget_data.plugin_info.get_name());
			label.margin_end = 18;
			label.halign = Gtk.Align.START;
			pack_start(label, false, false, 0);

			this.show_all();
		}
	}
}
