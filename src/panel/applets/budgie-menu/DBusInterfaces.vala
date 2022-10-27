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

[DBus (name="org.freedesktop.Accounts")]
interface AccountsRemote : Object {
	public abstract string find_user_by_name(string username) throws DBusError, IOError;
}

[DBus (name="org.freedesktop.Accounts.User")]
interface AccountUserRemote : Object {
	public signal void changed();
}

[DBus (name="org.freedesktop.DBus.Properties")]
interface PropertiesRemote : Object {
	public abstract Variant get(string interface, string property) throws DBusError, IOError;
	public signal void properties_changed();
}

/* logind */
[DBus (name="org.freedesktop.login1.Manager")]
public interface LogindRemote : Object {
	public abstract void suspend(bool interactive) throws DBusError, IOError;
	public abstract void hibernate(bool interactive) throws DBusError, IOError;
}

[DBus (name="org.gnome.SessionManager")]
public interface SessionManagerRemote : Object {
	public abstract void Logout(uint mode) throws DBusError, IOError;
	public abstract async void Reboot() throws Error;
	public abstract async void Shutdown() throws Error;
}

[DBus (name="org.gnome.ScreenSaver")]
public interface ScreenSaverRemote : GLib.Object {
	public abstract void lock() throws Error;
}

/* Budgie */

[DBus (name="org.buddiesofbudgie.XDGDirTracker")]
public interface XDGDirTrackerRemote : GLib.Object {
	public abstract UserDirectory[] get_dirs() throws Error;
	public signal void xdg_dirs_exist(UserDirectory[] dirs);
}