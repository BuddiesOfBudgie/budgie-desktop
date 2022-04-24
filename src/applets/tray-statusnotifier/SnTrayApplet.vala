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

public class SnTrayPlugin : Budgie.Plugin, Peas.ExtensionBase {
	public Budgie.Applet get_panel_widget(string uuid) {
		return new SnTrayApplet(uuid);
	}
}

[GtkTemplate (ui="/org/buddiesofbudgie/sntray/settings.ui")]
public class SnTraySettings : Gtk.Grid {
	Settings? settings = null;

	[GtkChild]
	private unowned Gtk.SpinButton? spinbutton_spacing;

	public SnTraySettings(Settings? settings) {
		this.settings = settings;
		settings.bind("spacing", spinbutton_spacing, "value", SettingsBindFlags.DEFAULT);
	}
}

public struct DBusPathName {
	public string name;
	public string object_path;
}

[DBus (name="org.kde.StatusNotifierWatcher")]
private interface SnWatcherInterface : Object {
	public abstract string[] registered_status_notifier_items {owned get;}
	public abstract bool is_status_notifier_host_registered {owned get;}
	public abstract int32 protocol_version {owned get;}

	public abstract void register_status_notifier_host(string service) throws DBusError, IOError;
	public abstract DBusPathName[] get_registered_status_notifier_pathnames() throws DBusError, IOError;

	// these signals are specifically for use with budgie
	public signal void status_notifier_item_registered_budgie(string name, string object_path);
	public signal void status_notifier_item_unregistered_budgie(string name, string object_path);
}

public class SnTrayApplet : Budgie.Applet {
	public string uuid { public set; public get; }
	private Settings? settings;
	private Gtk.EventBox box;
	private Gtk.Box layout;
	private HashTable<string, SnTrayItem> items;
	private Gtk.Orientation orient;
	private uint dbus_identifier;
	private SnWatcherInterface? watcher;
	private int panel_size;

	public SnTrayApplet(string uuid) {
		Object(uuid: uuid);

		get_style_context().add_class("system-tray-applet");

		box = new Gtk.EventBox();
		add(box);

		settings_schema = "org.buddiesofbudgie.sntray";
		settings_prefix = "/org/buddiesofbudgie/budgie-panel/instance/sntray";

		settings = get_applet_settings(uuid);
		settings.changed["spacing"].connect((key) => {
			layout.set_spacing(settings.get_int("spacing"));
		});

		items = new HashTable<string, SnTrayItem>(str_hash, str_equal);
		layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, settings.get_int("spacing"));
		box.add(layout);

		get_watcher_proxy();

		show_all();
	}

	~SnTrayApplet() {
		Bus.unown_name(dbus_identifier);
	}

	private void get_watcher_proxy() {
		Bus.get_proxy.begin<SnWatcherInterface>(
			BusType.SESSION,
			"org.kde.StatusNotifierWatcher",
			"/org/kde/StatusNotifierWatcher",
			0,
			null,
			on_dbus_get
		);
	}

	private void on_dbus_get(Object? o, AsyncResult? res) {
		try {
			watcher = Bus.get_proxy.end(res);
		} catch (Error e) {
			critical("Unable to connect to status notifier watcher: %s", e.message);
			return;
		}

		Bus.watch_name(
			BusType.SESSION,
			"org.kde.StatusNotifierWatcher",
			0,
			(conn,name,owner)=>{on_watcher_init();},
			(conn,name)=>{get_watcher_proxy();}
		);
	}

	private void on_watcher_init() {
		try {
			DBusPathName[] pathnames = watcher.get_registered_status_notifier_pathnames();
			for (int i = 0; i < pathnames.length; i++) {
				register_new_item(pathnames[i].name, pathnames[i].object_path);
			}
		} catch (Error e) {
			critical("Unable to fetch existing status notifier items: %s", e.message);
		}

		watcher.status_notifier_item_registered_budgie.connect(register_new_item);

		watcher.status_notifier_item_unregistered_budgie.connect((name,path)=>{
			layout.remove(items.get(path + name));
			items.remove(path + name);
		});

		string host_name = "org.freedesktop.StatusNotifierHost-budgie_" + uuid;

		dbus_identifier = Bus.own_name(
			BusType.SESSION,
			host_name,
			BusNameOwnerFlags.ALLOW_REPLACEMENT|BusNameOwnerFlags.REPLACE,
			(conn,name)=>{
				try {
					watcher.register_status_notifier_host(host_name);
				} catch (Error e) {
					critical("Failed to register Status Notifier host: %s", e.message);
				}
			}
		);
	}

	private void register_new_item(string name, string object_path) {
		try {
			SnItemInterface dbus_item = Bus.get_proxy_sync(BusType.SESSION, name, object_path);
			var new_item = new SnTrayItem(dbus_item, panel_size);
			items.set(object_path + name, new_item);
			layout.pack_end(new_item);
		} catch (Error e) {
			warning("Failed to fetch dbus item info for name=%s and path=%s", name, object_path);
		}
	}

	public override void panel_position_changed(Budgie.PanelPosition position) {
		if (position == Budgie.PanelPosition.LEFT || position == Budgie.PanelPosition.RIGHT) {
			orient = Gtk.Orientation.VERTICAL;
			valign = Gtk.Align.BASELINE;
			halign = Gtk.Align.FILL;
		} else {
			orient = Gtk.Orientation.HORIZONTAL;
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
		return new SnTraySettings(get_applet_settings(uuid));
	}
}

[ModuleInit]
public void peas_register_types(TypeModule module) {
	// boilerplate - all modules need this
	var objmodule = module as Peas.ObjectModule;
	objmodule.register_extension_type(typeof(Budgie.Plugin), typeof(SnTrayPlugin));
}
