/*
 * This file is part of budgie-desktop
 *
 * Copyright © 2022 Budgie Desktop Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

/**
 * Represents an application that can be ran.
 */
public class Application : Object {
	public string name { get; construct set; }
	public string description { get; private set; default = ""; }
	public string desktop_id { get; construct set; }
	public string exec { get; private set; }
	public string[] keywords { get; private set;}
	public Icon icon { get; private set; default = new ThemedIcon("application-default-icon"); }
	public string desktop_path { get; private set; }
	public string categories { get; private set; }
	public string generic_name { get; private set; default = ""; }
	public bool prefers_default_gpu { get; private set; default = false; }

	/**
	 * Create a new application from a `DesktopAppInfo`.
	 */
	public Application(DesktopAppInfo app_info) {
		this.name = app_info.get_display_name();
		this.description = app_info.get_description() ?? name;
		this.exec = app_info.get_commandline();
		this.desktop_id = app_info.get_id();
		this.desktop_path = app_info.get_filename();
		this.keywords = app_info.get_keywords();
		this.categories = app_info.get_categories();
		this.generic_name = app_info.get_generic_name();
		this.prefers_default_gpu = !app_info.get_boolean("PrefersNonDefaultGPU");

		// Try to get an icon from the desktop file
		var desktop_icon = app_info.get_icon();
		if (desktop_icon != null) {
			// Make sure we have a usable icon
			unowned var theme = Gtk.IconTheme.get_default();
			if (theme.lookup_by_gicon(this.icon, 64, Gtk.IconLookupFlags.USE_BUILTIN) != null) {
				this.icon = desktop_icon;
			}
		}
	}

	/**
	 * Launch this application.
	 *
	 * Returns `true` if the application launched successfully,
	 * otherwise `false`.
	 */
	public bool launch() {
		try {
			var info = new DesktopAppInfo(this.desktop_id);
			/*
			 * appinfo.launch has difficulty running pkexec
			 * based apps so lets spawn an async process instead
			 */
			var cmd = info.get_commandline();
			string[] args = {};
			const string checkstr = "pkexec";

			// Check if the start command contains pkexec
			if (cmd.contains(checkstr)) {
				// Split the command into args
				args = cmd.split(" ");
			}

			// Check if the first command element is pkexec
			if (args.length >= 2 && args[0] == checkstr) {
				// Spawn a new async process to start the application
				string[] env = Environ.get();
				Pid child_pid;
				Process.spawn_async(
					"/",
					args,
					env,
					SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
					null,
					out child_pid
				);
				ChildWatch.add(child_pid, (pid, status) => {
					Process.close_pid(pid);
				});
			} else {
				// No pkexec, use the DesktopAppInfo to launch the app
				new DesktopAppInfo(this.desktop_id).launch(null, null);
			}
		} catch (Error e) {
			warning("Failed to launch application '%s': %s", name, e.message);
			return false;
		}

		return true;
	}
}
