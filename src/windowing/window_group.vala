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
	 * This object represnts a group of windows belonging to the same
	 * application.
	 */
	public class WindowGroup : GLib.Object {
		/** The libxfce4windowing.Application that this group belongs to. */
		public libxfce4windowing.Application application { get; construct; }

		/** A copy of the application's ID. */
		public uint64 group_id { get; construct; }

		public DesktopAppInfo? app_info { get; construct; default = null; }

		private List<unowned libxfce4windowing.Window> windows;
		private unowned libxfce4windowing.Window? active_window = null;
		private unowned libxfce4windowing.Window? last_active_window = null;

		/**
		 * Emitted when the icon of the application for this group changes.
		 */
		public signal void app_icon_changed();

		/**
		 * Emitted when the state of a window in this group changes.
		 */
		public signal void window_state_changed(libxfce4windowing.Window window, libxfce4windowing.WindowState changed_mask, libxfce4windowing.WindowState new_state);

		/**
		 * Emitted when a window has been added to this group.
		 */
		public signal void window_added(libxfce4windowing.Window window);

		/**
		 * Emitted when a window has been removed from this group.
		 */
		public signal void window_removed(libxfce4windowing.Window window);

		/**
		 * Create a new WindowGroup for an application.
		 */
		public WindowGroup(libxfce4windowing.Application application, DesktopAppInfo? app_info) {
			Object(application: application, group_id: application.get_id(), app_info: app_info);
		}

		construct {
			windows = new List<unowned libxfce4windowing.Window>();

			application.icon_changed.connect(icon_changed);
		}

		private void icon_changed() {
			app_icon_changed();
		}

		private void state_changed(libxfce4windowing.Window window, libxfce4windowing.WindowState changed_mask, libxfce4windowing.WindowState new_state) {
			window_state_changed(window, changed_mask, new_state);
		}

		/**
		 * Adds a window to this WindowGroup.
		 */
		public void add_window(libxfce4windowing.Window window) {
			debug(@"adding window to group '$(application.get_name())': $(window.get_name())");

			window.state_changed.connect(state_changed);

			windows.append(window);
			window_added(window);
		}

		/**
		 * Removed a window from this WindowGroup, typically when the window
		 * has been closed.
		 */
		public void remove_window(libxfce4windowing.Window window) {
			debug(@"removing window from group '$(application.get_name())': $(window.get_name())");
			windows.remove(window);
			window_removed(window);
		}

		/**
		 * Get the desktop ID of this application.
		 *
		 * Returns: the desktop ID of the application
		 */
		 public string get_desktop_id() {
			return "%s.desktop".printf(application.get_name());
		}

		/**
		 * Get the currently active window in this group if
		 * one is active.
		 *
		 * Returns: the currently active window, or NULL
		 */
		 public unowned libxfce4windowing.Window? get_active_window() {
			return active_window;
		}

		/**
		 * Get the last active window in this group.
		 *
		 * Returns: the last active window, or NULL
		 */
		public unowned libxfce4windowing.Window? get_last_active_window() {
			return last_active_window;
		}

		/**
		 * Get the first opened window in this group.
		 *
		 * Returns: the first opened window or null
		 */
		public libxfce4windowing.Window? get_first_window() {
			unowned var first = windows.first();
			if (first == null) return null;
			return first.data;
		}

		/**
		 * Get the icon for this window group.
		 *
		 * Returns: the icon if found for the given size and scale
		 */
		public Gdk.Pixbuf? get_icon(int size, int scale) {
			return application.get_icon(size, scale);
		}

		/**
		 * Get the open windows in this group.
		 *
		 * Returns: a list of open windows
		 */
		public List<unowned libxfce4windowing.Window> get_windows() {
			return windows.copy();
		}

		/**
		 * Checks whether or not the given window is in this group.
		 *
		 * Returns: true if the window is in this window group
		 */
		public bool has_window(libxfce4windowing.Window window) {
			return windows.find(window) != null;
		}

		/**
		 * Checks whether or not this group still has any open windows.
		 *
		 * Returns: true if there are open windows
		 */
		public bool has_windows() {
			debug(@"window group '$(application.get_name()) has $(windows.length()) windows in it");
			return windows.length() > 0;
		}

		/**
		 * Set the currently active window.
		 */
		public void set_active_window(libxfce4windowing.Window? window) {
			active_window = window;
		}

		/**
		 * Set the previously active window.
		 */
		public void set_last_active_window(libxfce4windowing.Window? window) {
			last_active_window = window;
		}
	}
}
