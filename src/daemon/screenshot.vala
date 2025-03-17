/*
 * This file is part of budgie-desktop
 *
 * Copyright Budgie Desktop Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * Code has been inspired by the elementaryOS Gala ScreenshotManager.vala
 * and the GNOME 42 shell-screenshot.c techniques.
 */


namespace Budgie {
	const string EXTENSION = ".png";
	const string DBUS_SCREENSHOT = "org.buddiesofbudgie.BudgieScreenshot";
	const string DBUS_SCREENSHOT_PATH = "/org/buddiesofbudgie/Screenshot";

	[DBus (name="org.buddiesofbudgie.BudgieScreenshot")]
	public class ScreenshotManager : Object {

		[DBus (visible = false)]
		public ScreenshotManager() {
		}

		[DBus (visible = false)]
		public void serve() {
			/* Hook up screenshot dbus */
			Bus.own_name(BusType.SESSION, DBUS_SCREENSHOT, BusNameOwnerFlags.REPLACE,
				on_bus_acquired,
				() => {},
				() => warning("serve Could not acquire name\n") );
		}

		void on_bus_acquired(DBusConnection conn) {
			try {
				conn.register_object(DBUS_SCREENSHOT_PATH, this);
			} catch (Error e) {
				message("Unable to register Screenshot: %s", e.message);
			}
		}

		/*
		  stub function: we'll populate this for those window managers that support taking screenshots of the focussed window
		*/
		public bool SupportScreenshotWindow() throws DBusError, IOError {
			return false;
		}

		public async void screenshot(bool include_cursor, bool flash, string filename, out bool success, out string filename_used) throws DBusError, IOError {
			success = false;
			filename_used = "";

			try {
				filename_used = take_screenshot( filename, 0, 0, 0, 0, include_cursor);

				if (filename_used != "" ){
					success = true;
				}
			}
			catch {
				throw new DBusError.FAILED("Failed to take the screenshot");
			}
		}

		/*
		  actually take the screenshot and if successful return the filename that was used_filename
		*/
		private string take_screenshot(string filename, int x, int y, int width, int height, bool include_cursor) throws Error {
			string used_filename = filename;
			try {
				string cmd = "grim";
				if (include_cursor) {
					cmd += " -c";
				}

				if (x != 0 || y != 0 || width != 0 || height != 0) {
					cmd += " -g \"%d,%d %dx%d\"".printf(x, y, width, height);
				}

				if (used_filename != "" && !Path.is_absolute(used_filename)) {
					if (!used_filename.has_suffix(EXTENSION)) {
						used_filename = used_filename.concat(EXTENSION);
					}
					var path = Environment.get_tmp_dir();
					used_filename = Path.build_filename(path, used_filename, null);
				}
				cmd += " " + used_filename;
                Process.spawn_command_line_sync(cmd);
				warning("command %s", cmd);
				} catch (SpawnError e) {
					warning("Error: %s\n", e.message);
					used_filename = "";
				}

				return used_filename;
		}

		public async void screenshot_area(int x, int y, int width, int height, bool include_cursor, bool flash, string filename, out bool success, out string filename_used) throws DBusError, IOError {
			success = false;
			filename_used = "";

			try {
				filename_used = take_screenshot( filename, x, y, width, height, include_cursor);

				if (filename_used != "" ){
					success = true;
				}
			}
			catch {
				throw new DBusError.FAILED("Failed to take the screenshot");
			}
		}

		public async void screenshot_window(bool include_frame, bool include_cursor, bool flash, string filename, out bool success, out string filename_used) throws DBusError, IOError {
			throw new DBusError.FAILED("Failed to save image");
		}
	}
}
