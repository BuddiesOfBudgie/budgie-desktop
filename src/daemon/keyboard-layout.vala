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
	public const string KEYBOARD_LAYOUT_DBUS_NAME = "org.buddiesofbudgie.KeyboardLayout";
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
	[DBus (name = "org.buddiesofbudgie.KeyboardLayout")]
	public class KeyboardLayoutManager : GLib.Object {
		private DBusConnection? connection = null;

		/**
		 * The XKB layout currently in use, e.g. "fi". Set by the compositor
		 * bridge once it has applied a layout change.
		 */
		public string current_layout { get; set; default = ""; }

		[DBus (visible = false)]
		public KeyboardLayoutManager() {
			notify["current-layout"].connect(on_current_layout_notify);
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
				connection = conn;
				debug("KeyboardLayoutManager: registered on DBus");
			} catch (Error e) {
				critical("KeyboardLayoutManager: failed to register: %s", e.message);
			}
		}

		/**
		 * valac does not emit PropertiesChanged for exported properties, so
		 * clients watching CurrentLayout need us to emit it ourselves.
		 */
		private void on_current_layout_notify() {
			if (connection == null) return;

			var changed = new VariantBuilder(new VariantType("a{sv}"));
			changed.add("{sv}", "CurrentLayout", new Variant.string(current_layout));

			try {
				connection.emit_signal(null, KEYBOARD_LAYOUT_DBUS_PATH,
					"org.freedesktop.DBus.Properties", "PropertiesChanged",
					new Variant.tuple({
						new Variant.string(KEYBOARD_LAYOUT_DBUS_NAME),
						changed.end(),
						new Variant.strv({})
					}));
			} catch (Error e) {
				warning("KeyboardLayoutManager: failed to emit PropertiesChanged: %s", e.message);
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

		/**
		 * Called by the keyboard layout shortcuts. The bridge holds the order of
		 * the configured layouts, so it picks which one the move lands on.
		 */
		public void switch_layout_next() throws DBusError, IOError {
			debug("KeyboardLayoutManager.SwitchLayoutNext requested");
			switch_layout_next_requested();
		}

		public void switch_layout_previous() throws DBusError, IOError {
			debug("KeyboardLayoutManager.SwitchLayoutPrevious requested");
			switch_layout_previous_requested();
		}

		// ------------------------------------------------------------------ //
		// DBus signals
		// ------------------------------------------------------------------ //

		/** Broadcast to any listening compositor bridge that a layout change has been requested. */
		public signal void layout_changed(string layout);

		/** Broadcast to any listening compositor bridge that the next layout has been requested. */
		public signal void switch_layout_next_requested();

		/** Broadcast to any listening compositor bridge that the previous layout has been requested. */
		public signal void switch_layout_previous_requested();
	}
}
