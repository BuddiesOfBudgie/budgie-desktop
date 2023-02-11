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
	* We need to probe the dbus daemon directly, hence this interface
	*/
	[DBus (name="org.freedesktop.DBus")]
	public interface DBusImpl : Object {
		public abstract async string[] list_names() throws DBusError, IOError;
		public signal void name_owner_changed(string name, string old_owner, string new_owner);
	}

	/**
	* The meat of the operation
	*/
	public class RunDialog : Gtk.ApplicationWindow {
		Gtk.Revealer bottom_revealer;
		Gtk.ListBox? app_box;
		Gtk.SearchEntry entry;

		bool focus_quit = true;
		DBusImpl? impl = null;

		string search_term = "";

		Budgie.RelevancyService relevancy;
		Budgie.ThemeManager theme_manager;

		/* The .desktop file without the .desktop */
		string wanted_dbus_id = "";

		/* Active dbus names */
		HashTable<string,bool> active_names = null;

		construct {
			set_keep_above(true);
			set_position(Gtk.WindowPosition.CENTER);
			Gdk.Visual? visual = screen.get_rgba_visual();
			if (visual != null) {
				this.set_visual(visual);
			}
			get_style_context().add_class("budgie-run-dialog");

			this.relevancy = new Budgie.RelevancyService();
			this.theme_manager = new Budgie.ThemeManager(); // Initialize theme manager. What does this even do?

			/* Quicker than a list lookup */
			this.active_names = new HashTable<string,bool>(str_hash, str_equal);

			var header = new Gtk.EventBox();
			header.get_style_context().remove_class("titlebar");
			this.set_titlebar(header);

			var main_layout = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);

			/* Main layout, just a hbox with search-as-you-type */
			var hbox = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
			main_layout.pack_start(hbox, false, false, 0);

			this.entry = new Gtk.SearchEntry();
			entry.changed.connect(on_search_changed);
			entry.activate.connect(on_search_activate);
			entry.get_style_context().set_junction_sides(Gtk.JunctionSides.BOTTOM);
			hbox.pack_start(entry, true, true, 0);

			/* Revealer to hold the search results */
			bottom_revealer = new Gtk.Revealer() {
				reveal_child = false,
				transition_duration = 250,
				transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN
			};

			app_box = new Gtk.ListBox() {
				selection_mode = Gtk.SelectionMode.SINGLE,
				activate_on_single_click = true
			};
			app_box.row_activated.connect(on_row_activate);
			app_box.set_filter_func(this.on_filter);
			app_box.set_sort_func(this.on_sort);

			var scroll = new Gtk.ScrolledWindow(null, null) {
				hscrollbar_policy = Gtk.PolicyType.NEVER,
				vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
				max_content_height = 300,
				propagate_natural_height = true
			};
			scroll.get_style_context().set_junction_sides(Gtk.JunctionSides.TOP);

			scroll.add(app_box);
			bottom_revealer.add(scroll);
			main_layout.pack_start(bottom_revealer, true, true, 0);
			this.add(main_layout);

			/* Just so I can debug for now */
			bottom_revealer.set_reveal_child(false);

			/* Create our launcher buttons */
			this.load_buttons();

			/* Set size properties */
			int x, y;
			get_position(out x, out y);
			var monitor = get_screen().get_display().get_monitor_at_point(x, y);
			var rect = monitor.get_workarea();
			var width = (rect.width / 3).clamp(420, 840);

			set_size_request(width, -1);
			set_default_size(width, -1);

			/* Connect events */
			focus_out_event.connect(() => {
				if (!this.focus_quit) {
					return Gdk.EVENT_STOP;
				}
				debug("quiting from focus_out_event");
				this.application.quit();
				return Gdk.EVENT_STOP;
			});

			this.key_release_event.connect(on_key_release);

			/* Show and do DBus stuff */
			this.show_all();

			setup_dbus.begin();
		}

		/**
		 * Create a new budgie-run-dialog application window.
		 */
		public RunDialog(Gtk.Application app) {
			Object(
				application: app,
				border_width: 0,
				resizable: false,
				skip_pager_hint: true,
				skip_taskbar_hint: true,
				type_hint: Gdk.WindowTypeHint.DIALOG
			);
		}

		/**
		 * Create our launcher buttons from the Budgie AppIndexer.
		 */
		void load_buttons() {
			var added = new List<Budgie.Application>();
			var index = Budgie.AppIndex.get();
			var categories = index.get_categories();

			// Iterate over all of the applications and add
			// buttons for all of them
			foreach (Budgie.Category category in categories) {
				foreach (Budgie.Application a in category.apps) {
					// Check if the application should be shown
					if (!a.should_show) {
						continue;
					}

					// Check for duplicate entries
					if (added.find(a) != null) {
						continue;
					}

					var button = new LauncherButton(a);
					button.application.launched.connect(this.on_launched);
					button.application.launch_failed.connect(this.on_launch_failed);

					// Add the button if one hasn't already been created
					// for this application
					added.append(a);
					this.app_box.add(button);
				}
			}
		}

		/**
		 * Launch the given preconfigured button.
		 *
		 * This does additional DBus checking for apps to try to make
		 * sure they actually launched. That is because some apps are
		 * activated by DBus and the API lies about when the application
		 * starts, causing us to not actually launch the app before
		 * quitting.
		 */
		void launch_button(LauncherButton button) {
			var app = button.application;

			this.focus_quit = false;
			var splits = app.desktop_id.split(".desktop");
			if (app.dbus_activatable) {
				// Add this application to the list of DBus IDs to look for
				this.wanted_dbus_id = string.joinv(".desktop", splits[0:splits.length-1]);
			}

			if (app.launch()) {
				this.check_dbus_name();
				/* Some apps are slow to open so hide and quit when they're done */
				this.hide();
			} else {
				warning("Failed to launch application '%s'", app.name);
				this.application.quit();
			}
		}

		/**
		* Handle click/<enter> activation on the main list
		*/
		void on_row_activate(Gtk.ListBoxRow row) {
			var child = ((Gtk.Bin) row).get_child() as LauncherButton;
			this.launch_button(child);
		}

		/**
		* Handle <enter> activation on the search
		*/
		void on_search_activate() {
			// Make sure the search is up to date first
			this.on_search_changed();

			LauncherButton? button = null;

			var selected = app_box.get_selected_row();
			if (selected != null) {
				button = selected.get_child() as LauncherButton;
			} else {
				foreach (var row in app_box.get_children()) {
					if (row.get_visible() && row.get_child_visible()) {
						button = ((Gtk.Bin) row).get_child() as LauncherButton;
						break;
					}
				}
			}

			if (button == null) {
				return;
			}

			debug("launching '%s'", button.application.name);
			this.launch_button(button);
		}

		void on_search_changed() {
			this.search_term = entry.get_text();

			// Update the relevancy of all apps when
			// the search term changes
			foreach (var row in this.app_box.get_children()) {
				var button = ((Gtk.Bin) row).get_child() as LauncherButton;
				this.relevancy.update_relevancy(button.application, search_term);
			}

			this.app_box.invalidate_filter();
			this.app_box.invalidate_sort();

			// Check if there are visible entries
			Gtk.Widget? active_row = null;
			foreach (var row in app_box.get_children()) {
				if (row.get_visible() && row.get_child_visible()) {
					active_row = row;
					break;
				}
			}

			// Open or close the revealer as necessary
			if (active_row == null) {
				bottom_revealer.set_reveal_child(false);
			} else {
				bottom_revealer.set_reveal_child(true);
				app_box.select_row(active_row as Gtk.ListBoxRow);
			}
		}

		/**
		* Filter the list based on the application's relevancy to
		* the current search, if one is ongoing.
		*/
		bool on_filter(Gtk.ListBoxRow row) {
			var button = row.get_child() as LauncherButton;

			// No search happening, hide everything
			if (search_term == "") {
				return false;
			}

			// Only show this item if its relevancy to the search term
			// is within an arbitrary threshold
			return this.relevancy.is_app_relevant(button.application);
		}

		/**
		 * Sort rows based on their relevancy score.
		 *
		 * Copied from BudgieMenu.
		 */
		int on_sort(Gtk.ListBoxRow row1, Gtk.ListBoxRow row2) {
			LauncherButton btn1 = row1.get_child() as LauncherButton;
			LauncherButton btn2 = row2.get_child() as LauncherButton;

			// Check for an active search
			if (search_term.length > 0) {
				// Get the scores relative to the search term
				int sc1 = this.relevancy.get_score(btn1.application);
				int sc2 = this.relevancy.get_score(btn2.application);

				// The item with the lower score should be higher in the list
				if (sc1 < sc2) {
					return -1;
				} else if (sc1 > sc2) {
					return 1;
				}
				return 0;
			}

			// No active search, just return 0 because nothing will be
			// shown anyways
			return 0;
		}

		/**
		* Be a good citizen and pretend to be a dialog.
		*/
		bool on_key_release(Gdk.EventKey btn) {
			if (btn.keyval == Gdk.Key.Escape) {
				Idle.add(() => {
					this.application.quit();
					return false;
				});
				return Gdk.EVENT_STOP;
			}
			return Gdk.EVENT_PROPAGATE;
		}

		/**
		* Handle startup notification, mark it done, quit
		* We may not get the ID but we'll be told it's launched
		*/
		private void on_launched(AppInfo info, Variant v) {
			debug("on_launched called");
			Variant? elem;

			var iter = v.iterator();

			while ((elem = iter.next_value()) != null) {
				string? key = null;
				Variant? val = null;

				elem.get("{sv}", out key, out val);

				if (key == null) {
					continue;
				}

				if (!val.is_of_type(VariantType.STRING)) {
					continue;
				}

				if (key != "startup-notification-id") {
					continue;
				}
				get_display().notify_startup_complete(val.get_string());
			}
			this.application.quit();
		}

		/**
		* Set the ID if it exists, quit regardless
		*/
		private void on_launch_failed(string id) {
			get_display().notify_startup_complete(id);
			this.application.quit();
		}


		void on_name_owner_changed(string? n, string? o, string? ne) {
			if (o == "") {
				this.active_names[n] = true;
				this.check_dbus_name();
			} else {
				if (n in this.active_names) {
					this.active_names.remove(n);
				}
			}
		}

		/**
		* Check if our dbus name appeared. if it did, bugger off.
		*/
		void check_dbus_name() {
			if (this.wanted_dbus_id != "" && this.wanted_dbus_id in this.active_names) {
				this.application.quit();
			}
		}

		/**
		* Do basic dbus initialisation
		*/
		public async void setup_dbus() {
			try {
				impl = yield Bus.get_proxy(BusType.SESSION, "org.freedesktop.DBus", "/org/freedesktop/DBus");

				/* Cache the names already active */
				foreach (string name in yield impl.list_names()) {
					this.active_names[name] = true;
				}
				/* Watch for new names */
				impl.name_owner_changed.connect(on_name_owner_changed);
			} catch (Error e) {
				warning("Failed to initialise dbus: %s", e.message);
			}
		}
	}

	/**
	* GtkApplication for single instance wonderness
	*/
	public class RunDialogApp : Gtk.Application {
		private RunDialog? rd = null;

		public RunDialogApp() {
			Object(application_id: "org.budgie_desktop.BudgieRunDialog", flags: 0);
		}

		public override void activate() {
			if (rd == null) {
				rd = new RunDialog(this);
			}
			rd.show();
		}
	}
}

public static int main(string[] args) {
	Intl.setlocale(LocaleCategory.ALL, "");
	Intl.bindtextdomain(Budgie.GETTEXT_PACKAGE, Budgie.LOCALEDIR);
	Intl.bind_textdomain_codeset(Budgie.GETTEXT_PACKAGE, "UTF-8");
	Intl.textdomain(Budgie.GETTEXT_PACKAGE);

	Budgie.RunDialogApp rd = new Budgie.RunDialogApp();
	return rd.run(args);
}
