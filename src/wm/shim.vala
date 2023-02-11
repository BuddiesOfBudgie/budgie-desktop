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
	public struct GsdAccel {
		string accelerator;
		uint flags;
		Meta.KeyBindingFlags grab_flags;
	}

	[DBus (name="org.gnome.SessionManager.EndSessionDialog")]
	public class SessionHandler : GLib.Object {
		public signal void ConfirmedLogout();
		public signal void ConfirmedReboot();
		public signal void ConfirmedShutdown();
		public signal void Canceled();
		public signal void Closed();

		private EndSessionDialog? proxy = null;

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
			Bus.get_proxy.begin<EndSessionDialog>(BusType.SESSION, "org.budgie_desktop.Session.EndSessionDialog", "/org/budgie_desktop/Session/EndSessionDialog", 0, null, on_dialog_get);
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

	/**
	* Wrap the EndSessionDialog type inside Budgie itself
	*/
	[DBus (name="org.budgie_desktop.Session.EndSessionDialog")]
	public interface EndSessionDialog : GLib.Object {
		public signal void ConfirmedLogout();
		public signal void ConfirmedReboot();
		public signal void ConfirmedShutdown();
		public signal void Canceled();
		public signal void Closed();

		public abstract void Open(uint type, uint timestamp, uint open_length, ObjectPath[] inhibiters) throws DBusError, IOError;

		public abstract void Close() throws DBusError, IOError;
	}

	/**
	* Expose the BudgieOSD functionality for proxying of the Shell OSD Functionality
	*/
	[DBus (name="org.budgie_desktop.BudgieOSD")]
	public interface BudgieOSD : GLib.Object {
		/**
		* Budgie GTK+ On Screen Display
		*
		* Valid params:
		*   icon: string
		*   label: string
		*   level: int32
		*   monitor: int32
		*/
		public abstract async void ShowOSD(HashTable<string,Variant> params) throws DBusError, IOError;
	}

	[DBus (name="org.gnome.Shell")]
	public class ShellShim : GLib.Object {
		HashTable<string,uint?> grabs;
		unowned Meta.Display? display;

		private SessionHandler? handler = null;

		/* Proxy off the OSD Calls */
		private BudgieOSD? osd_proxy = null;
		private unowned BudgieWM? wm = null;

		[DBus (visible=false)]
		public ShellShim(Budgie.BudgieWM? _wm) {
			grabs = new HashTable<string,uint?>(str_hash, str_equal);
			wm = _wm;

			display = wm.get_display();
			display.accelerator_activated.connect(on_accelerator_activated);

			handler = new SessionHandler();

			Bus.watch_name(BusType.SESSION, "org.budgie_desktop.BudgieOSD",
				BusNameWatcherFlags.NONE, has_osd_proxy, lost_osd_proxy);
		}

		/**
		* BudgieOSD known to be present, now try to get the proxy
		*/
		void on_osd_proxy_get(Object? o, AsyncResult? res) {
			try {
				osd_proxy = Bus.get_proxy.end(res);
			} catch (Error e) {
				osd_proxy = null;
			}
		}

		/**
		* BudgieOSD appeared, schedule a proxy-get
		*/
		void has_osd_proxy() {
			if (osd_proxy  != null) {
				return;
			}
			Bus.get_proxy.begin<BudgieOSD>(BusType.SESSION, "org.budgie_desktop.BudgieOSD", "/org/budgie_desktop/BudgieOSD", 0, null, on_osd_proxy_get);
		}

		/**
		* BudgieOSD disappeared, drop the reference
		*/
		void lost_osd_proxy() {
			osd_proxy = null;
		}

		private void on_accelerator_activated(uint action, Clutter.InputDevice dev, uint timestamp) {
			foreach (string accelerator in grabs.get_keys()) {
				if (grabs[accelerator] == action) {
					var params = new HashTable<string,Variant>(null, null);
					params.set("device-name", new Variant.string(dev.get_device_name()));
					params.set("action-mode", new Variant.uint32(action));
					params.set("device-mode", new Variant.string(dev.get_device_node()));
					params.set("timestamp", new Variant.uint32(timestamp));
					this.accelerator_activated(action, params);
				}
			}
		}

		public uint grab_accelerator(string accelerator, Meta.KeyBindingFlags flags) throws DBusError, IOError {
			uint? action = grabs[accelerator];

			if (action == null) {
				action = display.grab_accelerator(accelerator, flags);
				if (action > 0) {
					grabs[accelerator] = action;
				}
			}

			return action;
		}

		public uint[] grab_accelerators(GsdAccel[] accelerators) throws DBusError, IOError {
			uint[] actions = {};

			foreach (unowned GsdAccel? accelerator in accelerators) {
				actions += grab_accelerator(accelerator.accelerator, accelerator.grab_flags);
			}

			return actions;
		}

		public bool ungrab_accelerator(uint action) throws DBusError, IOError {
			bool ret = false;
			var keys = grabs.get_keys();
			foreach (unowned string accelerator in keys) {
				if (grabs[accelerator] == action) {
					ret = display.ungrab_accelerator(action);
					grabs.remove(accelerator);
					break;
				}
			}

			return ret;
		}

		void on_bus_acquired(DBusConnection conn) {
			try {
				conn.register_object("/org/gnome/Shell", this);
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

		public uint GrabAccelerator(BusName sender, string accelerator, uint flags, Meta.KeyBindingFlags grab_flags) throws DBusError, IOError {
			return grab_accelerator(accelerator, grab_flags);
		}

		public uint[] GrabAccelerators(BusName sender, GsdAccel[] accelerators) throws DBusError, IOError {
			return grab_accelerators(accelerators);
		}

		public bool UngrabAccelerator(BusName sender, uint action) throws DBusError, IOError {
			return ungrab_accelerator(action);
		}

		public bool UngrabAccelerators(BusName sender, uint[] actions) throws DBusError, IOError {
			foreach (uint action in actions) {
				ungrab_accelerator(action);
			}
			return true;
		}

		/**
		* Show the OSD when requested.
		*/
		public void ShowOSD(HashTable<string,Variant> params) throws DBusError, IOError {
			if (osd_proxy != null) {
				osd_proxy.ShowOSD.begin(params);
			}
		}

		public signal void accelerator_activated(uint action, HashTable<string,Variant> parameters);
	}
}
