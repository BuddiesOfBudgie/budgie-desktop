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
		private WorkspaceManager workspace_manager;
		private HashTable<libxfce4windowing.Application, WindowGroup> applications;
		private List<Window> fullscreen_windows;
		private libxfce4windowing.Window? last_active_window;

		private Budgie.Windowing.WindowMapper window_mapper;
		private Budgie.Windowing.NotificationDispatcher dispatcher;

		private Settings color_settings;
		private Settings wm_settings;

		private ulong night_light_setting_handler;
		private bool pause_night_light;
		private bool pause_notifications;
		private bool previous_color_setting;

		public bool has_windows { get; private set; }
		public unowned List<libxfce4windowing.Window> windows { get { return screen.get_windows(); } }

		/**
		 * Emitted when the currently active window has changed.
		 */
		public signal void active_window_changed(Window? old_active_window, Window? new_active_window);

		/**
		 * Emitted when the currently active workspace has changed.
		 */
		public signal void active_workspace_changed(Workspace? old_active_workspace);

		/**
		 * Emitted when a WindowGroup has been created.
		 */
		public signal void window_group_added(WindowGroup group);

		/**
		 * Emitted when a WindowGroup has been removed.
		 */
		public signal void window_group_removed(WindowGroup group);

		/**
		 * Emitted when a window is added to the windowing system.
		 */
		public signal void window_added(Window window);
		/**
		 * Emitted when a window is removed from the windowing system.
		 */
		public signal void window_removed(Window window);

		/**
		 * Emitted when the state of a window has changed.
		 */
		public signal void window_state_changed(Window window, WindowState changed_mask, WindowState new_state);

		/**
		 * Emitted when a Workspace has been created.
		 */
		public signal void workspace_created(Workspace workspace);

		/**
		 * Emitted when a Workspace has been destroyed.
		 */
		public signal void workspace_destroyed(Workspace workspace);

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

			window_mapper = new WindowMapper();

			screen = Screen.get_default();

			screen.get_windows().foreach(on_window_added);

			screen.active_window_changed.connect(on_active_window_changed);
			screen.window_opened.connect(on_window_added);
			screen.window_closed.connect(on_window_removed);

			setup_workspace_listener();

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

		/**
		 * Get the first workspace group. X11 has no concept of
		 * workspace groups, so the first one is guaranteed to
		 * be the only one.
		 */
		public WorkspaceGroup? get_workspace_group() {
			unowned var groups = workspace_manager.list_workspace_groups();

			if (groups == null) return null;

			unowned var element = groups.first();

			return element.data as libxfce4windowing.WorkspaceGroup;
		}

		private void setup_workspace_listener() {
			workspace_manager = screen.get_workspace_manager();
			var group = get_workspace_group();

			if (group == null) return;

			group.active_workspace_changed.connect(on_active_workspace_changed);
			group.workspace_added.connect(on_workspace_created);
			group.workspace_removed.connect(on_workspace_destroyed);
		}

		private void on_active_window_changed(Window? old_window) {
			var new_window = screen.get_active_window();

			foreach (var group in applications.get_values()) {
				if (group.has_window(new_window)) {
					group.set_active_window(new_window);
				}

				if (old_window != null && group.has_window(old_window)) {
					group.set_last_active_window(old_window);
				}
			}

			last_active_window = old_window;

			active_window_changed(old_window, new_window);
		}

		private void on_active_workspace_changed(Workspace? previous_workspace) {
			active_workspace_changed(previous_workspace);
		}

		private void on_workspace_created(Workspace workspace) {
			workspace_created(workspace);
		}

		private void on_workspace_destroyed(Workspace workspace) {
			workspace_destroyed(workspace);
		}

		private void on_window_added(Window window) {
			if (window.is_skip_tasklist()) return;
			window_added(window);
			has_windows = true;

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

			var app_info = window_mapper.query_window(window);
			group = new WindowGroup(application, app_info);

			group.add_window(window);
			group.window_state_changed.connect(on_window_state_changed);
			applications.insert(application, group);
			window_group_added(group);
		}

		private void on_window_removed(Window window) {
			has_windows = screen.get_windows().length() > 0;

			if (window.is_skip_tasklist()) return;
			window_removed(window);

			var application = window.get_application();

			// Get the WindowGroup this window belongs to
			var group = applications.lookup(application);
			if (group == null) return;

			// Remove the window from the group
			group.remove_window(window);

			// Remove the window from fullscreen windows, if it happened
			// to be fullscreened
			fullscreen_windows.remove(window);

			// Remove the group if this was the last window
			if (!group.has_windows()) {
				debug(@"removing WindowGroup for application: $(application.get_name())");
				window_group_removed(group);
				applications.remove(application);
			}
		}

		private void on_window_state_changed(Window window, WindowState changed_mask, WindowState new_state) {
			window_state_changed(window, changed_mask, new_state);

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

		/**
		 * Get the currently active window.
		 *
		 * Returns: the active window, or NULL
		 */
		public unowned Window? get_active_window() {
			return screen.get_active_window();
		}

		/**
		 * Get a list of all current #WindowGroups.
		 *
		 * Returns: the list of window groups
		 */
		public List<weak WindowGroup> get_window_groups() {
			return applications.get_values();
		}

		/**
		 * Get the currently active workspace.
		 *
		 * Returns: the active workspace, or NULL
		 */
		public Workspace? get_active_workspace() {
			var group = get_workspace_group();

			if (group == null) return null;

			return group.get_active_workspace();
		}
	}
}
