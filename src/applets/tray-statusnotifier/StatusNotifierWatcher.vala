[DBus (name="org.kde.StatusNotifierItem")]
private interface StatusNotifierItem : Object {
	public abstract string category {owned get;}
	public abstract string id {owned get;}
	public abstract string title {owned get;}
	public abstract string status {owned get;}
	public abstract uint32 window_id {owned get;}
	public abstract string icon_name {owned get;}
	public abstract Variant icon_pixmap {owned get;}
	public abstract string overlay_icon_name {owned get;}
	public abstract Variant overlay_icon_pixmap {owned get;}
	public abstract string attention_icon_name {owned get;}
	public abstract Variant attention_icon_pixmap {owned get;}
	public abstract string attention_movie_name {owned get;}
	public abstract Variant tool_tip {owned get;}
	public abstract bool item_is_menu {owned get;}
	public abstract Variant menu {owned get;}

	public abstract void context_menu(int x, int y) throws DBusError, IOError;
	public abstract void activate(int x, int y) throws DBusError, IOError;
	public abstract void secondary_activate(int x, int y) throws DBusError, IOError;
	public abstract void scroll(int delta, string orientation) throws DBusError, IOError;

	public abstract signal void new_title();
	public abstract signal void new_icon();
	public abstract signal void new_attention_icon();
	public abstract signal void new_overlay_icon();
	public abstract signal void new_tool_tip();
	public abstract signal void new_status();
}

[DBus (name="org.kde.StatusNotifierWatcher")]
public class StatusNotifierWatcher : Object {
	public string[] registered_status_notifier_items {get; private set;}
	public bool is_status_notifier_host_registered {get; private set; default = true;}
	public int32 protocol_version {get; private set; default = 0;}

	private uint dbus_identifier = 0;
	private HashTable<string, uint> host_services;
	private HashTable<string, uint> item_services;

	construct {
		host_services = new HashTable<string, uint>(str_hash, str_equal);
		item_services = new HashTable<string, uint>(str_hash, str_equal);

		dbus_identifier = Bus.own_name(
			BusType.SESSION,
			"org.kde.StatusNotifierWatcher",
			BusNameOwnerFlags.NONE,
			null,
			on_dbus_acquired
		);
	}

	~StatusNotifierWatcher() {
		if (dbus_identifier != 0) {
			Bus.unown_name(dbus_identifier);
		}

		foreach (uint identifier in host_services.get_values()) {
			Bus.unwatch_name(identifier);
		}
		foreach (uint identifier in item_services.get_values()) {
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

	public void register_status_notifier_item(string service, BusName sender) throws DBusError, IOError {
		string path, name;
		if (service[0] == '/') {
			path = service;
			name = (string) sender;
		} else {
			path = "/StatusNotifierItem";
			name = service;
		}

		uint watch_identifier = Bus.watch_name(
			BusType.SESSION,
			name,
			BusNameWatcherFlags.NONE,
			(conn,name,owner)=>{
				warning("Registered item with path=%s, name=%s", path, name);
				status_notifier_item_registered(service);
			},
			(conn,name)=>{
				warning("Unregistered item with path=%s, name=%s", path, name);
				item_services.remove(path + name);
				status_notifier_item_unregistered(service);
			}
		);

		item_services.set(path + name, watch_identifier);
	}

	public void register_status_notifier_host(string service) throws DBusError, IOError {
		uint watch_identifier = Bus.watch_name(
			BusType.SESSION,
			service,
			BusNameWatcherFlags.NONE,
			(conn,name,owner)=>{
				warning("Registered status notifier host %s", service);
				status_notifier_host_registered();
			},
			(conn,name)=>{
				host_services.remove(service);
				warning("Unregistered status notifier host %s", service);
			}
		);

		host_services.set(service, watch_identifier);
	}

	public signal bool status_notifier_item_registered(string item);
	public signal bool status_notifier_item_unregistered(string item);
	public signal bool status_notifier_host_registered();
}
