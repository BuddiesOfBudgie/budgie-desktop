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

		update_layout();
		iface.items_properties_updated.connect((updated_props, removed_props) => {
			on_items_properties_updated(updated_props);
			on_items_properties_updated(removed_props);
		});

		menu.show();
	}

	private void update_layout() {
		uint32 revision;
		Variant layout;
		try {
			iface.get_layout(0, -1, {}, out revision, out layout);
		} catch (Error e) {
			warning("Failed to update layout: %s", e.message);
			return;
		}

		parse_layout(layout);
	}

	private void parse_layout(Variant layout) {
		Variant v_children = layout.get_child_value(2);

		VariantIter it = v_children.iterator();
		for (var v_child = it.next_value(); v_child != null; v_child = it.next_value()) {
			v_child = v_child.get_variant();
			int32 child_id = v_child.get_child_value(0).get_int32();
			Variant child_props = v_child.get_child_value(1);
			Variant child_children = v_child.get_child_value(2);

			var node = new DBusMenuNode(child_id, child_props, child_children);
			node.clicked.connect((data) => send_event(node.id, "clicked", data));
			node.hovered.connect((event) => send_event(node.id, "hovered"));
			node.opened.connect((event) => send_event(node.id, "opened"));
			node.closed.connect((event) => send_event(node.id, "closed"));
			children.append(child_id);
			all_nodes.set(child_id, node);
			menu.add(node.item);
		}
	}

	private void on_items_properties_updated(Variant updated_props) {
		VariantIter it = updated_props.iterator();
		for (var child = it.next_value(); child != null; child = it.next_value()) {
			var child_id = child.get_child_value(0).get_int32();
			var item = all_nodes.get(child_id);
			if (item != null) {
				var child_props = child.get_child_value(1);
				var pit = child_props.iterator();
				for (var prop = pit.next_value(); prop != null; prop = pit.next_value()) {
					if (prop.is_container() && prop.n_children() == 2) {
						var key = prop.get_child_value(0).get_string();
						var value = prop.get_child_value(1);
						item.update_property(key, value);
					}
				}
			}
		}
	}

	private void send_event(int32 node_id, string type, Variant? data = null) {
		try {
			iface.event(node_id, type, data ?? new Variant.int32(0), (uint32) get_real_time());
		} catch (Error e) {
			warning("Failed to send %s event to node %d: %s", type, node_id, e.message);
		}
	}

	public void popup_at_pointer(Gdk.Event event) {
		menu.popup_at_pointer(event);
	}
}
