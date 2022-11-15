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
		private MprisWidget? mpris = null;
		private CalendarWidget? cal = null;
		private Budgie.SoundWidget? audio_input_widget = null;
		private Budgie.SoundWidget? audio_output_widget = null;
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
			box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			scroll.add(box);

			cal = new CalendarWidget(raven_settings);
			box.pack_start(cal, false, false, 0);

			audio_output_widget = new Budgie.SoundWidget("output");
			box.pack_start(audio_output_widget, false, false, 0);

			audio_input_widget = new Budgie.SoundWidget("input");
			box.pack_start(audio_input_widget, false, false, 0);

			mpris = new MprisWidget();
			box.pack_start(mpris, false, false, 0);

			// Make sure everything is shown. Not having this can cause
			// silent failures when switching stack pages or opening Raven.
			scroll.show_all();

			main_stack.notify["visible-child-name"].connect(on_name_change);
			set_clean();
		}

		public void add_widget_instance(Gtk.Bin? widget_instance) {
			box.pack_end(widget_instance, false, false, 8);
			requested_draw();
		}

		public void remove_widget_instance(Gtk.Bin? widget_instance) {
			box.remove(widget_instance);
			requested_draw();
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

			bool show_widget = raven_settings.get_boolean(key);

			/**
			* You're probably wondering why I'm not just setting a visible value here, and that's typically a good idea.
			* However, it causes weird focus and rendering issues even when has_visible_focus is set to false. I don't get it either, so we're doing this.
			*/
			if (key == "show-mpris-widget") { // MPRIS
				mpris.set_show(show_widget);
			}

			requested_draw();
		}

		public void set_clean() {
			on_raven_settings_changed("show-mpris-widget");
			main_stack.set_visible_child_name("widgets");
		}
	}
}
