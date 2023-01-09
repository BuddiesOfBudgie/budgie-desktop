internal struct IconPixmap {
	int width;
	int height;
	char[] data;
}

internal struct ToolTip {
	string icon_name;
	IconPixmap[] icon_data;
	string title;
	string markup;
}

const int TARGET_ICON_PADDING = 18;
const double TARGET_ICON_SCALE = 2.0 / 3.0;
const int FORMULA_SWAP_POINT = TARGET_ICON_PADDING * 3;

[DBus (name="com.canonical.dbusmenu")]
internal interface DBusMenuInterface : Object {
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

[DBus (name="org.kde.StatusNotifierItem")]
internal interface SnItemProperties : Object {
	public abstract string category {owned get;}
	public abstract string id {owned get;}
	public abstract string title {owned get;}
	public abstract string status {owned get;}
	public abstract uint32 window_id {get;}
	public abstract string icon_name {owned get;}
	public abstract IconPixmap[] icon_pixmap {owned get;}
	public abstract string overlay_icon_name {owned get;}
	public abstract IconPixmap[] overlay_icon_pixmap {owned get;}
	public abstract string attention_icon_name {owned get;}
	public abstract IconPixmap[] attention_icon_pixmap {owned get;}
	public abstract string attention_movie_name {owned get;}
	public abstract string icon_theme_path {owned get;}
	public abstract ToolTip? tool_tip {owned get;}
	public abstract bool item_is_menu {get;}
	public abstract ObjectPath? menu {owned get;}
}

[DBus (name="org.kde.StatusNotifierItem")]
internal interface SnItemInterface : Object {
	public abstract void context_menu(int x, int y) throws DBusError, IOError;
	public abstract void activate(int x, int y) throws DBusError, IOError;
	public abstract void secondary_activate(int x, int y) throws DBusError, IOError;
	public abstract void scroll(int delta, string orientation) throws DBusError, IOError;

	public abstract signal void new_title();
	public abstract signal void new_icon();
	public abstract signal void new_icon_theme_path(string new_path);
	public abstract signal void new_attention_icon();
	public abstract signal void new_overlay_icon();
	public abstract signal void new_tool_tip();
	public abstract signal void new_status(string new_status);
}

internal class SnTrayItem : Gtk.EventBox {
	private SnItemInterface dbus_item;
	private SnItemProperties dbus_properties;

	private string dbus_name;
	private string dbus_object_path;

	private DBusMenuInterface? dbus_menu;
	private Gtk.Menu? context_menu;
	private HashTable<int32, uint32> revisions = null;

	private string? icon_theme_path = null;
	private Gtk.Image icon;

	public int target_icon_size = 8;

	public SnTrayItem(string dbus_name, string dbus_object_path, int applet_size) throws DBusError, IOError {
		this.dbus_item = Bus.get_proxy_sync(BusType.SESSION, dbus_name, dbus_object_path);
		this.dbus_properties = Bus.get_proxy_sync(BusType.SESSION, dbus_name, dbus_object_path);

		this.dbus_name = dbus_name;
		this.dbus_object_path = dbus_object_path;

		reset_icon_theme();
		icon = new Gtk.Image();
		resize(applet_size);
		add(icon);

		reset_tooltip();

		if (dbus_properties.menu != null) {
			try {
				dbus_menu = Bus.get_proxy_sync(BusType.SESSION, dbus_name, dbus_properties.menu);

				context_menu = build_menu(0);
				context_menu.map.connect(() => {
					dbus_menu.event(0, "opened", new Variant.int32(0), (uint32) get_real_time());
				});
				context_menu.unmap.connect(() => {
					dbus_menu.event(0, "closed", new Variant.int32(0), (uint32) get_real_time());
				});
				context_menu.show_all();

				dbus_menu.layout_updated.connect((revision, parent_id) => {
					context_menu = build_menu(0);
					context_menu.map.connect(() => {
						dbus_menu.event(0, "opened", new Variant.int32(0), (uint32) get_real_time());
					});
					context_menu.unmap.connect(() => {
						dbus_menu.event(0, "closed", new Variant.int32(0), (uint32) get_real_time());
					});
					context_menu.show_all();
				});
			} catch (Error e) {
				warning("Failed to get a proxy object for tray item menu: %s", e.message);
			}
		}

		dbus_item.new_icon.connect(() => {
			update_dbus_properties();
			reset_icon();
		});
		dbus_item.new_attention_icon.connect(() => {
			update_dbus_properties();
			reset_icon();
		});
		dbus_item.new_icon_theme_path.connect((new_path) => {
			reset_icon_theme(new_path);
		});
		dbus_item.new_status.connect((new_status) => {
			reset_icon(new_status);
		});
		dbus_item.new_tool_tip.connect(() => {
			update_dbus_properties();
			reset_tooltip();
		});

		show_all();
	}

