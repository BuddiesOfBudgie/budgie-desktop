/*
 * This file is part of budgie-desktop
 *
 * Copyright (C) 2017-2022 taaem <taaem@mailbox.org>
 * Copyright (C) 2017-2022 Budgie Desktop Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

namespace Budgie {
	/**
	* Our name on the session bus. Reserved for Budgie use
	*/
	public const string SCREENSHOTCLIENT_DBUS_NAME = "org.budgie_desktop.ScreenshotClient";

	/**
	* Unique object path on SWITCHER_DBUS_NAME
	*/
	public const string SCREENSHOTCLIENT_DBUS_OBJECT_PATH = "/org/budgie_desktop/ScreenshotClient";

	/**
	* ScreenshotClient is responsible for managing the client-side calls over d-bus, receiving
	* requests, for example, from budgie-wm
	*/
	[DBus (name="org.budgie_desktop.ScreenshotClient")]
	public class ScreenshotClient : GLib.Object {
		//private ScreenshotClientWindow? screenshotclient_window = null;
		private uint32 mod_timeout = 0;

		[DBus (visible=false)]
		public ScreenshotClient() {
			//screenshotclient_window = new TabSwitcherWindow();
		}

		/**
		* Own the SWITCHER_DBUS_NAME
		*/
		[DBus (visible=false)]
		public void setup_dbus(bool replace) {
			var flags = BusNameOwnerFlags.ALLOW_REPLACEMENT;
			if (replace) {
				flags |= BusNameOwnerFlags.REPLACE;
			}
			Bus.own_name(BusType.SESSION, Budgie.SCREENSHOTCLIENT_DBUS_NAME, flags,
				on_bus_acquired, ()=> {}, Budgie.DaemonNameLost);
		}

		/**
		* Acquired SWITCHER_DBUS_NAME, register ourselves on the bus
		*/
		private void on_bus_acquired(DBusConnection conn) {
			try {
				conn.register_object(Budgie.SCREENSHOTCLIENT_DBUS_OBJECT_PATH, this);
			} catch (Error e) {
				stderr.printf("Error registering ScreenshotClient: %s\n", e.message);
			}
			Budgie.setup = true;
		}

		//public void StopSwitcher() throws DBusError, IOError {
		//	switcher_window.stop_switching();
		//}
        public async void ScreenshotClientArea() throws DBusError, IOError {
            message("calling screenshotclientarea");
        }
	}
}
