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

private class Properties {
	public bool visible;
	public bool enabled;
	public string? label;
	public string? type;
	public string? disposition;
	public string? children_display;

	public string? toggle_type;
	public bool? toggle_state;

	public string? icon_name;
	public uint8[] icon_data;

	public List<List<string>> shortcut;

	public Properties(Variant props) {
		HashTable<string, Variant?> props_table = new HashTable<string, Variant?>(str_hash, str_equal);

		VariantIter prop_it = props.iterator();
		string key;
		Variant value;
		while (prop_it.next("{sv}", out key, out value)) {
			props_table.set(key, value);
		}

		visible = Properties.parse_bool(props_table.get("visible"), true);
		enabled = Properties.parse_bool(props_table.get("enabled"), true);
		label = Properties.parse_string(props_table.get("label"), "");
		type = Properties.parse_string(props_table.get("type"), "standard");
		disposition = Properties.parse_string(props_table.get("disposition"), "normal");
		children_display = Properties.parse_string(props_table.get("children-display"), "");

		toggle_type = Properties.parse_string(props_table.get("toggle-type"), "");
		toggle_state = Properties.parse_int32_bool(props_table.get("toggle-state"), null);

		icon_name = Properties.parse_string(props_table.get("icon-name"), "");
		icon_data = Properties.parse_bytes(props_table.get("icon-data"), {});

		shortcut = Properties.parse_shortcuts(props_table.get("shortcut"));
	}

	public void set_property(string key, Variant? value) {
		switch (key) {
			case "visible":
				visible = Properties.parse_bool(value, true);
				break;
			case "enabled":
				enabled = Properties.parse_bool(value, true);
				break;
			case "label":
				label = Properties.parse_string(value, "");
				break;
			case "type":
				type = Properties.parse_string(value, "standard");
				break;
			case "disposition":
				disposition = Properties.parse_string(value, "normal");
				break;
			case "children-display":
				children_display = Properties.parse_string(value, "");
				break;
			case "toggle-type":
				toggle_type = Properties.parse_string(value, "");
				break;
			case "toggle-state":
				toggle_state = Properties.parse_int32_bool(value, null);
				break;
			case "icon-name":
				icon_name = Properties.parse_string(value, "");
				break;
			case "icon-data":
				icon_data = Properties.parse_bytes(value, {});
				break;
			case "shortcut":
				shortcut = Properties.parse_shortcuts(value);
				break;
			default:
				break;
		}
	}

	private static bool parse_bool(Variant? variant, bool default) {
		return variant != null && variant.is_of_type(VariantType.BOOLEAN) ?
			variant.get_boolean() : default;
	}

	private static bool? parse_int32_bool(Variant? variant, bool? default) {
		if (variant == null || !variant.is_of_type(VariantType.INT32)) {
			return default;
		}

		var value = variant.get_int32();
		if (value == 0 || value == 1) {
			return value == 1;
		} else {
			return default;
		}
	}

	private static string? parse_string(Variant? variant, string default) {
		return variant != null && variant.is_of_type(VariantType.STRING) ?
			variant.get_string() : default;
	}

	private static uint8[] parse_bytes(Variant? variant, uint8[] default) {
		return variant != null && variant.is_of_type(VariantType.BYTESTRING) ?
			variant.get_data_as_bytes().get_data() : default;
	}

	private static List<List<string>> parse_shortcuts(Variant? variant) {
		var ret = new List<List<string>>();
		if (variant == null) {
			return ret;
		}

		VariantIter prop_it = variant.iterator();
		string key;
		string[] value;
		while (prop_it.next("{as}", out key, out value)) {
			var shortcut = new List<string>();
			for (int i = 0; i < value.length; i++) {
				shortcut.append(value[i]);
			}
			ret.append((owned) shortcut);
		}

		return ret;
	}
}

public class DBusMenuNode : Object {
	public int32 id;
	public Gtk.MenuItem item;

	private Properties properties;
	private List<int32> children;

	public DBusMenuNode(int32 id, Variant props, Variant children) {
		this.id = id;
		properties = new Properties(props);

		if (properties.type == "separator") {
			item = new Gtk.SeparatorMenuItem();
			item.visible = properties.visible;
			item.set_sensitive(properties.enabled);
			return;
		}

		if (properties.toggle_type != "") {
			var check_item = new Gtk.CheckMenuItem.with_mnemonic(properties.label) {
				active = properties.toggle_state ?? false,
				draw_as_radio = properties.toggle_type == "radio",
			};
			check_item.activate.connect(() => clicked(new Variant.boolean(check_item.active)));
		} else {
			item = new Gtk.MenuItem.with_mnemonic(properties.label);
			item.activate.connect(() => clicked(null));
		}

		item.set_visible(properties.visible);
		item.set_sensitive(properties.enabled);
	}

	public void update_property(string key, Variant? value) {
		properties.set_property(key, value);

		switch (key) {
			case "visible":
				item.set_visible(properties.visible);
				break;
			case "enabled":
				item.set_sensitive(properties.enabled);
				break;
			case "label":
				item.set_label(properties.label);
				break;
			case "type":
				warning("Attempted to change the type of an existing item");
				break;
			case "disposition":
				break; // TODO make this do something
			case "children-display":
				break; // TODO make this do something
			case "toggle-type":
				warning("Attempted to change the toggle type of an existing item");
				break;
			case "toggle-state":
				if (item is Gtk.CheckMenuItem) {
					((Gtk.CheckMenuItem) item).active = properties.toggle_state ?? false;
				}
				break;
			case "icon-name":
				break; // TODO make this do something
			case "icon-data":
				break; // TODO make this do something
			case "shortcut":
				break; // TODO make this do something
			default:
				break;
		}
	}

	public signal void clicked(Variant? data);
	public signal void hovered();
	public signal void opened();
	public signal void closed();
}
