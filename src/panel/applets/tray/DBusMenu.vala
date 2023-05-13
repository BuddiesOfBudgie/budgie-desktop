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

	public abstract bool about_to_show(int32 id, out bool need_update) throws DBusError, IOError;
	public abstract void about_to_show_group(int32[] ids, out int32[] updates_needed, out int32[] id_errors) throws DBusError, IOError;
	public abstract void event(int32 id, string event_id, Variant? data, uint32 timestamp) throws DBusError, IOError;
	public abstract void event_group([DBus (signature="a(isvu)")] Variant events, out int32[] id_errors) throws DBusError, IOError;
	public abstract void get_layout(int32 parent_id, int32 recursion_depth, string[] property_names, out uint32 revision, [DBus (signature="(ia{sv}av)")] out Variant? layout) throws DBusError, IOError;
	public abstract Variant? get_property(int32 id, string name) throws DBusError, IOError;
	public abstract void get_group_properties(int32[] ids, string[] property_names, [DBus (signature="a(ia{sv})")] out Variant? properties) throws DBusError, IOError;

	public abstract signal void item_activation_requested(int32 id, uint32 timestamp);
	public abstract signal void items_properties_updated(
		[DBus (signature="a(ia{sv})")] Variant updated_props,
		[DBus (signature="a(ias)")] Variant removed_props
	);
	public abstract signal void layout_updated(uint32 revision, int32 parent_id);
}

public class DBusMenu : Object {
	private HashTable<int32, DBusMenuNode> all_nodes = new HashTable<int32, DBusMenuNode>(direct_hash, direct_equal);
	private DBusMenuInterface iface;

	public DBusMenu(string dbus_name, ObjectPath dbus_object_path) throws DBusError, IOError {
		iface = Bus.get_proxy_sync(BusType.SESSION, dbus_name, dbus_object_path);

		update_layout();
		iface.layout_updated.connect((revision, parent) => update_layout());
		iface.items_properties_updated.connect((updated_props, removed_props) => {
			on_items_properties_updated(updated_props);
			on_items_properties_updated(removed_props);
		});
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

		all_nodes.foreach_remove((id, node) => {
			return id != 0 && node.item.parent == null;
		});

		all_nodes.get(0).submenu.show_all();
	}

	private DBusMenuNode? parse_layout(Variant layout) {
		Variant v_id = layout.get_child_value(0);

		// this happens with some apps that don't follow spec, like jetbrains toolbox
		if (!v_id.is_of_type(VariantType.INT32)) {
			return null;
		}

		int32 id = v_id.get_int32();
		Variant v_props = layout.get_child_value(1);
		Variant v_children = layout.get_child_value(2);

		var node = all_nodes.get(id);
		if (node != null) {
			update_node_properties(node, v_props);
		} else {
			node = new DBusMenuNode(id, v_props);
			node.clicked.connect((data) => send_event(id, "clicked", data));
			node.hovered.connect((event) => send_event(id, "hovered"));
			node.opened.connect((event) => send_event(id, "opened"));
			node.closed.connect((event) => send_event(id, "closed"));

			all_nodes.set(id, node);
		}

		if (v_children.is_container() && v_children.n_children() > 0) {
			var new_children = new List<DBusMenuNode>();

			VariantIter it = v_children.iterator();
			for (var v_child = it.next_value(); v_child != null; v_child = it.next_value()) {
				v_child = v_child.get_variant();
				var child_node = parse_layout(v_child);
				if (child_node != null) {
					new_children.append(child_node);
				}
			}

			node.update_children(new_children);
		}

		return node;
	}

	private void on_items_properties_updated(Variant updated_props) {
		VariantIter it = updated_props.iterator();
		for (var child = it.next_value(); child != null; child = it.next_value()) {
			var child_id = child.get_child_value(0).get_int32();
			var node = all_nodes.get(child_id);
			if (node != null) update_node_properties(node, child.get_child_value(1));
		}
	}

	private void update_node_properties(DBusMenuNode node, Variant props) {
		VariantIter prop_it = props.iterator();
		string key;
		Variant value;
		while (prop_it.next("{sv}", out key, out value)) {
			node.update_property(key, value);
		}
	}

	private void send_event(int32 node_id, string type, Variant? data = null) {
		if (node_id in all_nodes) {
			try {
				iface.event(node_id, type, data ?? new Variant.int32(0), (uint32) Gtk.get_current_event_time());
			} catch (Error e) {
				warning("Failed to send %s event to node %d: %s", type, node_id, e.message);
			}
		}
	}

	public void popup_at_pointer(Gdk.Event event) {
		var submenu = all_nodes.get(0).submenu;

		// avoid showing empty menus, e.g. if an app provides invalid data (like jetbrains toolbox)
		if (submenu.get_children().length() > 0) {
			submenu.popup_at_pointer(event);
		}
	}
}