	private void update_dbus_properties() {
		try {
			this.dbus_properties = Bus.get_proxy_sync(BusType.SESSION, dbus_name, dbus_object_path);
		} catch (Error e) {
			warning("Failed to update dbus properties: %s", e.message);
		}
	}

	private void reset_icon(string? status = null) {
		string icon_name;
		if ((status ?? dbus_properties.status) == "NeedsAttention") {
			icon_name = dbus_properties.attention_icon_name;
		} else {
			icon_name = dbus_properties.icon_name;
		}

		try {
			if (icon_theme_path != null) {
				var icon_theme = Gtk.IconTheme.get_default();

				if (icon_theme.has_icon(icon_name)) {
					icon.set_from_icon_name(icon_name, Gtk.IconSize.INVALID);
				} else {
					icon_theme.prepend_search_path(icon_theme_path);
					icon.set_from_pixbuf(icon_theme.load_icon(icon_name, target_icon_size, Gtk.IconLookupFlags.FORCE_SIZE));
				}
			} else {
				icon.set_from_icon_name(icon_name, Gtk.IconSize.INVALID);
			}
		} catch (Error e) {
			warning("Failed to get icon from theme: %s", e.message);
		}

		if (target_icon_size > 0) {
			this.icon.pixel_size = target_icon_size;
		}
	}

	private void reset_icon_theme(string? new_path = null) {
		if (new_path != null) {
			icon_theme_path = new_path;
		} else if (dbus_properties.icon_theme_path != null) {
			icon_theme_path = dbus_properties.icon_theme_path;
		}
	}

	private void reset_tooltip() {
		if (dbus_properties.tool_tip != null) {
			if (dbus_properties.tool_tip.markup != "") {
				set_tooltip_markup(dbus_properties.tool_tip.markup);
			} else {
				set_tooltip_text(dbus_properties.tool_tip.title);
			}
		} else {
			set_tooltip_text(null);
		}
	}

	private Gtk.Menu? build_menu(int32 parent_id) {
		uint32 revision;
		Variant layout;

		try {
			dbus_menu.get_layout(parent_id, -1, {}, out revision, out layout);
		} catch (Error e) {
			debug("Failed to get layout for dbus menu: %s", e.message);
			return null;
		}

		int32 id = layout.get_child_value(0).get_int32();
		Variant properties = layout.get_child_value(1);
		Variant children = layout.get_child_value(2);

		var menu = new Gtk.Menu();
		Gtk.RadioMenuItem? last_radio_item = null;

		VariantIter it = children.iterator();
		for (var child = it.next_value(); child != null; child = it.next_value()) {
			child = child.get_variant();

			int32 child_id = child.get_child_value(0).get_int32();
			HashTable<string, Variant?> props_table = build_props_table(child.get_child_value(1));

			if (props_table.contains("visible") && !props_table.get("visible").get_boolean()) {
				continue;
			}

			Gtk.MenuItem item = null;

			if (props_table.contains("type") && props_table.get("type").get_string() == "separator") {
				last_radio_item = null;
				item = new Gtk.SeparatorMenuItem();
			} else if (props_table.contains("toggle-type")) {
				var toggle_type = props_table.get("toggle-type").get_string();

				if (toggle_type == "checkmark") {
					item = build_check_menu_item(props_table, child_id);
				} else if (toggle_type == "radio") {
					last_radio_item = build_radio_menu_item(props_table, child_id, last_radio_item);
					item = last_radio_item;
				}
			} else if (props_table.contains("icon-name") && props_table.get("icon-name").get_string().size() == 0) {
				var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
				box.add(new Gtk.Image.from_icon_name(props_table.get("icon-name").get_string(), Gtk.IconSize.MENU));
				box.add(new Gtk.Label.with_mnemonic(props_table.get("label").get_string()));
				item = new Gtk.MenuItem();
				item.add(box);
				item.activate.connect(() => {
					dbus_menu.event(child_id, "clicked", new Variant.int32(0), (uint32) get_real_time());
				});
			} else if (props_table.contains("icon-data")) {
				var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
				var input_stream = new MemoryInputStream.from_data(props_table.get("icon-data").get_data_as_bytes().get_data(), free);
				box.add(new Gtk.Image.from_pixbuf(new Gdk.Pixbuf.from_stream(input_stream)));
				box.add(new Gtk.Label.with_mnemonic(props_table.get("label").get_string()));
				item = new Gtk.MenuItem();
				item.add(box);
				item.activate.connect(() => {
					dbus_menu.event(child_id, "clicked", new Variant.int32(0), (uint32) get_real_time());
				});
			} else {
				item = new Gtk.MenuItem.with_mnemonic(props_table.get("label").get_string());
				item.activate.connect(() => {
					dbus_menu.event(child_id, "clicked", new Variant.int32(0), (uint32) get_real_time());
				});
			}

			if (item != null) {
				if (props_table.contains("children-display") && props_table.get("children-display").get_string() == "submenu") {
					var submenu = build_menu(child_id);
					if (submenu != null) {
						submenu.map.connect(() => {
							dbus_menu.event(child_id, "opened", new Variant.int32(0), (uint32) get_real_time());
						});
						submenu.unmap.connect(() => {
							dbus_menu.event(child_id, "closed", new Variant.int32(0), (uint32) get_real_time());
						});
						item.set_submenu(submenu);
					}
				}

				if (props_table.contains("enabled") && !props_table.get("enabled").get_boolean()) {
					item.set_sensitive(false);
				}

				if (props_table.contains("disposition")) {
					var disposition = props_table.get("disposition").get_string();
					if (disposition == "informative") {
						item.get_style_context().add_class("info");
					} else if (disposition == "warning") {
						item.get_style_context().add_class("warning");
					} else if (disposition == "alert") {
						item.get_style_context().add_class("error");
					}
				}
				menu.add(item);
			}
		}

		return menu;
	}

