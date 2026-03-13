using Gtk;

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

	[DBus (name = "org.buddiesofbudgie.BudgieScreenshotControl")]
	interface ScreenshotControl : GLib.Object {
		public async abstract void StartMainWindow() throws GLib.Error;
		public async abstract void StartAreaSelect() throws GLib.Error;
		public async abstract void StartWindowScreenshot() throws GLib.Error;
		public async abstract void StartFullScreenshot() throws GLib.Error;
	}

	static bool interactive = false;
	static bool window = false;
	static bool area = false;

	const OptionEntry[] options = {
		{ "interactive", 'i', 0, OptionArg.NONE, ref interactive, "Interactively set options" },
		{ "window", 'w', 0, OptionArg.NONE, ref window, "Grab a window instead of the entire display. This capability only works for compatible window managers." },
		{ "area", 'a', 0, OptionArg.NONE, ref area, "Grab an area of the display instead of the entire display" },
		{ null }
	};

	/* Stored reference for async callbacks */
	static ScreenshotControl? stored_control = null;

	private static void on_start_main_window_ready(Object? obj, AsyncResult res) {
		try {
			stored_control.StartMainWindow.end(res);
		} catch (Error e) {
			message("Failed to StartMainWindow: %s", e.message);
		}
	}

	private static void on_start_area_select_ready(Object? obj, AsyncResult res) {
		try {
			stored_control.StartAreaSelect.end(res);
		} catch (Error e) {
			message("Failed to StartAreaSelect: %s", e.message);
		}
	}

	private static void on_start_window_screenshot_ready(Object? obj, AsyncResult res) {
		try {
			stored_control.StartWindowScreenshot.end(res);
		} catch (Error e) {
			message("Failed to StartWindowScreenshot: %s", e.message);
		}
	}

	private static void on_start_full_screenshot_ready(Object? obj, AsyncResult res) {
		try {
			stored_control.StartFullScreenshot.end(res);
		} catch (Error e) {
			message("Failed to StartFullScreenshot: %s", e.message);
		}
	}

	public static int main(string[] args) {
		ScreenshotControl control;
		OptionContext ctx;
		ctx = new OptionContext("- Budgie Screenshot");
		ctx.set_help_enabled(true);
		ctx.add_main_entries(options, null);

		try {
			ctx.parse(ref args);
		} catch (Error e) {
			stderr.printf("Error: %s\n", e.message);
			return 0;
		}
		try {
			control = GLib.Bus.get_proxy_sync(
				BusType.SESSION, "org.buddiesofbudgie.BudgieScreenshotControl",
				"/org/buddiesofbudgie/ScreenshotControl"
			);

			stored_control = control;

			if (interactive) {
				control.StartMainWindow.begin(on_start_main_window_ready);
				GLib.Thread.usleep(2000); // pause the thread to allow the dbus call to complete
				return 0;
			}
			if (area) {
				control.StartAreaSelect.begin(on_start_area_select_ready);
				GLib.Thread.usleep(2000); // pause the thread to allow the dbus call to complete
				return 0;
			}
			if (window) {
				control.StartWindowScreenshot.begin(on_start_window_screenshot_ready);
				GLib.Thread.usleep(2000); // pause the thread to allow the dbus call to complete
				return 0;
			}

			control.StartFullScreenshot.begin(on_start_full_screenshot_ready);
			GLib.Thread.usleep(2000); // pause the thread to allow the dbus call to complete
			return 0;
		}
		catch (Error e) {
			stderr.printf("%s\n", e.message);
			return 1;
		}
	}
}
