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

using GLib;
using Gtk;

namespace Budgie {
	public class PowerApplication : Gtk.Application {
		private PowerDialog? power_dbus = null;
		private PowerWindow? window = null;

		public PowerApplication() {
			Object(application_id: "org.buddiesofbudgie.PowerDialog", flags: 0);
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
			if (power_dbus == null) {
				return;
			}

			power_dbus.is_showing = false;
		}

		private void on_toggle(bool show) {
			if (window == null) {
				critical("Tried to toggle visibility of PowerDialog, but the window hasn't been initialized");
				return;
			}

			if (show) {
				window.present();
				window.show_all();
			} else {
				window.hide();
			}
		}
	}
}
