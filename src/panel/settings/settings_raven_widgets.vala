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

			show_all();
		}

		public override void add(Gtk.Widget widget) {
			this.pack_start(widget, false, false, 0);
		}
	}

	public class RavenWidgetsPage : Gtk.Box {
		private unowned Budgie.DesktopManager? manager = null;
		private unowned Budgie.Raven? raven = null;

		private Gtk.ListBox listbox_widgets;
		private HashTable<string, SettingsPluginListboxItem> items;
		private HashTable<string, RavenWidgetData> widgets;
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

			halign = Gtk.Align.CENTER;
			valign = Gtk.Align.FILL;

			var frame_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			frame_box.width_request = 200;

			var move_box = new Gtk.ButtonBox(Gtk.Orientation.HORIZONTAL);
			move_box.set_layout(Gtk.ButtonBoxStyle.EXPAND);
			move_box.spacing = 1;
			move_box.get_style_context().add_class(Gtk.STYLE_CLASS_INLINE_TOOLBAR);

			button_move_widget_up = new Gtk.Button.from_icon_name("go-up-symbolic", Gtk.IconSize.MENU);
			button_move_widget_up.clicked.connect(() => move_widget_by_offset(-1));
			move_box.add(button_move_widget_up);

			button_move_widget_down = new Gtk.Button.from_icon_name("go-down-symbolic", Gtk.IconSize.MENU);
			button_move_widget_down.clicked.connect(() => move_widget_by_offset(1));
			move_box.add(button_move_widget_down);

			button_remove_widget = new Gtk.Button.from_icon_name("edit-delete-symbolic", Gtk.IconSize.MENU);
			button_remove_widget.clicked.connect(remove_widget);
			move_box.add(button_remove_widget);

			frame_box.pack_start(move_box, false, false, 0);

			var frame = new Gtk.Frame(null);
			frame.vexpand = false;
			frame.margin_end = 20;
			frame.margin_top = 6;
			frame.add(frame_box);

			items = new HashTable<string, SettingsPluginListboxItem>(str_hash, str_equal);
			widgets = new HashTable<string, RavenWidgetData>(str_hash, str_equal);

			listbox_widgets = new Gtk.ListBox();
			listbox_widgets.set_activate_on_single_click(true);
			listbox_widgets.row_selected.connect(row_selected);

			Gtk.ScrolledWindow scroll = new Gtk.ScrolledWindow(null, null);
			scroll.add(listbox_widgets);
			scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
			frame_box.pack_start(scroll, true, true, 0);
			this.pack_start(frame, false, false, 0);

			move_box.get_style_context().set_junction_sides(Gtk.JunctionSides.BOTTOM);
			listbox_widgets.get_style_context().set_junction_sides(Gtk.JunctionSides.TOP);

			configure_actions();
			update_action_buttons();

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
				var ui = ((Budgie.RavenWidget) widget_data.widget_instance).build_settings_ui();
				frame.add(ui);
				ui.show();
				frame.show();
				settings_stack.add_named(frame, widget_data.uuid);
			}

			var info = widget_data.plugin_info;
			var item = new SettingsPluginListboxItem(widget_data.uuid, info.get_name(), info.get_icon_name(), info.is_builtin());
			item.show_all();
			items[widget_data.uuid] = item;
			widgets[widget_data.uuid] = widget_data;
			listbox_widgets.add(item);
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
			var item = row.get_child() as SettingsPluginListboxItem;
			var widget = widgets.get(item.instance_uuid);
			if (!widget.supports_settings) {
				settings_stack.set_visible_child_name("no-settings");
				return;
			}

			unowned Gtk.Widget? lookup = settings_stack.get_child_by_name(widget.uuid);
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
			button_move_widget_up.set_sensitive(selected_row.get_index() > 0);
			button_move_widget_down.set_sensitive(selected_row.get_index() < listbox_widgets.get_children().length() - 1);
		}

		void add_widget() {
			this.manager.rescan_raven_plugins();
			var dlg = new SettingsPluginChooser(this.get_toplevel() as Gtk.Window);
			dlg.set_plugin_list(this.manager.get_raven_plugins());
			string? widget_id = dlg.run();
			dlg.destroy();
			if (widget_id == null) {
				return;
			}

			var result = raven.create_widget_instance(widget_id);
			if (result != RavenWidgetCreationResult.SUCCESS) {
				string markup = null;
				switch (result) {
					case RavenWidgetCreationResult.PLUGIN_INFO_MISSING:
						markup = _("Failed to create the widget instance. The plugin engine could not find info for this plugin.");
						break;
					case RavenWidgetCreationResult.INVALID_MODULE_NAME:
						markup = _("Failed to create the widget instance. The module name must be in reverse-DNS format, " +
							"such as 'tld.domain.group.WidgetName.so' for C/Vala or 'tld_domain_group_WidgetName' for Python.");
						break;
					case RavenWidgetCreationResult.PLUGIN_LOAD_FAILED:
						markup = _("Failed to create the widget instance. The plugin engine failed to load the plugin from the disk.");
						break;
					case RavenWidgetCreationResult.SCHEMA_LOAD_FAILED:
						markup = _("Failed to create the widget instance. The plugin supports settings, but does not install a " +
							"settings schema with the same name.\n\nThe schema name should be identical to the module name, but " +
							"with no extension and (in the case of Python) the underscores replaced with periods.");
						break;
					case RavenWidgetCreationResult.INSTANCE_CREATION_FAILED:
						markup = _("Failed to create the widget instance due to an unknown failure.");
						break;
					default:
						break;
				}
				var failure_dialog = new Gtk.MessageDialog.with_markup(
					this.get_toplevel() as Gtk.Window,
					Gtk.DialogFlags.DESTROY_WITH_PARENT | Gtk.DialogFlags.MODAL,
					Gtk.MessageType.ERROR,
					Gtk.ButtonsType.CLOSE,
					markup
				);
				failure_dialog.run();
				failure_dialog.destroy();
			}
		}

		/**
		* User requested we delete this widget. Make sure they meant it!
		*/
		void remove_widget() {
			var row = listbox_widgets.get_selected_row();
			if (row == null) {
				return;
			}

			var dlg = new RemoveRavenWidgetDialog(get_toplevel() as Gtk.Window);
			bool del = dlg.run();
			dlg.destroy();
			if (del) {
				var widget = get_current_data();
				items.remove(widget.uuid);
				widgets.remove(widget.uuid);
				raven.remove_widget(widget);
				listbox_widgets.remove(row);
				update_action_buttons();
			}
		}

		private void move_widget_by_offset(int offset) {
			Gtk.ListBoxRow? row = listbox_widgets.get_selected_row();
			if (row == null) return;

			var new_index = row.get_index() + offset;

			if (new_index < listbox_widgets.get_children().length() && new_index >= 0) {
				listbox_widgets.unselect_row(row);

				listbox_widgets.remove(row);
				listbox_widgets.insert(row, new_index);

				listbox_widgets.select_row(row);

				var item = (SettingsPluginListboxItem) row.get_child();
				raven.move_widget_by_offset(widgets.get(item.instance_uuid), offset);
			}
		}

		private RavenWidgetData get_current_data() {
			var item = (SettingsPluginListboxItem) listbox_widgets.get_selected_row().get_child();
			return widgets.get(item.instance_uuid);
		}
	}
}
