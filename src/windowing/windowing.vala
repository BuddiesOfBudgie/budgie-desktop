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

using libxfce4windowing;

namespace Budgie.Windowing {

	private const string NOTIFICATIONS_DBUS_NAME = "org.budgie_desktop.Notifications";
	private const string NOTIFICATIONS_DBUS_OBJECT_PATH = "/org/budgie_desktop/Notifications";

	/**
	 * This object keeps track of WindowGroups. It serves as the main part
	 * of the Budgie windowing library.
	 */
	public class Windowing : GLib.Object {
		private libxfce4windowing.Screen screen;
		private HashTable<libxfce4windowing.Application, WindowGroup> applications;
		private List<Window> fullscreen_windows;

		private Budgie.Windowing.NotificationDispatcher dispatcher;

		private Settings color_settings;
		private Settings wm_settings;

		private ulong night_light_setting_handler;
		private bool pause_night_light;
		private bool pause_notifications;
		private bool previous_color_setting;

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
			color_settings = new Settings("org.gnome.settings-daemon.plugins.color");
			wm_settings = new Settings("com.solus-project.budgie-wm");

			Bus.get_proxy.begin<Budgie.Windowing.NotificationDispatcher>(
				BusType.SESSION,
				NOTIFICATIONS_DBUS_NAME,
				NOTIFICATIONS_DBUS_OBJECT_PATH,
				DBusProxyFlags.NONE,
				null,
				on_dbus_get
			);

			applications = new HashTable<libxfce4windowing.Application, WindowGroup>(direct_hash, direct_equal);
			fullscreen_windows = new List<Window>();

			screen = Screen.get_default();

			screen.get_windows().foreach(window_added);

			screen.window_opened.connect(window_added);
			screen.window_closed.connect(window_removed);

			// Get the current night light setting and watch for changes
			previous_color_setting = color_settings.get_boolean("night-light-enabled");
			night_light_setting_handler = color_settings.changed["night-light-enabled"].connect(night_light_enabled_changed);

			// Get the current WM settings and watch for changes
			pause_night_light = wm_settings.get_boolean("disable-night-light-on-fullscreen");
			pause_notifications = wm_settings.get_boolean("pause-notifications-on-fullscreen");
			wm_settings.changed["disable-night-light-on-fullscreen"].connect(wm_settings_changed);
			wm_settings.changed["pause-notifications-on-fullscreen"].connect(wm_settings_changed);
		}

		private void on_dbus_get(Object? object, AsyncResult? result) {
			try {
				dispatcher = Bus.get_proxy.end(result);
			} catch (GLib.Error e) {
				critical("Error getting notification dispatcher: %s", e.message);
			}
		}

		private void window_added(Window window) {
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
			group.window_state_changed.connect(window_state_changed);
			applications.insert(application, group);
			window_group_added(group);
		}

		private void window_removed(Window window) {
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

			// Remove the window from fullscreen windows, if it happened
			// to be fullscreened
			fullscreen_windows.remove(window);

			// Remove the group if this was the last window
			if (!group.has_windows()) {
				debug(@"removing WindowGroup for application: $(application.get_name())");
				applications.remove(application);
				window_group_removed(group);
			}
		}

		private void window_state_changed(Window window, WindowState changed_mask, WindowState new_state) {
			// Check if fullscreen state changed
			if (!(WindowState.FULLSCREEN in changed_mask)) return;

			// Check if the window is fullscreen
			var is_fullscreen = (WindowState.FULLSCREEN in new_state) && !(WindowState.MINIMIZED in new_state || WindowState.SHADED in new_state);

			debug(@"window '$(window.get_name())' fullscreen changed: is fullscreen = $is_fullscreen");

			// Handle the state change with regard to night light and notifications
			handle_fullscreen_changed(is_fullscreen);

			// Remove this window from the list if it was fullscreen, but is no longer
			if (!is_fullscreen) {
				fullscreen_windows.remove(window);
				return;
			}

			// Add this window to the list of fullscreen windows
			fullscreen_windows.append(window);
		}

		private void handle_fullscreen_changed(bool fullscreen) {
			// Block the setting signal handler for night light
			SignalHandler.block(color_settings, night_light_setting_handler);

			if (fullscreen) {
				// Pause night light
				if (pause_night_light) {
					color_settings.set_boolean("night-light-enabled", false);
				}
				// Pause notifications
				if (pause_notifications) {
					dispatcher.notifications_paused = true;
				}
			} else {
				// Reset the night light setting
				if (pause_night_light) {
					color_settings.set_boolean("night-light-enabled", previous_color_setting);
				}
				// Unpause notifications
				if (pause_notifications) {
					dispatcher.notifications_paused = false;
				}
			}

			// Unblock the setting signal handler for night light
			SignalHandler.unblock(color_settings, night_light_setting_handler);
		}

		private void night_light_enabled_changed(string key) {
			previous_color_setting = color_settings.get_boolean(key);
		}

		private void wm_settings_changed(string key) {
			switch (key) {
				case "disable-night-light-on-fullscreen":
					pause_night_light = wm_settings.get_boolean(key);
					break;
				case "pause-notifications-on-fullscreen":
					pause_notifications = wm_settings.get_boolean(key);
					break;
				default:
					warning("Unknown setting changed: %s", key);
					break;
			}
		}
	}
}
