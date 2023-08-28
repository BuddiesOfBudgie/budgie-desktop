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
	public Gtk.Menu submenu;
	private Properties properties;
	private ulong activate_signal_handler = 0;

	public DBusMenuNode(int32 id, Variant props) {
		this.id = id;
		properties = new Properties(props);

		if (properties.type == "separator") {
			item = new Gtk.SeparatorMenuItem();
			item.visible = properties.visible;
			item.sensitive = properties.enabled;
			return;
		}

		submenu = new Gtk.Menu();
		submenu.map.connect(() => opened());
		submenu.unmap.connect(() => closed());

		var dbus_item = new DBusMenuItem(properties, submenu);
		activate_signal_handler = dbus_item.activate.connect(() => {
			if (dbus_item.submenu != null) {
				hovered();
			} else {
				clicked(dbus_item.should_draw_indicator ? new Variant.boolean(dbus_item.active) : null);
			}
		});
		dbus_item.notify["visible"].connect(() => dbus_item.visible = properties.visible);
		item = dbus_item;
	}

	public void update_children(List<DBusMenuNode> new_children) {
		for (int i = 0; i < new_children.length(); i++) {
			var item = new_children.nth_data(i).item;

			if (item.parent != submenu) {
				submenu.add(item);
			}
			submenu.reorder_child(item, i);
		}

		var old_children = submenu.get_children();
		for (uint i = old_children.length() - 1; i > new_children.length() - 1; i--) {
			var item = submenu.get_children().nth_data(i);
			submenu.remove(item);
		}

		submenu.queue_resize();
	}

	public void update_property(string key, Variant? value) {
		if (!properties.set_property(key, value)) return;

		if (activate_signal_handler > 0 && item is DBusMenuItem) {
			SignalHandler.block((DBusMenuItem) item, activate_signal_handler);
		}

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
			var dbus_item = (DBusMenuItem) item;
			switch (key) {
				case "label":
					dbus_item.update_label(properties.label);
					break;
				case "type":
					warning("Attempted to change the type of an existing item");
					break;
				case "disposition":
					dbus_item.update_disposition(properties.disposition);
					break;
				case "children-display":
					dbus_item.update_submenu(properties.children_display, submenu);
					break;
				case "toggle-type":
					dbus_item.update_toggle_type(properties.toggle_type);
					break;
				case "toggle-state":
					dbus_item.active = properties.toggle_state ?? false;
					break;
				case "icon-name":
				case "icon-data":
					dbus_item.update_icon(properties.icon_name, properties.icon_data);
					break;
				case "shortcut":
					dbus_item.update_shortcut(properties.shortcut);
					break;
				default:
					break;
			}

			if (activate_signal_handler > 0) SignalHandler.unblock(dbus_item, activate_signal_handler);
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

	public DBusMenuItem(Properties properties, Gtk.Menu submenu) {
		active = properties.toggle_state ?? false;
		update_toggle_type(properties.toggle_type);
		update_disposition(properties.disposition);
		update_submenu(properties.children_display, submenu);

		box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 5);
		icon = new Gtk.Image();
		update_icon(properties.icon_name, properties.icon_data);

		label = new Gtk.AccelLabel("");
		label.set_text_with_mnemonic(properties.label);
		update_shortcut(properties.shortcut);
		box.add(label);
		box.show_all();

		add(box);
		set_visible(properties.visible);
		set_sensitive(properties.enabled);
	}

	public void update_label(string new_mnemonic_text) {
		label.set_text_with_mnemonic(new_mnemonic_text);
	}

	public void update_toggle_type(string new_toggle_type) {
		draw_as_radio = new_toggle_type == "radio";
		should_draw_indicator = new_toggle_type != "";
	}

	public void update_disposition(string new_disposition) {
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

	public void update_submenu(string new_children_display, Gtk.Menu submenu) {
		if (this.submenu == null && new_children_display == "submenu") {
			this.submenu = submenu;
		} else if (this.submenu != null && new_children_display != "submenu") {
			this.submenu = null;
		}
	}

	public void update_icon(string icon_name, Bytes icon_data) {
		if (icon_name == "" && icon_data.get_size() == 0) {
			if (icon.parent == box) box.remove(icon);
			return;
		}

		Icon gicon;
		gicon = (icon_name != "") ? new ThemedIcon.with_default_fallbacks(icon_name) : gicon = new BytesIcon(icon_data);
		icon.set_from_gicon(gicon, Gtk.IconSize.MENU);
		icon.set_pixel_size(16);
		box.pack_start(icon, false, false, 2);
	}

	public void update_shortcut(List<string>? new_shortcut) {
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

	protected override void toggle_size_request(void* request) {
		if (should_draw_indicator || icon.parent == null) {
			base.toggle_size_request(request);
		} else {
			int* request_int = request;
			*request_int = 0;
		}
	}

	protected override void toggle_size_allocate(int alloc) {
		base.toggle_size_allocate(should_draw_indicator || icon.parent == null ? alloc : 0);
	}

	protected override void draw_indicator(Cairo.Context cr) {
		if (should_draw_indicator) base.draw_indicator(cr);
	}
}

private class Properties {
	public bool visible;
	public bool enabled;
	public string label;
	public string type;
	public string disposition;
	public string children_display;

	public string toggle_type;
	public bool? toggle_state;

	public string icon_name;
	public Bytes icon_data;

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
		icon_data = Properties.parse_bytes(props_table.get("icon-data"), new Bytes({}));

		shortcut = Properties.parse_shortcuts(props_table.get("shortcut"));
	}

	public bool set_property(string key, Variant? value) {
		switch (key) {
			case "visible":
				var old_value = visible;
				visible = Properties.parse_bool(value, true);
				return visible != old_value;
			case "enabled":
				var old_value = enabled;
				enabled = Properties.parse_bool(value, true);
				return enabled != old_value;
			case "label":
				var old_value = label;
				label = Properties.parse_string(value, "");
				return label != old_value;
			case "type":
				var old_value = type;
				type = Properties.parse_string(value, "standard");
				return type != old_value;
			case "disposition":
				var old_value = disposition;
				disposition = Properties.parse_string(value, "normal");
				return disposition != old_value;
			case "children-display":
				var old_value = children_display;
				children_display = Properties.parse_string(value, "");
				return children_display != old_value;
			case "toggle-type":
				var old_value = toggle_type;
				toggle_type = Properties.parse_string(value, "");
				return toggle_type != old_value;
			case "toggle-state":
				var old_value = toggle_state;
				toggle_state = Properties.parse_int32_bool(value, null);
				return toggle_state != old_value;
			case "icon-name":
				var old_value = icon_name;
				icon_name = Properties.parse_string(value, "");
				return icon_name != old_value;
			case "icon-data":
				var old_value = icon_data;
				icon_data = Properties.parse_bytes(value, new Bytes({}));
				return icon_data != old_value;
			case "shortcut":
				shortcut = Properties.parse_shortcuts(value);
				return true;
			default:
				return false;
		}
	}

	private static bool parse_bool(Variant? variant, bool default) {
		return variant != null && variant.is_of_type(VariantType.BOOLEAN) ?
			variant.get_boolean() : default;
	}

	private static bool? parse_int32_bool(Variant? variant, bool? default) {
		if (variant == null || !variant.is_of_type(VariantType.INT32)) return default;

		var value = variant.get_int32();
		return (value == 0 || value == 1) ? value == 1 : default;
	}

	private static string? parse_string(Variant? variant, string default) {
		return variant != null && variant.is_of_type(VariantType.STRING) ?
			variant.get_string() : default;
	}

	private static Bytes parse_bytes(Variant? variant, Bytes default) {
		return variant != null && variant.is_of_type(VariantType.BYTESTRING) ?
			variant.get_data_as_bytes() : default;
	}

	private static List<string>? parse_shortcuts(Variant? variant) {
		List<string>? ret = null;
		if (variant == null) return ret;

		VariantIter prop_it = variant.iterator();
		string key;
		string[] values;
		if (prop_it.next("{as}", out key, out values)) {
			ret = new List<string>();
			foreach (string val in values) {
				ret.append(val);
			}
		}

		return ret;
	}
}
