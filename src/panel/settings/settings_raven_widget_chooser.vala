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
	* RavenPluginItem is used to represent a plugin for the user to add to their
	* panel through the Applet API
	*/
	public class RavenPluginItem : Gtk.Box {
		/**
		* We're bound to the info
		*/
		public unowned Peas.PluginInfo? plugin { public get ; construct set; }

		private Gtk.Image image;
		private Gtk.Label label;

		/**
		* Construct a new RavenPluginItem for the given widget
		*/
		public RavenPluginItem(Peas.PluginInfo? info) {
			Object(plugin: info);

			get_style_context().add_class("plugin-item");

			margin_top = 4;
			margin_bottom = 4;

			image = new Gtk.Image.from_icon_name(info.get_icon_name(), Gtk.IconSize.LARGE_TOOLBAR);
			image.pixel_size = 32;
			image.margin_start = 8;
			image.margin_end = 12;

			label = new Gtk.Label(null);
			label.set_markup("<b>%s</b>".printf(info.get_name()));
			label.margin_end = 32;
			label.halign = Gtk.Align.START;

			pack_start(image, false, false, 0);
			pack_start(label, false, false, 0);
			if (info.is_builtin()) {
				var builtin = new Gtk.Label(null);
				builtin.set_markup("<i>%s</i>".printf(_("Built-in")));
				builtin.get_style_context().add_class("dim-label");
				builtin.margin_end = 12;
				pack_end(builtin, false, false, 0);
			}

			show_all();
		}
	}

	/**
	* RavenWidgetChooser provides a dialog to allow selection of an widget to be added to Raven
	*/
	public class RavenWidgetChooser : Gtk.Dialog {
		private Gtk.ListBox applets;
		private Gtk.Widget button_ok;

		private Gtk.Image? selected_plugin_icon = null;
		private Gtk.Label? selected_plugin_name = null;
		private Gtk.Label? selected_plugin_description = null;
		private Gtk.Label? selected_plugin_authors = null;
		private Gtk.Label? selected_plugin_copyright = null;
		private Gtk.Label? selected_plugin_website = null;

		private string? applet_id = null;

		public RavenWidgetChooser(Gtk.Window parent) {
			Object(use_header_bar: 1,
				modal: true,
				title: _("Choose a widget"),
				transient_for: parent,
				resizable: false);

			Gtk.Box content_area = get_content_area() as Gtk.Box;
			content_area.set_orientation(Gtk.Orientation.HORIZONTAL);

			this.add_button(_("Cancel"), Gtk.ResponseType.CANCEL);
			button_ok = this.add_button(_("Add"), Gtk.ResponseType.ACCEPT);
			button_ok.set_sensitive(false);
			button_ok.get_style_context().add_class(Gtk.STYLE_CLASS_SUGGESTED_ACTION);

			var scroll = new Gtk.ScrolledWindow(null, null);
			scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
			applets = new Gtk.ListBox();
			applets.set_activate_on_single_click(false);
			applets.set_sort_func(this.sort_applets);
			scroll.add(applets);

			applets.row_selected.connect(row_selected);
			applets.row_activated.connect(row_activated);

			content_area.pack_start(scroll, false, false, 0);

			selected_plugin_icon = new Gtk.Image();
			selected_plugin_icon.pixel_size = 64;

			selected_plugin_name = new Gtk.Label("");
			selected_plugin_name.halign = Gtk.Align.START;

			selected_plugin_description = new Gtk.Label("");
			selected_plugin_description.set_line_wrap(true);
			selected_plugin_description.set_size_request(368, -1);
			selected_plugin_description.set_max_width_chars(0);
			selected_plugin_description.margin_start = 4;
			selected_plugin_description.xalign = 0.0f;
			selected_plugin_description.halign = Gtk.Align.START;

			selected_plugin_authors = new Gtk.Label("");
			selected_plugin_authors.halign = Gtk.Align.START;

			selected_plugin_website = new Gtk.Label("");
			selected_plugin_website.halign = Gtk.Align.START;

			selected_plugin_copyright = new Gtk.Label("");

			var upper_text_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
			upper_text_box.valign = Gtk.Align.START;
			upper_text_box.pack_start(selected_plugin_name, false, false, 0);
			upper_text_box.pack_start(selected_plugin_authors, false, false, 0);
			upper_text_box.pack_start(selected_plugin_website, false, false, 0);

			var upper_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
			upper_box.pack_start(selected_plugin_icon, false, false, 0);
			upper_box.pack_start(upper_text_box, false, false, 0);

			var plugin_info_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
			plugin_info_box.border_width = 8;
			plugin_info_box.margin_start = 8;
			plugin_info_box.margin_end = 8;
			plugin_info_box.pack_start(upper_box, false, false, 0);
			plugin_info_box.pack_start(selected_plugin_description, false, false, 0);
			plugin_info_box.pack_end(selected_plugin_copyright, false, false, 0);

			content_area.pack_start(plugin_info_box, true, true, 0);

			content_area.show_all();

			set_default_size(650, 350);
		}

		/**
		* Simple accessor to get the new widget ID to be added
		*/
		public new string? run() {
			Gtk.ResponseType resp = (Gtk.ResponseType)base.run();
			switch (resp) {
				case Gtk.ResponseType.ACCEPT:
					return this.applet_id;
				case Gtk.ResponseType.CANCEL:
				default:
					return null;
			}
		}

		/**
		* Super simple sorting of applets in alphabetical listing
		*/
		int sort_applets(Gtk.ListBoxRow? a, Gtk.ListBoxRow? b) {
			Peas.PluginInfo? infoA = ((RavenPluginItem) a.get_child()).plugin;
			Peas.PluginInfo? infoB = ((RavenPluginItem) b.get_child()).plugin;

			return strcmp(infoA.get_name().down(), infoB.get_name().down());
		}

		/**
		* User picked a plugin
		*/
		void row_selected(Gtk.ListBoxRow? row) {
			if (row == null) {
				this.applet_id = null;
				this.button_ok.set_sensitive(false);
				return;
			}

			this.button_ok.set_sensitive(true);

			var plugin = ((RavenPluginItem) row.get_child()).plugin;
			this.applet_id = plugin.get_module_name();

			selected_plugin_icon.set_from_icon_name(plugin.get_icon_name(), Gtk.IconSize.LARGE_TOOLBAR);
			selected_plugin_name.set_markup("<span size='x-large'>%s</span>".printf(plugin.get_name()));

			if (plugin.get_description() != null) {
				selected_plugin_description.set_text(plugin.get_description());
			} else {
				selected_plugin_description.set_text("No description.");
			}

			if (plugin.get_copyright() != null) {
				selected_plugin_copyright.set_markup("<span alpha='50%'>%s</span>".printf(plugin.get_copyright()));
				selected_plugin_copyright.show();
			} else {
				selected_plugin_copyright.hide();
			}

			if (plugin.get_website() != null) {
				selected_plugin_website.set_markup("<a href='%s'>%s</a>".printf(plugin.get_website(), plugin.get_website()));
				selected_plugin_website.show();
			} else {
				selected_plugin_website.hide();
			}

			if (plugin.get_authors() != null && plugin.get_authors().length > 0) {
				var authors_string = "by ";
				var authors = plugin.get_authors();
				for (int i = 0; i < authors.length - 1; i++) {
					authors_string += authors[i] + ", ";
				}
				authors_string += authors[authors.length - 1];
				selected_plugin_authors.set_markup("<i><span alpha='70%'>%s</span></i>".printf(authors_string));
			} else {
				selected_plugin_authors.set_markup("<i><span alpha='70%'>%s</span></i>".printf(_("No authors listed")));
			}
		}

		/**
		* Special sauce to allow us to double-click activate an widget
		*/
		void row_activated(Gtk.ListBoxRow? row) {
			this.row_selected(row);

			if (this.applet_id != null) {
				this.response(Gtk.ResponseType.ACCEPT);
			}
		}

		/**
		* Set the available plugins to show in the dialog
		*/
		public void set_plugin_list(List<Peas.PluginInfo?> plugins) {
			foreach (var child in applets.get_children()) {
				child.destroy();
			}

			foreach (var plugin in plugins) {
				this.add_plugin(plugin);
			}
			this.applets.invalidate_sort();
		}

		/**
		* Add a new plugin to our display area
		*/
		void add_plugin(Peas.PluginInfo? plugin) {
			this.applets.add(new RavenPluginItem(plugin));
		}
	}
}
