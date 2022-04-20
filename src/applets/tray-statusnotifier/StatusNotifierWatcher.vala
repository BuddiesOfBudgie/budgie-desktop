[DBus (name="org.freedesktop.StatusNotifierWatcher")]
public class StatusNotifierWatcher : Object {
	public string[] registered_status_notifier_items {get; private set;}
	public bool is_status_notifier_host_registered {get; private set; default = true;}
	public int32 protocol_version {get; private set; default = 0;}

	private uint identifier = 0;

	construct {
		Bus.own_name(
			BusType.SESSION,
			"org.freedesktop.StatusNotifierWatcher",
			BusNameOwnerFlags.ALLOW_REPLACEMENT|BusNameOwnerFlags.REPLACE,
			null,
			on_dbus_acquired
		);
	}

	~StatusNotifierWatcher() {
		if (identifier != 0) {
			Bus.unown_name(identifier);
		}
	}

	private void on_dbus_acquired(DBusConnection conn) {
		try {
			conn.register_object("/org/freedesktop/StatusNotifierWatcher", this);
			conn.register_object("/org/kde/StatusNotifierWatcher", this);
			conn.register_object("/StatusNotifierWatcher", this);
		} catch (Error e) {
			critical("Unable to register status notifier watcher: %s", e.message);
		}
	}

	public void register_status_notifier_item(string service) throws DBusError, IOError {
		warning("Attempted to register service %s", service);
	}

	public void register_status_notifier_host(string service) throws DBusError, IOError {
		warning("Attempted to register host %s", service);
	}

	public signal bool status_notifier_item_registered(string item);
	public signal bool status_notifier_item_unregistered(string item);
	public signal bool status_notifier_host_registered();
}
