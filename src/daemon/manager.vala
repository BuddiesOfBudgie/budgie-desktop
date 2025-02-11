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
		Budgie.Background? background;

		/* Screenlock */
		Budgie.Screenlock? screenlock;
		/**
		* Construct a new ServiceManager and initialiase appropriately
		*/
		public ServiceManager(bool replace) {
			theme_manager = new Budgie.ThemeManager();
			status_notifier = new Budgie.StatusNotifier.FreedesktopWatcher();
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
			background = new Budgie.Background();

			try {
				screenshotcontrol = new BudgieScr.ScreenshotServer();
				screenshotcontrol.setup_dbus();
			} catch (Error e) {
				warning("ServiceManager %s\n", e.message);
			}
			xdg_tracker = new Budgie.XDGDirTracker();
			xdg_tracker.setup_dbus(replace);


			screenlock = Screenlock.init();
			screenlock.setup_dbus();
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
}
