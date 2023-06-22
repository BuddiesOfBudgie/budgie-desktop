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

namespace Budgie.Windowing {
	/**
	 * This object keeps track of WindowGroups. It serves as the main part
	 * of the Budgie windowing library.
	 */
	public class Windowing : GLib.Object {
		private libxfce4windowing.Screen screen;
		private HashTable<libxfce4windowing.Application, WindowGroup> applications;

		/**
		 * Emitted when a WindowGroup has been created.
		 */
		public signal void window_group_added(WindowGroup group);

		/**
		 * Emitted when a WindowGroup has been removed.
		 */
		public signal void window_group_removed(WindowGroup group);

		/**
		 * Creates a new Windowing object. This is the entry point into
		 * this library.
		 */
		public Windowing() {
			Object();
		}

		construct {
			applications = new HashTable<libxfce4windowing.Application, WindowGroup>(direct_hash, direct_equal);
			screen = libxfce4windowing.Screen.get_default();

			screen.get_windows().foreach(window_added);

			screen.window_opened.connect(window_added);
			screen.window_closed.connect(window_removed);
		}

		private void window_added(libxfce4windowing.Window window) {
			if (window.is_skip_tasklist()) return;

			var application = window.get_application();

			// Check if this application is already open
			var group = applications.lookup(application);
			if (group != null) {
				// Group already exists, add this window to it and bail
				group.add_window(window);
				return;
			}

			// Not already open, create a new group
			debug(@"creating new WindowGroup for application: $(application.get_name())");
			group = new WindowGroup(application);
			group.add_window(window);
			applications.insert(application, group);
			window_group_added(group);
		}

		private void window_removed(libxfce4windowing.Window window) {
			if (window.is_skip_tasklist()) return;

			var application = window.get_application();

			// Get the WindowGroup this window belongs to
			var group = applications.lookup(application);
			if (group == null) {
				warning("A window was closed, but we could not find its WindowGroup");
				return;
			}

			// Remove the window from the group
			group.remove_window(window);

			// Remove the group if this was the last window
			if (!group.has_windows()) {
				debug(@"removing WindowGroup for application: $(application.get_name())");
				applications.remove(application);
				window_group_removed(group);
			}
		}
	}
}
