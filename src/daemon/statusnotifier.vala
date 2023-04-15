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

namespace Budgie.StatusNotifier {
	public const string WATCHER_FREEDESKTOP_DBUS_NAME = "org.freedesktop.StatusNotifierWatcher";
	public const string WATCHER_KDE_DBUS_NAME = "org.kde.StatusNotifierWatcher";

	public const string WATCHER_FREEDESKTOP_DBUS_OBJECT_PATH = "/org/freedesktop/StatusNotifierWatcher";
	public const string WATCHER_KDE_DBUS_OBJECT_PATH = "/org/kde/StatusNotifierWatcher";
	public const string WATCHER_BASIC_DBUS_OBJECT_PATH = "/StatusNotifierWatcher";

	public struct DBusServiceInfo {
		public string name;
		public string object_path;
		public string sender;
		public string owner;
	}

	[DBus (name="org.freedesktop.StatusNotifierWatcher")]
	public class FreedesktopWatcher : Object {
		public bool is_status_notifier_host_registered {get; private set; default = false;}
		public int32 protocol_version {get; private set; default = 0;}

		private KdeWatcher kde_watcher;
		private uint freedesktop_dbus_identifier = 0;
		private uint host_dbus_identifier;
		private HashTable<string, uint> host_services;
		private HashTable<string, uint> item_watchers;
		private HashTable<string, DBusServiceInfo?> registered_services;

		public string[] registered_status_notifier_items {
			owned get {
				string[] ret = {};
				foreach (DBusServiceInfo val in registered_services.get_values()) {
				    ret += val.name;
				}
				return ret;
			}
		}

		construct {
			host_services = new HashTable<string, uint>(str_hash, str_equal);
			item_watchers = new HashTable<string, uint>(str_hash, str_equal);
			registered_services = new HashTable<string, DBusServiceInfo?>(str_hash, str_equal);

			host_dbus_identifier = Bus.own_name(
				BusType.SESSION,
				"org.freedesktop.StatusNotifierHost-budgie_daemon",
				BusNameOwnerFlags.ALLOW_REPLACEMENT|BusNameOwnerFlags.REPLACE,
				null,
				(conn,name) => {
					freedesktop_dbus_identifier = Bus.own_name(
						BusType.SESSION,
						WATCHER_FREEDESKTOP_DBUS_NAME,
						BusNameOwnerFlags.NONE,
						null,
						on_dbus_acquired
					);
				}
			);

			kde_watcher = new KdeWatcher(this);
		}

		~FreedesktopWatcher() {
			kde_watcher.unref();

			if (freedesktop_dbus_identifier != 0) Bus.unown_name(freedesktop_dbus_identifier);
			if (host_dbus_identifier != 0) Bus.unown_name(host_dbus_identifier);

			foreach (uint identifier in host_services.get_values()) {
				Bus.unwatch_name(identifier);
			}
			foreach (string service in item_watchers.get_keys()) {
				Bus.unwatch_name(item_watchers.get(service));
			}
		}

		private void on_dbus_acquired(DBusConnection conn) {
			try {
				register_status_notifier_host("org.freedesktop.StatusNotifierHost-budgie_daemon");
				conn.register_object(WATCHER_FREEDESKTOP_DBUS_OBJECT_PATH, this);
				conn.register_object(WATCHER_BASIC_DBUS_OBJECT_PATH, this);
			} catch (Error e) {
				critical("Unable to register status notifier watcher: %s", e.message);
			}
		}

