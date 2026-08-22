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
	public const string KEYBOARD_LAYOUT_DBUS_NAME = "org.buddiesofbudgie.BudgieKeyboardLayout";
	public const string KEYBOARD_LAYOUT_DBUS_PATH = "/org/buddiesofbudgie/KeyboardLayout";

	/**
	 * KeyboardLayoutManager is exposed on the session bus as a proxy
	 * between the keyboard layout applet and whichever compositor bridge is
	 * running (labwc, wayfire, ...).
	 *
	 * The applet calls SetKeyboardLayout() to request a layout change.
	 *  N.B. Its th compositor's responsibility via the its bridge to
	 *  set the keyboard layout.
	 */
	[DBus (name = "org.buddiesofbudgie.BudgieKeyboardLayout")]
	public class KeyboardLayoutManager : GLib.Object {

		[DBus (visible = false)]
		public KeyboardLayoutManager() {
		}

		[DBus (visible = false)]
		public void setup_dbus(bool replace) {
			var flags = BusNameOwnerFlags.ALLOW_REPLACEMENT;
			if (replace) flags |= BusNameOwnerFlags.REPLACE;
			Bus.own_name(BusType.SESSION, KEYBOARD_LAYOUT_DBUS_NAME, flags,
				on_bus_acquired, () => {}, Budgie.DaemonNameLost);
		}

		private void on_bus_acquired(DBusConnection conn) {
			try {
				conn.register_object(KEYBOARD_LAYOUT_DBUS_PATH, this);
				debug("KeyboardLayoutManager: registered on DBus");
			} catch (Error e) {
				critical("KeyboardLayoutManager: failed to register: %s", e.message);
			}
		}

		// ------------------------------------------------------------------ //
		// DBus methods
		// ------------------------------------------------------------------ //

		/**
		 * Called by the keyboard layout applet (or any other client) to
		 * request a change of the active XKB keyboard layout, e.g. "us,gb".
		 */
		public void set_keyboard_layout(string layout) throws DBusError, IOError {
			debug("KeyboardLayoutManager.SetKeyboardLayout requested: %s", layout);
			layout_changed(layout);
		}

		// ------------------------------------------------------------------ //
		// DBus signals
		// ------------------------------------------------------------------ //

		/** Broadcast to any listening compositor bridge that a layout change has been requested. */
		public signal void layout_changed(string layout);
	}
}
