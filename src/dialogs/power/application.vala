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

using GLib;
using Gdk;
using Gtk;

namespace Budgie {
	public class PowerApplication : Gtk.Application {
		private PowerDialog? power_dbus = null;
		private PowerWindow? window = null;

		private bool grabbed = false;

		private ShellShim? shim;

		public PowerApplication() {
			Object(application_id: "org.buddiesofbudgie.PowerDialog", flags: 0);

			/* 	we need a separate process to connect budgie session with our
				endsessiondialog in budgie-daemon via dbus to allow the confirmation dialog
				to be displayed; connecting via the same process introduces a 30sec - 1 min delay
				In v10.9.2 this was budgie_wm.  Under wayland the power app is the replacement choice
			*/
			shim = new ShellShim();
			shim.serve();
		}

		public override void activate() {
			if (window == null) {
				window = new PowerWindow(this);
				window.hide.connect(on_hide);
			}

			if (power_dbus == null) {
				Bus.own_name(
					BusType.SESSION,
					"org.buddiesofbudgie.PowerDialog",
					BusNameOwnerFlags.NONE,
					on_dbus_acquired
				);
			}
		}

		private void on_dbus_acquired(DBusConnection conn) {
			try {
				power_dbus = new PowerDialog();
				conn.register_object("/org/buddiesofbudgie/PowerDialog", power_dbus);
				power_dbus.toggle.connect(on_toggle);
			} catch (Error e) {
				critical("Unable to register PowerDialog DBus: %s", e.message);
			}
		}

		private void on_hide() {
			if (power_dbus == null) return;

			power_dbus.is_showing = false;
		}

		private void on_toggle(bool show) {
			if (window == null) {
				critical("Tried to toggle visibility of PowerDialog, but the window hasn't been initialized");
				return;
			}

			if (!show) {
				ungrab_seat();
				window.hide();
				return;
			}

			this.window.present_with_time(CURRENT_TIME);
			this.window.show_all();
			this.window.reset_focus();

			// We can't grab the seat for this window right after calling present/show
			// because it happens too fast. The seat will fail to grab with `GDK_GRAB_STATUS_NOT_VIEWABLE`.
			Timeout.add(250, () => {
				grab_seat();
				return Source.REMOVE;
			});
		}

		/**
		 * Attempts to grab device input and send it to our dialog window.
		 */
		private void grab_seat() {
			if (window == null) return;

			var display = window.get_display();
			var seat = display.get_default_seat();
			var status = seat.grab(window.get_window(), ALL, true, null, null, null);

			if (status != SUCCESS) {
				warning("Tried to grab seat, but failed: %s", status.to_string());
			}

			grabbed = true;
		}

		/**
		 * Releases a seat grab. If the seat hasn't been grabbed, this function
		 * does nothing.
		 */
		private void ungrab_seat() {
			if (!grabbed || window == null) return;

			var display = window.get_display();
			var seat = display.get_default_seat();

			seat.ungrab();
			grabbed = false;
		}
	}
}
