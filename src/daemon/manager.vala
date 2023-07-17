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
	* Main lifecycle management, handle all the various session and GTK+ bits
	*/
	public class ServiceManager : GLib.Object {
		private Budgie.ThemeManager theme_manager;
		/* Keep track of our SessionManager */
		private LibSession.SessionClient? sclient;

		/* On Screen Display */
		Budgie.OSDManager? osd;
		Budgie.Notifications.Server? notifications;
		Budgie.StatusNotifier.FreedesktopWatcher? status_notifier;
		Budgie.MenuManager? menus;
		Budgie.TabSwitcher? switcher;
		BudgieScr.ScreenshotServer? screenshotcontrol;
		Budgie.XDGDirTracker? xdg_tracker;

		/**
		* Construct a new ServiceManager and initialiase appropriately
		*/
		public ServiceManager(bool replace) {
			theme_manager = new Budgie.ThemeManager();
			if (use_status_notifier()) status_notifier = new Budgie.StatusNotifier.FreedesktopWatcher();
			register_with_session.begin((o, res) => {
				bool success = register_with_session.end(res);
				if (!success) {
					message("Failed to register with Session manager");
				}
			});
			osd = new Budgie.OSDManager();
			osd.setup_dbus(replace);
			notifications = new Budgie.Notifications.Server();
			notifications.setup_dbus(replace);
			menus = new Budgie.MenuManager();
			menus.setup_dbus(replace);
			switcher = new Budgie.TabSwitcher();
			switcher.setup_dbus(replace);

			try {
				screenshotcontrol = new BudgieScr.ScreenshotServer();
				screenshotcontrol.setup_dbus();
			} catch (Error e) {
				warning("ServiceManager %s\n", e.message);
			}
			xdg_tracker = new Budgie.XDGDirTracker();
			xdg_tracker.setup_dbus(replace);
		}

		/**
		* Attempt registration with the Session Manager
		*/
		private async bool register_with_session() {
			sclient = yield LibSession.register_with_session("budgie-daemon");

			if (sclient == null) {
				return false;
			}

			sclient.QueryEndSession.connect(() => {
				end_session(false);
			});
			sclient.EndSession.connect(() => {
				end_session(false);
			});
			sclient.Stop.connect(() => {
				end_session(true);
			});
			return true;
		}

		/**
		* Properly shutdown when asked to
		*/
		private void end_session(bool quit) {
			if (quit) {
				Gtk.main_quit();
				return;
			}
			try {
				sclient.EndSessionResponse(true, "");
			} catch (Error e) {
				warning("Unable to respond to session manager! %s", e.message);
			}
		}
	}

	bool use_status_notifier () {
		/**
		* Check which applets are installed. Return false only if AppIndicator applet
		* is installed and System Tray isn't. Return true for all other scenarios.
		*/
		bool appindicator_installed = false;
		bool systray_installed = false;
		string panel_schema = "com.solus-project.budgie-panel";
		string panel_path = "/com/solus-project/budgie-panel";
		GLib.Settings? panel_settings = new GLib.Settings(panel_schema);
		foreach (string panel in panel_settings.get_strv("panels")) {
			string curr_panel_path = @"$panel_path/panels/{$panel}/";
			GLib.Settings? curr_panel_subject_settings = new GLib.Settings.with_path(@"$panel_schema.panel", curr_panel_path);
			foreach (string app in curr_panel_subject_settings.get_strv("applets")) {
				string curr_apppath = @"$panel_path/applets/{$app}/";
				GLib.Settings? curr_app_settings = new GLib.Settings.with_path(@"$panel_schema.applet", curr_apppath);
				string name = curr_app_settings.get_string("name");
				if (name == "AppIndicator Applet") appindicator_installed = true;
				if (name == "System Tray") systray_installed = true;
			}
		}
		return (systray_installed || !appindicator_installed);
	}
}
