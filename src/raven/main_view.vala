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
	public class MainView : Gtk.Box {
		private Gtk.Box? box = null; // Holds our content
		private Settings? raven_settings = null;
		private Gtk.ScrolledWindow? scroll = null;

		private Gtk.Stack? main_stack = null;
		private Gtk.StackSwitcher? switcher = null;

		public signal void requested_draw(); // Request the window to redraw itself

		public void expose_notification() {
			main_stack.set_visible_child_name("notifications");
		}

		public MainView() {
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			raven_settings = new Settings("com.solus-project.budgie-raven");
			raven_settings.changed.connect(this.on_raven_settings_changed);

			var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
			header.get_style_context().add_class("raven-header");
			header.get_style_context().add_class("top");
			main_stack = new Gtk.Stack();
			pack_start(header, false, false, 0);

			/* Anim */
			main_stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT);
			switcher = new Gtk.StackSwitcher();

			switcher.valign = Gtk.Align.CENTER;
			switcher.margin_top = 4;
			switcher.margin_bottom = 4;
			switcher.set_halign(Gtk.Align.CENTER);
			switcher.set_stack(main_stack);
			header.pack_start(switcher, true, true, 0);

			pack_start(main_stack, true, true, 0);

			scroll = new Gtk.ScrolledWindow(null, null);
			main_stack.add_titled(scroll, "widgets", _("Widgets"));
			/* Dummy - no notifications right now */
			var not = new NotificationsView();
			main_stack.add_titled(not, "notifications", _("Notifications"));

			scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);

			/* Eventually these guys get dynamically loaded */
			box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
			box.margin_top = 8;
			box.margin_bottom = 8;
			scroll.add(box);

			// Make sure everything is shown. Not having this can cause
			// silent failures when switching stack pages or opening Raven.
			scroll.show_all();

			main_stack.notify["visible-child-name"].connect(on_name_change);
			set_clean();
		}

		public void add_widget_instance(Gtk.Bin? widget_instance) {
			box.add(widget_instance);
			requested_draw();
		}

		public void remove_widget_instance(Gtk.Bin? widget_instance) {
			box.remove(widget_instance);
			requested_draw();
		}

		public void move_widget_instance_up(Gtk.Bin? widget_instance) {
			var current_index = box.get_children().index(widget_instance);

			if (current_index > 0) {
				box.reorder_child(widget_instance, current_index - 1);
			}
		}

		public void move_widget_instance_down(Gtk.Bin? widget_instance) {
			var current_index = box.get_children().index(widget_instance);

			if (current_index < box.get_children().length() - 1) {
				box.reorder_child(widget_instance, current_index + 1);
			}
		}

		void on_name_change() {
			if (main_stack.get_visible_child_name() == "notifications") {
				Raven.get_instance().ReadNotifications();
			}
		}

		/**
		* on_raven_settings_changed will handle when the settings for Raven widgets have changed
		*/
		void on_raven_settings_changed(string key) {
			// This key is handled by the panel manager instead of Raven directly.
			// Moreover, it isn't a boolean so it logs a Critical message on the get_boolean() below.
			if (key == "raven-position") {
				return;
			}

			requested_draw();
		}

		public void set_clean() {
			main_stack.set_visible_child_name("widgets");
		}
	}
}
