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
	 *   GtkBox: background, drop-shadow
	 *     GtkGrid: power-button-grid
	 *       DialogButtons: power-dialog-button
	 */
	public class PowerWindow : Gtk.ApplicationWindow {
		private DialogButton? lock_button = null;
		private DialogButton? suspend_button = null;
#if WITH_HIBERNATE
		private DialogButton? hibernate_button = null;
#endif
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
			set_position(WindowPosition.CENTER_ALWAYS);

			var visual = screen.get_rgba_visual();
			if (visual != null) {
				set_visual(visual);
			}

			get_style_context().add_class("budgie-power-dialog");

			theme_manager = new Budgie.ThemeManager();

			setup_dbus.begin();

			// Nuke the header
			var header = new EventBox();
			header.get_style_context().remove_class("titlebar");
			set_titlebar(header);

			// Create our layout
			var box = new Box(Orientation.HORIZONTAL, 0) {
				halign = Align.CENTER,
				valign = Align.CENTER
			};

			var button_grid = new Grid() {
				column_homogeneous = true,
				row_homogeneous = true,
				column_spacing = 8,
				row_spacing = 8,
				margin = 12,
				halign = Align.CENTER,
				hexpand = false,
				valign = Align.CENTER,
				vexpand = false
			};
			button_grid.get_style_context().add_class("power-button-grid");

			// Create our buttons
			lock_button = new DialogButton(_("_Lock"), "system-lock-screen-symbolic");
			lock_button.clicked.connect(lock_screen);

			logout_button = new DialogButton(_("L_og Out"), "system-log-out-symbolic");
			logout_button.clicked.connect(logout);

			suspend_button = new DialogButton(_("_Suspend"), "system-suspend-symbolic");
			suspend_button.clicked.connect(suspend);

#if WITH_HIBERNATE
			hibernate_button = new DialogButton(_("_Hibernate"), "system-hibernate-symbolic");
			hibernate_button.clicked.connect(hibernate);
#endif

			reboot_button = new DialogButton(_("_Reboot"), "system-reboot-symbolic");
			reboot_button.clicked.connect(reboot);

			shutdown_button = new DialogButton(_("Shut_down"), "system-shutdown-symbolic");
			shutdown_button.clicked.connect(shutdown);

			// Attach our buttons
			button_grid.attach(lock_button, 0, 0, 2, 2);
			button_grid.attach(logout_button, 2, 0, 2, 2);
			button_grid.attach(suspend_button, 4, 0, 2, 2);
#if WITH_HIBERNATE
			button_grid.attach(hibernate_button, 0, 2, 2, 2);
			button_grid.attach(reboot_button, 2, 2, 2, 2);
			button_grid.attach(shutdown_button, 4, 2, 2, 2);
#else
			button_grid.attach(reboot_button, 1, 2, 2, 2);
			button_grid.attach(shutdown_button, 3, 2, 2, 2);
#endif

			// Attach our grid to the window
			box.pack_start(button_grid, true, false, 0);
			add(box);

			// Connect events
			button_release_event.connect((event) => {
				// We only care about primary mouse clicks
				if (event.button != BUTTON_PRIMARY) return EVENT_PROPAGATE;

				// Get the allocation of the button box
				Allocation allocation;
				box.get_allocation(out allocation);

				// Check if the click was inside the box
				if (event.x >= allocation.x && event.x <= (allocation.x + allocation.width)) {
					if (event.y >= allocation.y && event.y <= (allocation.y + allocation.height)) {
						return EVENT_PROPAGATE;
					}
				}

				// The event was not inside the box, hide the window
				debug("hiding due to button_release_event");
				hide();
				return EVENT_STOP;
			});

			focus_out_event.connect(() => {
				debug("hiding due to focus_out_event");
				hide();
				return Gdk.EVENT_STOP;
			});

#if WITH_HIBERNATE
			show.connect(() => {
				var can_hibernate = can_hibernate();
				hibernate_button.sensitive = can_hibernate;
				hibernate_button.set_tooltip_markup(can_hibernate ? null : _("This system does not support hibernation."));
			});
#endif

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
				screensaver = yield Bus.get_proxy(BusType.SESSION, "org.buddiesofbudgie.BudgieScreenlock", "/org/buddiesofbudgie/Screenlock");
			} catch (Error e) {
				warning("Unable to connect to budgie-screenlock: %s", e.message);
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
			if (keyval != Key.Escape) return;

			hide();
		}

		/**
		 * Gives keyboard focus back to the lock button.
		 */
		public void reset_focus() {
			lock_button.grab_focus();
		}

		private void logout() {
			hide();
			if (session_manager == null) return;

			Idle.add(() => {
				try {
					session_manager.Logout(0);
				} catch (Error e) {
					warning("Failed to logout: %s", e.message);
				}
				return false;
			});
		}

#if WITH_HIBERNATE
		private bool can_hibernate() {
			var can_hibernate = true;
			try {
				can_hibernate = logind.can_hibernate() == "yes";
			} catch (Error e) {
				warning("Failed to check if hibernation is supported: %s", e.message);
			}
			return can_hibernate;
		}

		private void hibernate() {
			hide();
			if (logind == null) return;

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
#endif

		private void reboot() {
			hide();
			if (session_manager == null) return;

			Idle.add(() => {
				session_manager.Reboot.begin();
				return false;
			});
		}

		private void shutdown() {
			hide();
			if (session_manager == null) return;

			Idle.add(() => {
				session_manager.Shutdown.begin();
				return false;
			});
		}

		private void suspend() {
			hide();
			if (logind == null) return;

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
					screensaver.lock();
				} catch (Error e) {
					warning("Cannot lock screen: %s", e.message);
				}
				return false;
			});
		}
	}
}
