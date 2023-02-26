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

[DBus (name="com.canonical.dbusmenu")]
private interface DBusMenuInterface : Object {
	public abstract uint32 version {get;}
	public abstract string status {owned get;}
	public abstract string text_direction {owned get;}
	public abstract string[] icon_theme_path {owned get;}

	public abstract bool about_to_show(int32 id) throws DBusError, IOError;
	public abstract void event(int32 id, string event_id, Variant? data, uint32 timestamp) throws DBusError, IOError;
	public abstract void get_layout(int32 parent_id, int32 recursion_depth, string[] property_names, out uint32 revision, [DBus (signature="(ia{sv}av)")] out Variant? layout) throws DBusError, IOError;
	public abstract Variant? get_property(int32 id, string name) throws DBusError, IOError;

	public abstract signal void item_activation_requested(int32 id, uint32 timestamp);
	public abstract signal void items_properties_updated(
		[DBus (signature="a(ia{sv})")] Variant updated_props,
		[DBus (signature="a(ias)")] Variant removed_props
	);
	public abstract signal void layout_updated(uint32 revision, int32 parent_id);
}

public class DBusMenu : Object {
	private HashTable<int32, DBusMenuNode> all_nodes = new HashTable<int32, DBusMenuNode>(direct_hash, direct_equal);
	private List<int32> children = new List<int32>();
	private DBusMenuInterface iface;
	private Gtk.Menu menu;

	public DBusMenu(string dbus_name, ObjectPath dbus_object_path) throws DBusError, IOError {
		iface = Bus.get_proxy_sync(BusType.SESSION, dbus_name, dbus_object_path);
		menu = new Gtk.Menu();

		uint32 revision;
		Variant layout;
		iface.get_layout(0, -1, {}, out revision, out layout);
		parse_layout(layout);

		iface.items_properties_updated.connect(on_items_properties_updated);

		menu.show();
	}

	private void parse_layout(Variant layout) {
		Variant v_children = layout.get_child_value(2);

		VariantIter it = v_children.iterator();
		for (var v_child = it.next_value(); v_child != null; v_child = it.next_value()) {
			v_child = v_child.get_variant();
			int32 child_id = v_child.get_child_value(0).get_int32();
			Variant child_props = v_child.get_child_value(1);
			Variant child_children = v_child.get_child_value(2);

			var item = new DBusMenuNode(child_id, child_props, child_children);
			children.append(child_id);
			all_nodes.set(child_id, item);
			menu.add(item.item);
		}
	}

	private void on_items_properties_updated(Variant updated_props, Variant removed_props) {
		VariantIter it = updated_props.iterator();
		for (var child = it.next_value(); child != null; child = it.next_value()) {
			var child_id = child.get_child_value(0).get_int32();
			var item = all_nodes.get(child_id);
			if (item != null) {
				var child_props = child.get_child_value(1);
				var pit = child_props.iterator();
				for (var prop = pit.next_value(); prop != null; prop = pit.next_value()) {
					var key = prop.get_child_value(0).get_string();
					var value = prop.get_child_value(1);
					item.update_property(key, value);
				}
			}
		}

		it = removed_props.iterator();
		for (var child = it.next_value(); child != null; child = it.next_value()) {
			var child_id = child.get_child_value(0).get_int32();
			var node = all_nodes.get(child_id);
			if (node != null) {
				var child_props = child.get_child_value(1);
				var pit = child_props.iterator();
				for (var prop = pit.next_value(); prop != null; prop = pit.next_value()) {
					var key = prop.get_child_value(0).get_string();
					var value = prop.get_child_value(1);
					node.update_property(key, value);
				}
			}
		}
	}

	public void popup_at_pointer(Gdk.Event event) {
		menu.popup_at_pointer(event);
	}
}