		public void register_status_notifier_item(string service, BusName sender) throws DBusError, IOError {
			string name, object_path;
			if (service[0] == '/') {
				name = (string) sender;
				object_path = service;
			} else {
				name = service;
				object_path = "/StatusNotifierItem";
			}

			// we already have this service; ignore the request
			if (name in item_watchers) return;

			var sender_str = (string) sender;
			uint watch_identifier = Bus.watch_name(
				BusType.SESSION,
				name,
				BusNameWatcherFlags.NONE,
				(conn,name,owner) => {
					var service_key = object_path + sender_str + name;
					warning("Received register request for item with service=%s, path=%s, name=%s, sender=%s, owner=%s", service, object_path, name, sender_str, owner);
					if (!registered_services.contains(service_key)) {
						warning("Registering item with service=%s, path=%s, name=%s, sender=%s, owner=%s", service, object_path, name, sender_str, owner);
						registered_services.set(service_key, {name, object_path, sender_str, owner});
						status_notifier_item_registered(name);
						status_notifier_item_registered_budgie(name, object_path, sender_str, owner);
						kde_watcher.status_notifier_item_registered(name);
					}
				},
				(conn,name) => {
					warning("Received unregister request for item with service=%s, path=%s, name=%s, sender=%s", service, object_path, name, sender_str);
					var service_key = object_path + sender_str + name;
					if (registered_services.contains(service_key)) {
						warning("Unregistering item with service=%s, path=%s, name=%s, sender=%s", service, object_path, name, sender_str);
						registered_services.remove(service_key);
						status_notifier_item_unregistered(name);
						status_notifier_item_unregistered_budgie(name, object_path, sender_str);
						kde_watcher.status_notifier_item_unregistered(name);
					}

				}
			);

			item_watchers.insert(name, watch_identifier);
		}

		public void register_status_notifier_host(string service) throws DBusError, IOError {
			uint watch_identifier = Bus.watch_name(
				BusType.SESSION,
				service,
				BusNameWatcherFlags.NONE,
				(conn,name,owner) => {
					warning("Registered status notifier host %s", service);
					is_status_notifier_host_registered = true;
					status_notifier_host_registered();
				},
				(conn,name) => {
					host_services.remove(service);
					warning("Unregistered status notifier host %s", service);

					is_status_notifier_host_registered = host_services.get_keys_as_array().length != 0;
				}
			);

			host_services.insert(service, watch_identifier);
		}

		public DBusServiceInfo[] get_registered_status_notifier_pathnames_budgie() throws DBusError, IOError {
			DBusServiceInfo[] ret = {};
			foreach (DBusServiceInfo val in registered_services.get_values()) {
				ret += val;
			}
			return ret;
		}

		// these signals are part of the spec
		public signal bool status_notifier_item_registered(string item);
		public signal bool status_notifier_item_unregistered(string item);
		public signal bool status_notifier_host_registered();

		// these signals are specifically for use with budgie
		public signal void status_notifier_item_registered_budgie(string name, string object_path, string sender, string owner);
		public signal void status_notifier_item_unregistered_budgie(string name, string object_path, string owner);
	}

	[DBus (name="org.kde.StatusNotifierWatcher")]
	public class KdeWatcher : Object {
		private unowned FreedesktopWatcher parent;
		private uint kde_dbus_identifier = 0;

		public string[] registered_status_notifier_items {
			owned get { return parent.registered_status_notifier_items; }
		}
		public bool is_status_notifier_host_registered {
			get { return parent.is_status_notifier_host_registered; }
		}
		public int32 protocol_version {
			get { return parent.protocol_version; }
		}

		public KdeWatcher(FreedesktopWatcher parent) {
			this.parent = parent;
			parent.status_notifier_item_registered.connect((item) => status_notifier_item_registered(item));
			parent.status_notifier_item_unregistered.connect((item) => status_notifier_item_unregistered(item));
			parent.status_notifier_host_registered.connect(() => status_notifier_host_registered());

			kde_dbus_identifier = Bus.own_name(
				BusType.SESSION,
				WATCHER_KDE_DBUS_NAME,
				BusNameOwnerFlags.NONE,
				null,
				on_dbus_acquired
			);
		}

		~KdeWatcher() {
			if (kde_dbus_identifier != 0) Bus.unown_name(kde_dbus_identifier);
		}

		private void on_dbus_acquired(DBusConnection conn) {
			try {
				conn.register_object(WATCHER_KDE_DBUS_OBJECT_PATH, this);
				conn.register_object(WATCHER_BASIC_DBUS_OBJECT_PATH, this);
			} catch (Error e) {
				critical("Unable to register status notifier watcher: %s", e.message);
			}
		}

		public void register_status_notifier_item(string service, BusName sender) throws DBusError, IOError {
			parent.register_status_notifier_item(service, sender);
		}

		public void register_status_notifier_host(string service) throws DBusError, IOError {
			parent.register_status_notifier_host(service);
		}

		public signal bool status_notifier_item_registered(string item);
		public signal bool status_notifier_item_unregistered(string item);
		public signal bool status_notifier_host_registered();
	}
}
