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

/**
 * Trivial helper for IconTasklist - i.e. desktop lookups
 */
public class DesktopHelper : GLib.Object {
	private Wnck.Screen? screen = null;
	private Gtk.Box? icon_layout = null;

	/* Panel specifics */
	public int panel_size = 40;
	public int icon_size = 32;
	public Gtk.Orientation orientation = Gtk.Orientation.HORIZONTAL;
	public Budgie.PanelPosition panel_position = Budgie.PanelPosition.BOTTOM;

	/* Preferences */
	public bool lock_icons = false;

	/**
	 * Handle initial bootstrap of the desktop helper
	 */
	public DesktopHelper(Gtk.Box? icon_layout) {
		/* Stash privates */
		this.icon_layout = icon_layout;

		/* Stash lifetime reference to screen */
		this.screen = Wnck.Screen.get_default();
	}

	public const Gtk.TargetEntry[] targets = {
		{ "application/x-icon-tasklist-launcher-id", 0, 0 },
		{ "text/uri-list", 0, 0 },
		{ "application/x-desktop", 0, 0 },
	};

	/**
	 * Return the currently active window
	 */
	public Wnck.Window get_active_window() {
		return screen.get_active_window();
	}

	/**
	 * Return the currently active workspace
	 */
	public Wnck.Workspace get_active_workspace() {
		return screen.get_active_workspace();
	}

	/**
	 * get_app_launcher will return the last past of an app_id string. Useful when handling the full path to a DesktopAppInfo
	 */
	public string get_app_launcher(string app_id) {
		string[] parts = app_id.split("/");
		return parts[parts.length - 1];
	}
}
