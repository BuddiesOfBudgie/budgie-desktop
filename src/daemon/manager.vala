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

		// define a reference to WaylandClient once for this process
		private WaylandClient wayland_client = new WaylandClient();

		/* On Screen Display */
		Budgie.OSDManager? osd;
		Budgie.OSDKeys? osdkeys;
		Budgie.Notifications.Server? notifications;
		Budgie.StatusNotifier.FreedesktopWatcher? status_notifier;
		Budgie.XDGDirTracker? xdg_tracker;
		Budgie.Background? background;

		/* Screenlock */
		Budgie.Screenlock? screenlock;

		/* NightLight */
		Budgie.NightLightManager? nightlight;

		/* screenshot */
		ScreenshotManager? screenshot_manager;

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

			// Set up OSD service first
			debug("ServiceManager: Creating OSDManager...");
			osd = new Budgie.OSDManager();
			osd.setup_dbus(replace);

			// Wait for OSD to be ready before creating OSDKeys
			osd.ready.connect(() => {
				debug("ServiceManager: OSDManager ready, creating OSDKeys");
				osdkeys = new Budgie.OSDKeys();
			});

			notifications = new Budgie.Notifications.Server();
			notifications.setup_dbus(replace);

			background = new Budgie.Background();

			xdg_tracker = new Budgie.XDGDirTracker();
			xdg_tracker.setup_dbus(replace);


			screenlock = Screenlock.init();
			screenlock.setup_dbus();

			nightlight = new NightLightManager();

			screenshot_manager = new ScreenshotManager();
			screenshot_manager.serve();
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
