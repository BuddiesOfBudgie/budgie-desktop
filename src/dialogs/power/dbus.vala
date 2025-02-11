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

namespace Budgie {
	[DBus (name="org.buddiesofbudgie.PowerDialog")]
	public class PowerDialog : Object {
		public bool is_showing { get; set; default = false; }

		public signal void toggle(bool show);

		public void Toggle() throws DBusError, IOError {
			is_showing = !is_showing;
			toggle(is_showing);
		}
	}

	/* logind */
	[DBus (name="org.freedesktop.login1.Manager")]
	public interface LogindRemote : Object {
		public abstract string can_hibernate() throws DBusError, IOError;

		public abstract void suspend(bool interactive) throws DBusError, IOError;
		public abstract void hibernate(bool interactive) throws DBusError, IOError;
	}

	[DBus (name="org.gnome.SessionManager")]
	public interface SessionManagerRemote : Object {
		public abstract void Logout(uint mode) throws DBusError, IOError;
		public abstract async void Reboot() throws Error;
		public abstract async void Shutdown() throws Error;
	}

	[DBus (name="org.buddiesofbudgie.BudgieScreenlock")]
	public interface ScreensaverRemote : GLib.Object {
		public abstract void lock() throws Error;
	}
}
