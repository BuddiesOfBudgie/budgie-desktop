[DBus (name="org.kde.StatusNotifierWatcher")]
public class StatusNotifierWatcher : Object {
	public string[] registered_status_notifier_items {get; private set;}
	public bool is_status_notifier_host_registered {get; private set; default = true;}
	public int32 protocol_version {get; private set; default = 0;}

	private uint dbus_identifier = 0;
	private DBusConnection? conn = null;
	private HashTable<string, uint> host_services;

	construct {
		host_services = new HashTable<string, uint>(direct_hash, direct_equal);

		dbus_identifier = Bus.own_name(
			BusType.SESSION,
			"org.kde.StatusNotifierWatcher",
			BusNameOwnerFlags.ALLOW_REPLACEMENT|BusNameOwnerFlags.REPLACE,
			null,
			on_dbus_acquired
		);
	}

	~StatusNotifierWatcher() {
		// breaks adding items on panel reinit for some reason
		//  if (dbus_identifier != 0) {
		//  	Bus.unown_name(dbus_identifier);
		//  }

		foreach (uint identifier in host_services.get_values()) {
			Bus.unwatch_name(identifier);
		}
	}

	private void on_dbus_acquired(DBusConnection conn) {
		try {
			conn.register_object("/org/kde/StatusNotifierWatcher", this);
			conn.register_object("/StatusNotifierWatcher", this);
		} catch (Error e) {
			critical("Unable to register status notifier watcher: %s", e.message);
		}
	}

	public void register_status_notifier_item(string service) throws DBusError, IOError {
		warning("Attempted to register item %s", service);

		status_notifier_item_registered(service);
	}

	public void register_status_notifier_host(string service) throws DBusError, IOError {
		warning("Attempted to register host %s", service);

		uint watch_identifier = Bus.watch_name(
			BusType.SESSION,
			service,
			BusNameWatcherFlags.NONE,
			null,
			(conn,name)=>{
				host_services.remove(service);
				warning("Unregistered status notifier host %s", service);
			}
		);

		host_services.set(service, watch_identifier);

		status_notifier_host_registered();
	}

	public signal bool status_notifier_item_registered(string item);
	public signal bool status_notifier_item_unregistered(string item);
	public signal bool status_notifier_host_registered();
}
