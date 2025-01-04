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
	[DBus (name="org.budgie_desktop.Session.EndSessionDialog")]
	public interface EndSessionRemote : GLib.Object {
		public abstract signal void ConfirmedLogout();
		public abstract signal void ConfirmedReboot();
		public abstract signal void ConfirmedShutdown();
		public abstract signal void Canceled();
		public abstract signal void Closed();
		public abstract void Open(uint type, uint timestamp, uint open_length, ObjectPath[] inhibiters) throws Error;
		public abstract void Close() throws Error;
	}

	[DBus (name="org.gnome.SessionManager.EndSessionDialog")]
	public class SessionHandler : GLib.Object {
		public signal void ConfirmedLogout();
		public signal void ConfirmedReboot();
		public signal void ConfirmedShutdown();
		public signal void Canceled();
		public signal void Closed();

		private EndSessionRemote? proxy = null;

		public SessionHandler() {
			Bus.watch_name(BusType.SESSION, "org.budgie_desktop.Session.EndSessionDialog",
				BusNameWatcherFlags.NONE, has_dialog, lost_dialog);
		}

		void on_dialog_get(Object? o, AsyncResult? res) {
			try {
				proxy = Bus.get_proxy.end(res);
				proxy.ConfirmedLogout.connect(() => {
					this.ConfirmedLogout();
				});
				proxy.ConfirmedReboot.connect(() => {
					this.ConfirmedReboot();
				});
				proxy.ConfirmedShutdown.connect(() => {
					this.ConfirmedShutdown();
				});
				proxy.Canceled.connect(() => {
					this.Canceled();
				});
				proxy.Closed.connect(() => {
					this.Closed();
				});
			} catch (Error e) {
				proxy = null;
			}
		}

		void has_dialog() {
			if (proxy != null) {
				return;
			}
			Bus.get_proxy.begin<EndSessionRemote>(BusType.SESSION, "org.budgie_desktop.Session.EndSessionDialog", "/org/budgie_desktop/Session/EndSessionDialog", 0, null, on_dialog_get);
		}

		void lost_dialog() {
			proxy = null;
		}

		public void Open(uint type, uint timestamp, uint open_length, ObjectPath[] inhibiters) throws DBusError, IOError {
			if (proxy == null) {
				return;
			}
			try {
				proxy.Open(type, timestamp, open_length, inhibiters);
			} catch (Error e) {
				message(e.message);
			}
		}

		public void Close() throws DBusError, IOError {
			if (proxy == null) {
				try {
					proxy.Close();
				} catch (Error e) {
					message(e.message);
				}
			}
		}
	}

	[DBus (name="org.gnome.Shell")]
	public class ShellShim : GLib.Object {
		private SessionHandler? handler = null;

		[DBus (visible=false)]
		public ShellShim() {
			handler = new SessionHandler();
		}

		void on_bus_acquired(DBusConnection conn) {
			try {
				conn.register_object("/org/gnome/SessionManager/EndSessionDialog", handler);
			} catch (Error e) {
				message("Unable to register ShellShim: %s", e.message);
			}
		}

		[DBus (visible=false)]
		public void serve() {
			Bus.own_name(BusType.SESSION, "org.gnome.Shell",
				BusNameOwnerFlags.ALLOW_REPLACEMENT|BusNameOwnerFlags.REPLACE,
				on_bus_acquired, null, null);
		}
	}
}