	private static HashTable<string, Variant?> build_props_table(Variant properties) {
		HashTable<string, Variant?> props_table = new HashTable<string, Variant?>(str_hash, str_equal);

		VariantIter prop_it = properties.iterator();
		string key;
		Variant value;
		while (prop_it.next("{sv}", out key, out value)) {
			props_table.set(key, value);
		}

		return props_table;
	}

	private Gtk.CheckMenuItem build_check_menu_item(HashTable<string, Variant?> props_table, int32 child_id) {
		Gtk.CheckMenuItem check_item = new Gtk.CheckMenuItem.with_mnemonic(props_table.get("label").get_string());
		check_item.set_active(props_table.contains("toggle-state") && props_table.get("toggle-state").get_int32() == 1);
		check_item.toggled.connect(() => {
			dbus_menu.event(child_id, "clicked", new Variant.boolean(check_item.get_active()), (uint32) get_real_time());
		});
		return check_item;
	}

	private Gtk.RadioMenuItem build_radio_menu_item(HashTable<string, Variant?> props_table, int32 child_id, Gtk.RadioMenuItem? prev_radio_item) {
		Gtk.RadioMenuItem radio_item = new Gtk.RadioMenuItem.with_mnemonic_from_widget(prev_radio_item, props_table.get("label").get_string());
		radio_item.set_active(props_table.contains("toggle-state") && props_table.get("toggle-state").get_int32() == 1);
		radio_item.toggled.connect(() => {
			dbus_menu.event(child_id, "clicked", new Variant.boolean(radio_item.get_active()), (uint32) get_real_time());
		});
		return radio_item;
	}

	//  private Gtk.MenuItem build_menu_item(Variant layout) {

	//  }

	public override bool button_release_event(Gdk.EventButton event) {
		if (event.button == 3) { // Right click
			show_context_menu(event);
			return Gdk.EVENT_STOP;
		} else if (event.button == 1 && !dbus_properties.item_is_menu) { // Left click
			activate(event);
			return Gdk.EVENT_STOP;
		} else if (event.button == 2) { // Middle click
			secondary_activate(event);
			return Gdk.EVENT_STOP;
		}

		return base.button_release_event(event);
	}

	private void activate(Gdk.EventButton event) {
		try {
			dbus_item.activate((int) event.x_root, (int) event.y_root);
		} catch (DBusError e) {
			// this happens if the application doesn't implement the activate dbus method
			debug("Failed to call activate method on StatusNotifier item: %s", e.message);
		} catch (IOError e) {
			warning("Failed to call activate method on StatusNotifier item: %s", e.message);
		}
	}

	private void secondary_activate(Gdk.EventButton event) {
		try {
			dbus_item.secondary_activate((int) event.x_root, (int) event.y_root);
		} catch (DBusError e) {
			// this happens if the application doesn't implement the secondary activate dbus method
			debug("Failed to call secondary activate method on StatusNotifier item: %s", e.message);
		} catch (IOError e) {
			warning("Failed to call secondary activate method on StatusNotifier item: %s", e.message);
		}
	}

	private void show_context_menu(Gdk.EventButton event) {
		if (context_menu != null) {
			context_menu.popup_at_pointer(event);
		} else try {
			dbus_item.context_menu((int) event.x_root, (int) event.y_root);
		} catch (DBusError e) {
			// this happens if the application doesn't implement the context menu dbus method
			debug("Failed to show context menu on StatusNotifier item: %s", e.message);
		} catch (IOError e) {
			warning("Failed to show context menu on StatusNotifier item: %s", e.message);
		}
	}

	public void resize(int applet_size) {
		if (applet_size > FORMULA_SWAP_POINT) {
			target_icon_size = applet_size - TARGET_ICON_PADDING;
		} else {
			target_icon_size = (int) Math.round(TARGET_ICON_SCALE * applet_size);
		}

		reset_icon();
	}
}
