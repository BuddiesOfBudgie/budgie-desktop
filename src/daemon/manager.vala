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

	/*
	 The underlying WaylandClient does not appear to be fully thread-safe and either
	 repeated calls very quickly, or calls within the same process where the
	 reference was not release will result in mutex-locks causing the daemon to spin
	 indefinitely.

	 Our use in the daemon is limited so we can initialise variable we use within
	 a singleton to make things thread-safe.
	 */
	[SingleInstance]
	public class WaylandClient : GLib.Object {
		private unowned libxfce4windowing.Monitor? primary_monitor=null;

		public bool is_initialised() { return primary_monitor != null; }
		public unowned Gdk.Monitor gdk_monitor {get; private set; }
		public Gdk.Rectangle monitor_res { get; private set; }

		public WaylandClient() {
			if (primary_monitor != null) return;
			libxfce4windowing.Screen.get_default().monitors_changed.connect(on_monitors_changed);
			on_monitors_changed();
		}

		void on_monitors_changed() {
			int loop = 0;

			/* it can take a short-time after first call for the underlying wayland client
			   to return a reference, so lets loop until we get a reference ... but
			   don't try indefinitely
			*/
			Timeout.add(200, ()=> {
				primary_monitor = libxfce4windowing.Screen.get_default().get_primary_monitor();
				if (primary_monitor != null || loop++ > 10) {
					monitor_res = primary_monitor.get_logical_geometry();
					gdk_monitor = primary_monitor.get_gdk_monitor();
					return false;
				}

				return true;
			});
		}
	}
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
		BudgieScr.ScreenshotServer? screenshotcontrol;
		Budgie.XDGDirTracker? xdg_tracker;
		Budgie.Background? background;

		/* Screenlock */
		Budgie.Screenlock? screenlock;

		/* NightLight */
		Budgie.NightLightManager? nightlight;

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
			osdkeys = new Budgie.OSDKeys();

			notifications = new Budgie.Notifications.Server();
			notifications.setup_dbus(replace);

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

			nightlight = new NightLightManager();

			Budgie.KeyboardManager.init();
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
