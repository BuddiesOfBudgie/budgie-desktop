/*
 * This file is part of budgie-desktop
 *
 * Copyright © 2015-2022 Budgie Desktop Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

using Gdk;
using Gtk;

namespace Budgie {
	const string LOGIND_LOGIN = "org.freedesktop.login1";
	const string G_SESSION = "org.gnome.SessionManager";

	/**
	 * This widget is the meat of the application. It contains
	 * a grid of buttons, and handles all of the necessary events.
	 *
	 * There are a few CSS classes to better fascilitate theming:
	 * GtkWindow: budgie-power-dialog
	 *   GtkBox
	 *     GtkGrid: power-button-grid
	 *       DialogButtons: power-dialog-button
	 */
	public class PowerWindow : Gtk.ApplicationWindow {
		private DialogButton? lock_button = null;
		private DialogButton? suspend_button = null;
		private DialogButton? hibernate_button = null;
		private DialogButton? reboot_button = null;
		private DialogButton? shutdown_button = null;
		private DialogButton? logout_button = null;

		private LogindRemote? logind = null;
		private SessionManagerRemote? session_manager = null;
		private ScreensaverRemote? screensaver = null;

		private EventControllerKey? event_controller = null;

		Budgie.ThemeManager? theme_manager = null;

		construct {
			set_keep_above(true);
			set_position(WindowPosition.CENTER);

			var visual = screen.get_rgba_visual();
			if (visual != null) {
				set_visual(visual);
			}

			get_style_context().add_class("budgie-power-dialog");

			theme_manager = new Budgie.ThemeManager();

			setup_dbus.begin();

			// Create our layout
			var header = new EventBox();
			header.get_style_context().remove_class("titlebar");
			set_titlebar(header);

			var box = new Box(Orientation.HORIZONTAL, 0);

			var button_grid = new Grid() {
				column_homogeneous = true,
				row_homogeneous = true,
				column_spacing = 8,
				row_spacing = 8,
				margin = 12
			};
			button_grid.get_style_context().add_class("power-button-grid");

			// Create our buttons
			lock_button = new DialogButton(_("Lock"), "system-lock-screen-symbolic");
			lock_button.clicked.connect(lock_screen);

			logout_button = new DialogButton(_("Log Out"), "system-log-out-symbolic");
			logout_button.clicked.connect(logout);

			suspend_button = new DialogButton(_("Suspend"), "system-suspend-symbolic");
			suspend_button.clicked.connect(suspend);

			hibernate_button = new DialogButton(_("Hibernate"), "system-hibernate-symbolic");
			hibernate_button.clicked.connect(hibernate);

			reboot_button = new DialogButton(_("Reboot"), "system-restart-symbolic");
			reboot_button.clicked.connect(reboot);

			shutdown_button = new DialogButton(_("Shutdown"), "system-shutdown-symbolic");
			shutdown_button.clicked.connect(shutdown);

			// Attach our buttons
			button_grid.attach(lock_button, 0, 0);
			button_grid.attach(logout_button, 1, 0);
			button_grid.attach(suspend_button, 2, 0);
			button_grid.attach(hibernate_button, 0, 1);
			button_grid.attach(reboot_button, 1, 1);
			button_grid.attach(shutdown_button, 2, 1);

			// Attach our grid to the window
			box.pack_start(button_grid, true, true, 0);
			add(box);

			// Connect events
			focus_out_event.connect(() => {
				debug("hiding due to focus_out_event");
				hide();
				return Gdk.EVENT_STOP;
			});

			event_controller = new EventControllerKey(this);
			event_controller.key_released.connect(on_key_release);
		}

		public PowerWindow(Gtk.Application app) {
			Object(
				application: app,
				resizable: false,
				skip_pager_hint: true,
				skip_taskbar_hint: true,
				type_hint: WindowTypeHint.DIALOG
			);
		}

		/**
		 * Set up all of the DBus bits to make all the items work.
		 */
		private async void setup_dbus() {
			try {
				logind = yield Bus.get_proxy(BusType.SYSTEM, LOGIND_LOGIN, "/org/freedesktop/login1");
			} catch (Error e) {
				warning("Unable to connect to logind: %s", e.message);
			}

			try {
				screensaver = yield Bus.get_proxy(BusType.SESSION, "org.gnome.ScreenSaver", "/org/gnome/ScreenSaver");
			} catch (Error e) {
#if HAVE_GNOME_SCREENSAVER
				warning("Unable to connect to gnome-screensaver: %s", e.message);
#else
				warning("Unable to connect to budgie-screensaver: %s", e.message);
#endif
				return;
			}

			try {
				session_manager = yield Bus.get_proxy(BusType.SESSION, G_SESSION, "/org/gnome/SessionManager");
			} catch (Error e) {
				warning("Unable to connect to GNOME Session: %s", e.message);
			}
		}

		/**
		 * Handles key release events.
		 */
		private void on_key_release(uint keyval, uint keycode, ModifierType state) {
			// Right now, we only care about hiding when ESC is pressed
			if (keyval != Key.Escape) {
				return;
			}

			hide();
		}

		private void logout() {
			hide();
			if (session_manager == null) {
				return;
			}

			Idle.add(() => {
				try {
					session_manager.Logout(0);
				} catch (Error e) {
					warning("Failed to logout: %s", e.message);
				}
				return false;
			});
		}

		private void hibernate() {
			hide();
			if (logind == null) {
				return;
			}

			Idle.add(() => {
				try {
					lock_screen();
					logind.hibernate(false);
				} catch (Error e) {
					warning("Cannot hibernate: %s", e.message);
				}
				return false;
			});
		}

		private void reboot() {
			hide();
			if (session_manager == null) {
				return;
			}

			Idle.add(() => {
				session_manager.Reboot.begin();
				return false;
			});
		}

		private void shutdown() {
			hide();
			if (session_manager == null) {
				return;
			}

			Idle.add(() => {
				session_manager.Shutdown.begin();
				return false;
			});
		}

		private void suspend() {
			hide();
			if (logind == null) {
				return;
			}

			Idle.add(() => {
				try {
					lock_screen();
					logind.suspend(false);
				} catch (Error e) {
					warning("Cannot suspend: %s", e.message);
				}
				return false;
			});
		}

		private void lock_screen() {
			hide();
			Idle.add(() => {
				try {
#if HAVE_GNOME_SCREENSAVER
					if (screensaver == null) { // attempt to connect to dbus if not started previously
						screensaver = Bus.get_proxy_sync(BusType.SESSION, "org.gnome.ScreenSaver", "/org/gnome/ScreenSaver");
					}
#endif
					screensaver.lock();
				} catch (Error e) {
					warning("Cannot lock screen: %s", e.message);
#if HAVE_GNOME_SCREENSAVER
					screensaver = null; // allow another retry to lock the screen on a failure
#endif
				}
				return false;
			});
		}
	}
}
