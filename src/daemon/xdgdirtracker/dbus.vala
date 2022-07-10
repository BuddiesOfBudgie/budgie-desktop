/*
 * This file is part of budgie-desktop
 *
 * Copyright © 2022 Buddies of Budgie
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

namespace Budgie {
	public const string TRACKER_DBUS_NAME = "org.buddiesofbudgie.XDGDirTracker";
	public const string TRACKER_DBUS_OBJECT_PATH = "/org/buddiesofbudgie/XDGDirTracker";

	[DBus (name="org.buddiesofbudgie.XDGDirTracker")]
	public class XDGDirTracker: Object {
		public UserDirectory[] dirs = {};
		private File? home_dir_file;
		private FileMonitor? home_dir_monitor;
		private const UserDirectory[] xdg_dirs = {UserDirectory.DESKTOP, UserDirectory.DOCUMENTS, UserDirectory.DOWNLOAD, UserDirectory.MUSIC, UserDirectory.PICTURES, UserDirectory.VIDEOS};

		// The only signal the presentation layer should need. Presentation layer should handle deletes, creates, etc.
		public signal void xdg_dirs_exist(UserDirectory[] dirs);

		[DBus (visible=false)]
		public XDGDirTracker() {
			try {
				home_dir_file = File.new_for_path(Environment.get_home_dir()); // Get our home directory
				home_dir_monitor = home_dir_file.monitor_directory(FileMonitorFlags.NONE, null); // Monitor our home directory primarily for validation of XDG changes
				home_dir_monitor.changed.connect(on_homedir_changed);
			} catch (Error e) {
				warning("Failed to create our XDGDirTracker: %s", e.message);
			}
		}

		[DBus (visible=true)]
		public UserDirectory[] get_dirs() throws Error {
			return dirs;
		}

		[DBus (visible=false)]
		public void setup_dbus(bool replace) {
			var flags = BusNameOwnerFlags.ALLOW_REPLACEMENT;
			if (replace) {
				flags |= BusNameOwnerFlags.REPLACE;
			}
			Bus.own_name(BusType.SESSION, Budgie.TRACKER_DBUS_NAME, flags,
				on_dbus_acquired, ()=> {}, Budgie.DaemonNameLost);
		}

		private void on_dbus_acquired(DBusConnection conn) {
			try {
				conn.register_object(Budgie.TRACKER_DBUS_OBJECT_PATH, this);
				on_homedir_changed(); // Trigger our change immediately
			} catch (Error e) {
				stderr.printf("Error registering our XDGDirTracker: %s\n", e.message);
			}
		}

		// We don't care about all the changes, only that our XDG dirs do or don't exist.
		private void on_homedir_changed() {
			UserDirectory[] existing_xdgs = {}; // Create an array of the paths of the existing XDG dirs

			for (var i = 0; i < xdg_dirs.length; i++) { // For each directory
				UserDirectory xdg_dir = xdg_dirs[i];
				unowned string? path = Environment.get_user_special_dir(xdg_dir);

				if (path == null) {
					continue; // Skip this since the logical ID does not exist
				}

				File xdg_file = File.new_for_path(path); // Get the file
				try {
					FileInfo? info = xdg_file.query_info("standard::*", 0); // Get the file info (if this is a symlink, it follows it - this does not seem to actually query info for it correctly though)

					if (info == null) {
						continue;
					}

					FileType t = info.get_file_type();
					if (t == FileType.DIRECTORY) { // Is a directory and does exist
						existing_xdgs += xdg_dir; // Add this directory
					} else if (t == FileType.SYMBOLIC_LINK) { // Is a symlink
						string? symlink_target = info.get_symlink_target();

						if (symlink_target == null) {
							continue;
						}

						File sym_file = File.new_for_path(symlink_target); // Get the file
						if (!sym_file.query_exists()) { // Does not exist
							continue;
						}

						existing_xdgs += xdg_dir; // Add this directory
					}
				} catch (Error e) {
					warning("Failed to get file info for %s: %s", path, e.message);
				}
			}

			if (dirs == null || dirs.length == 0) { // Dirs not set yet
				update_xdgs(existing_xdgs);
				return;
			}

			if (dirs.length != existing_xdgs.length) { // Different lengths
				update_xdgs(existing_xdgs);
				return;
			}

			for (var i = 0; i < existing_xdgs.length; i++) { // For each item
				UserDirectory path = existing_xdgs[i]; // Get the path
				UserDirectory existing_entry = dirs[i];

				if (path != existing_entry) { // If the path doesn't match, which either means the path changed or we have a different XDG dir (for example Desktop is removed, Pictures added)
					update_xdgs(existing_xdgs);
					return;
				}
			}
		}

		private void update_xdgs(UserDirectory[] xdgs) {
			dirs = xdgs; // Set our private dirs to the XDG ones
			xdg_dirs_exist(dirs); // Invoke our signal
		}
	}
}