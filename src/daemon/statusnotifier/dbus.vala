namespace Budgie.StatusNotifier {
	public const string WATCHER_KDE_DBUS_NAME = "org.kde.StatusNotifierWatcher";

	public const string WATCHER_KDE_DBUS_OBJECT_PATH = "/org/kde/StatusNotifierWatcher";
	public const string WATCHER_BASIC_DBUS_OBJECT_PATH = "/StatusNotifierWatcher";

	public struct DBusPathName {
		public string name;
		public string object_path;
	}

	[DBus (name="org.kde.StatusNotifierWatcher")]
	public class Watcher : Object {
		public string[] registered_status_notifier_items {get; private set;}
		public bool is_status_notifier_host_registered {get; private set; default = false;}
		public int32 protocol_version {get; private set; default = 0;}

		private uint dbus_identifier = 0;
		private HashTable<string, uint> host_services;
		private HashTable<string, uint> item_services;
		private HashTable<string, DBusPathName?> item_pathnames;

		construct {
			host_services = new HashTable<string, uint>(str_hash, str_equal);
			item_services = new HashTable<string, uint>(str_hash, str_equal);
			item_pathnames = new HashTable<string, DBusPathName?>(str_hash, str_equal);

			dbus_identifier = Bus.own_name(
				BusType.SESSION,
				WATCHER_KDE_DBUS_NAME,
				BusNameOwnerFlags.NONE,
				null,
				on_dbus_acquired
			);
		}

		~Watcher() {
			if (dbus_identifier != 0) {
				Bus.unown_name(dbus_identifier);
			}

			foreach (uint identifier in host_services.get_values()) {
				Bus.unwatch_name(identifier);
			}
			foreach (string service in item_services.get_keys()) {
				Bus.unwatch_name(item_services.get(service));
				status_notifier_item_unregistered(service);
			}
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
			string path, name;
			if (service[0] == '/') {
				name = (string) sender;
				path = service;
			} else {
				name = service;
				path = "/StatusNotifierItem";
			}

			// we already have this item; ignore the request
			if (item_pathnames.contains(service)) {
				return;
			}

			uint watch_identifier = Bus.watch_name(
				BusType.SESSION,
				name,
				BusNameWatcherFlags.NONE,
				(conn,name,owner)=>{
					warning("Registered item with path=%s, name=%s", path, name);
					status_notifier_item_registered(service);
					status_notifier_item_registered_budgie(name, path);
				},
				(conn,name)=>{
					warning("Unregistered item with path=%s, name=%s", path, name);
					item_services.remove(service);
					item_pathnames.remove(service);
					status_notifier_item_unregistered(service);
					status_notifier_item_unregistered_budgie(name, path);
				}
			);

			item_services.insert(service, watch_identifier);
			item_pathnames.insert(service, {name, path});
		}

		public void register_status_notifier_host(string service) throws DBusError, IOError {
			uint watch_identifier = Bus.watch_name(
				BusType.SESSION,
				service,
				BusNameWatcherFlags.NONE,
				(conn,name,owner)=>{
					warning("Registered status notifier host %s", service);
					is_status_notifier_host_registered = true;
					status_notifier_host_registered();
				},
				(conn,name)=>{
					host_services.remove(service);
					warning("Unregistered status notifier host %s", service);

					if (host_services.get_keys_as_array().length == 0) {
						is_status_notifier_host_registered = false;
					}
				}
			);

			host_services.insert(service, watch_identifier);
		}

		public DBusPathName[] get_registered_status_notifier_pathnames() throws DBusError, IOError {
			DBusPathName[] ret = new DBusPathName[item_pathnames.size()];
			for (int i = 0; i < item_pathnames.size(); i++) {
				ret[i] = item_pathnames.get_values().nth_data(i);
			}
			return ret;
		}

		// these signals are part of the spec
		public signal bool status_notifier_item_registered(string item);
		public signal bool status_notifier_item_unregistered(string item);
		public signal bool status_notifier_host_registered();

		// these signals are specifically for use with budgie
		public signal void status_notifier_item_registered_budgie(string name, string object_path);
		public signal void status_notifier_item_unregistered_budgie(string name, string object_path);
	}
}
