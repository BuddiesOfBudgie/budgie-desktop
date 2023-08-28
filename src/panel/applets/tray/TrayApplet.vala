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

public class TrayPlugin : Budgie.Plugin, Peas.ExtensionBase {
	public Budgie.Applet get_panel_widget(string uuid) {
		return new TrayApplet(uuid);
	}
}

[GtkTemplate (ui="/com/solus-project/tray/settings.ui")]
public class TraySettings : Gtk.Grid {
	Settings? settings = null;

	[GtkChild]
	private unowned Gtk.SpinButton? spinbutton_spacing;

	public TraySettings(Settings? settings) {
		this.settings = settings;
		settings.bind("spacing", spinbutton_spacing, "value", SettingsBindFlags.DEFAULT);
	}
}

internal struct DBusServiceInfo {
	public string name;
	public string object_path;
	public string sender;
	public string owner;
}

[DBus (name="org.freedesktop.StatusNotifierWatcher")]
private interface SnWatcherInterface : Object {
	public abstract string[] registered_status_notifier_items {owned get;}
	public abstract bool is_status_notifier_host_registered {owned get;}
	public abstract int32 protocol_version {owned get;}

	public abstract void register_status_notifier_host(string service) throws DBusError, IOError;

	// these signals and methods are specifically for use with budgie
	public abstract DBusServiceInfo[] get_registered_status_notifier_pathnames_budgie() throws DBusError, IOError;
	public signal void status_notifier_item_registered_budgie(string name, string object_path, string sender, string owner);
	public signal void status_notifier_item_unregistered_budgie(string name, string object_path, string sender);
}

public class TrayApplet : Budgie.Applet {
	public string uuid { public set; public get; }
	private Settings? settings;
	private Gtk.EventBox box;
	private Gtk.Box layout;
	private HashTable<string, TrayItem> items;
	private uint dbus_identifier;
	private SnWatcherInterface? watcher = null;
	private int panel_size;

	public TrayApplet(string uuid) {
		Object(uuid: uuid);

		get_style_context().add_class("system-tray-applet");

		box = new Gtk.EventBox();
		add(box);

		settings_schema = "com.solus-project.tray";
		settings_prefix = "/com/solus-project/tray";

		settings = get_applet_settings(uuid);
		settings.changed["spacing"].connect((key) => {
			layout.set_spacing(settings.get_int("spacing"));
		});

		items = new HashTable<string, TrayItem>(str_hash, str_equal);
		layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, settings.get_int("spacing"));
		box.add(layout);

		get_watcher_proxy();

		show_all();
	}

	~TrayApplet() {
		Bus.unown_name(dbus_identifier);
	}

	private void get_watcher_proxy() {
		Bus.get_proxy.begin<SnWatcherInterface>(
			BusType.SESSION,
			"org.freedesktop.StatusNotifierWatcher",
			"/org/freedesktop/StatusNotifierWatcher",
			0,
			null,
			on_dbus_get
		);
	}

	private void on_dbus_get(Object? o, AsyncResult? res) {
		if (watcher != null) return;

		try {
			watcher = Bus.get_proxy.end(res);
		} catch (Error e) {
			critical("Unable to connect to status notifier watcher: %s", e.message);
			return;
		}

		Bus.watch_name(
			BusType.SESSION,
			"org.freedesktop.StatusNotifierWatcher",
			0,
			(conn, name, owner) => Timeout.add(100, () => {
				on_watcher_init();
				return false;
			}),
			(conn, name) => get_watcher_proxy()
		);
	}

	private void on_watcher_init() {
		try {
			DBusServiceInfo[] services = watcher.get_registered_status_notifier_pathnames_budgie();
			foreach (DBusServiceInfo service in services) {
				register_new_item(service.name, service.object_path, service.sender, service.owner);
			}
		} catch (Error e) {
			critical("Unable to fetch existing status notifier items: %s", e.message);
		}

		watcher.status_notifier_item_registered_budgie.connect(register_new_item);

		watcher.status_notifier_item_unregistered_budgie.connect((name,path,sender)=>{
			var key = sender + name + path;
			if (key in items) {
				layout.remove(items.get(key));
				items.remove(key);
			}
		});

		string host_name = "org.freedesktop.StatusNotifierHost-budgie_" + uuid;

		dbus_identifier = Bus.own_name(
			BusType.SESSION,
			host_name,
			BusNameOwnerFlags.ALLOW_REPLACEMENT|BusNameOwnerFlags.REPLACE,
			null,
			(conn,name) => {
				try {
					watcher.register_status_notifier_host(host_name);
				} catch (Error e) {
					critical("Failed to register Status Notifier host: %s", e.message);
				}
			}
		);
	}

	private void register_new_item(string name, string object_path, string sender, string owner) {
		var key = sender + name + object_path;

		if (key in items) return;

		try {
			var new_item = new TrayItem(name, object_path, panel_size);
			items.set(key, new_item);
			if (object_path == "/org/ayatana/NotificationItem/nm_applet") {
				layout.pack_end(new_item);
			} else {
				layout.pack_start(new_item);
				layout.reorder_child(new_item, 0);
			}
		} catch (Error e) {
			warning("Failed to fetch dbus item info for name=%s and path=%s", name, object_path);
		}
	}

	public override void panel_position_changed(Budgie.PanelPosition position) {
		if (position == Budgie.PanelPosition.LEFT || position == Budgie.PanelPosition.RIGHT) {
			layout.orientation = Gtk.Orientation.VERTICAL;
			valign = Gtk.Align.BASELINE;
			halign = Gtk.Align.FILL;
		} else {
			layout.orientation = Gtk.Orientation.HORIZONTAL;
			valign = Gtk.Align.FILL;
			halign = Gtk.Align.BASELINE;
		}
	}

	public override void panel_size_changed(int panel, int icon, int small_icon) {
		panel_size = panel;
		items.get_values().foreach((item)=>{
			item.resize(panel);
		});
	}

	public override bool supports_settings() {
		return true;
	}

	public override Gtk.Widget? get_settings_ui() {
		return new TraySettings(get_applet_settings(uuid));
	}
}

[ModuleInit]
public void peas_register_types(TypeModule module) {
	// boilerplate - all modules need this
	var objmodule = module as Peas.ObjectModule;
	objmodule.register_extension_type(typeof(Budgie.Plugin), typeof(TrayPlugin));
}
