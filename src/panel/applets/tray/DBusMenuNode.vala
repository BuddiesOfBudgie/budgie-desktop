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

public class DBusMenuNode : Object {
	public int32 id;
	public Gtk.MenuItem item;

	private Properties properties;
	private List<int32> children = new List<int32>();

	public DBusMenuNode(int32 id, Variant props, Variant children, bool is_root = false) {
		this.id = id;
		properties = new Properties(props);
		if (is_root) return;

		if (properties.type == "separator") {
			item = new Gtk.SeparatorMenuItem();
			item.visible = properties.visible;
			item.sensitive = properties.enabled;
			return;
		}

		var dbus_item = new DBusMenuItem(properties);
		dbus_item.activate.connect(() => {
			clicked(dbus_item.should_draw_indicator ? new Variant.boolean(dbus_item.active) : null);
		});
		item = dbus_item;
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
			default:
				break;
		}

		if (item is DBusMenuItem) {
			((DBusMenuItem) item).property_updated(properties, key);
		}
	}

	public signal void clicked(Variant? data);
	public signal void hovered();
	public signal void opened();
	public signal void closed();
}

private class DBusMenuItem : Gtk.CheckMenuItem {
	public bool should_draw_indicator = false;
	private Gtk.Box box;
	private new Gtk.AccelLabel label;
	private Gtk.Image icon;

	public DBusMenuItem(Properties properties) {
		active = properties.toggle_state ?? false;
		update_toggle_type(properties.toggle_type);
		update_disposition(properties.disposition);

		box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 5);
		icon = new Gtk.Image();
		if (properties.icon_name != "" || properties.icon_data.length > 0) {
			if (properties.icon_name != "") {
				icon.set_from_icon_name(properties.icon_name, Gtk.IconSize.MENU);
			} else if (properties.icon_data.length > 0) {
				var input_stream = new MemoryInputStream.from_data(properties.icon_data, free);
				icon.set_from_pixbuf(new Gdk.Pixbuf.from_stream(input_stream));
			}
			box.pack_start(icon, false, false, 2);
		}

		label = new Gtk.AccelLabel("");
		label.set_text_with_mnemonic(properties.label);
		update_shortcut(properties.shortcut);
		box.add(label);
		box.show_all();

		add(box);
		set_visible(properties.visible);
		set_sensitive(properties.enabled);
	}

	public void property_updated(Properties properties, string key) {
		switch (key) {
			case "label":
				label.set_text_with_mnemonic(properties.label);
				break;
			case "type":
				warning("Attempted to change the type of an existing item");
				break;
			case "disposition":
				update_disposition(properties.disposition);
				break;
			case "children-display":
				break; // TODO make this do something
			case "toggle-type":
				update_toggle_type(properties.toggle_type);
				break;
			case "toggle-state":
				active = properties.toggle_state ?? false;
				break;
			case "icon-name":
				if (properties.icon_name == "" && icon.parent == box) {
					box.remove(icon);
				} else if (properties.icon_name != "") {
					icon.set_from_icon_name(properties.icon_name, Gtk.IconSize.MENU);
					box.pack_start(icon, false, false, 2);
				}

				break;
			case "icon-data":
				if (properties.icon_name != "") return;

				if (properties.icon_data.length == 0 && icon.parent == box) {
					box.remove(icon);
				} else if (properties.icon_data.length > 0) {
					var input_stream = new MemoryInputStream.from_data(properties.icon_data, free);
					icon.set_from_pixbuf(new Gdk.Pixbuf.from_stream(input_stream));
					box.pack_start(icon, false, false, 2);
				}

				break;
			case "shortcut":
				update_shortcut(properties.shortcut);
				break;
			default:
				break;
		}
	}

	private void update_toggle_type(string new_toggle_type) {
		draw_as_radio = new_toggle_type == "radio";
		should_draw_indicator = new_toggle_type != "";
	}

	private void update_disposition(string new_disposition) {
		var style_context = get_style_context();
		style_context.remove_class("info");
		style_context.remove_class("warning");
		style_context.remove_class("error");

		if (new_disposition == "informative") {
			style_context.add_class("info");
		} else if (new_disposition == "warning") {
			style_context.add_class("warning");
		} else if (new_disposition == "alert") {
			style_context.add_class("error");
		}
	}

	private void update_shortcut(List<string>? new_shortcut) {
		if (new_shortcut == null) {
			label.set_accel(0, 0);
			return;
		}

		uint key = 0;
		Gdk.ModifierType modifier = 0;
		new_shortcut.foreach((it) => {
			switch (it) {
				case "Control":
					modifier |= Gdk.ModifierType.CONTROL_MASK;
					break;
				case "Alt":
					modifier |= Gdk.ModifierType.MOD1_MASK;
					break;
				case "Shift":
					modifier |= Gdk.ModifierType.SHIFT_MASK;
					break;
				case "Super":
					modifier |= Gdk.ModifierType.SUPER_MASK;
					break;
				default:
					Gdk.ModifierType temp_modifier;
					Gtk.accelerator_parse(it, out key, out temp_modifier);
					break;
			}
		});

		label.set_accel(key, modifier);
	}

	protected override void draw_indicator(Cairo.Context cr) {
		if (should_draw_indicator) base.draw_indicator(cr);
	}
}

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

	public List<string>? shortcut;

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

	private static List<string>? parse_shortcuts(Variant? variant) {
		List<string>? ret = null;
		if (variant == null) {
			return ret;
		}

		VariantIter prop_it = variant.iterator();
		string key;
		string[] value;
		if (prop_it.next("{as}", out key, out value)) {
			ret = new List<string>();
			for (int i = 0; i < value.length; i++) {
				ret.append(value[i]);
			}
		}

		return ret;
	}
}
