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

private struct MenuItem {
	string type;
	bool enabled;
	bool visible;
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

				build_menu();

				dbus_menu.layout_updated.connect((revision, parent_id) => {
					build_menu();
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
				var icon_theme = new Gtk.IconTheme();
				icon_theme.append_search_path(icon_theme_path);
				icon.set_from_pixbuf(icon_theme.load_icon(icon_name, target_icon_size, Gtk.IconLookupFlags.FORCE_SIZE));
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

	private void build_menu() {
		uint32 revision;
		Variant layout;

		try {
			dbus_menu.get_layout(0, -1, null, out revision, out layout);
		} catch (Error e) {
			warning("Failed to get layout for dbus menu: %s", e.message);
			return;
		}

		int32 id = layout.get_child_value(0).get_int32();
		Variant properties = layout.get_child_value(1);
		Variant children = layout.get_child_value(2);

		context_menu = new Gtk.Menu();
		bool last_is_separator = true;

		VariantIter it = children.iterator();
		for (var child = it.next_value(); child != null; child = it.next_value()) {
			child = child.get_variant();

			int32 child_id = child.get_child_value(0).get_int32();
			Variant child_properties = child.get_child_value(1);
			HashTable<string, Variant?> props_table = new HashTable<string, Variant?>(str_hash, str_equal);

			VariantIter prop_it = child_properties.iterator();
			string key;
			Variant value;
			while (prop_it.next("{sv}", out key, out value)) {
				props_table.set(key, value);
			}

			if (props_table.contains("visible") && !props_table.get("visible").get_boolean()) {
				continue;
			}

			Gtk.MenuItem item = null;
			if (props_table.contains("type")) {
				if (props_table.get("type").get_string() == "separator" &&
					context_menu.get_children().length() != 0 &&
					!last_is_separator
				) {
					item = new Gtk.SeparatorMenuItem();
					last_is_separator = true;
				}
			} else if (props_table.contains("toggle-type")) {
				if (props_table.get("toggle-type").get_string() == "checkmark") {
					Gtk.CheckMenuItem check_item = new Gtk.CheckMenuItem.with_mnemonic(props_table.get("label").get_string());
					check_item.set_active(props_table.contains("toggle-state") && props_table.get("toggle-state").get_int32() != 0);
					check_item.toggled.connect(() => {
						dbus_menu.event(child_id, "clicked", new Variant.boolean(check_item.get_active()), (uint32) get_real_time());
					});
					item = check_item;
					last_is_separator = false;
				}
			} else {
				item = new Gtk.MenuItem.with_mnemonic(props_table.get("label").get_string());
				item.activate.connect(() => {
					dbus_menu.event(child_id, "clicked", new Variant.int32(0), (uint32) get_real_time());
				});
				last_is_separator = false;
			}

			if (item != null) {
				if (props_table.contains("enabled") && props_table.contains("enabled") && !props_table.get("enabled").get_boolean()) {
					item.set_sensitive(false);
				}
				context_menu.add(item);
			}
		}

		context_menu.show_all();
	}

	//  private Gtk.MenuItem build_menu_item(Variant layout) {

	//  }

	public override bool button_release_event(Gdk.EventButton event) {
		warning("Received button release event: x=%f, y=%f, x_root=%f, y_root=%f", event.x, event.y, event.x_root, event.y_root);

		try {
			if (event.button == 3) { // Right click
				if (context_menu != null) {
					context_menu.popup_at_pointer(event);
				} else {
					dbus_item.context_menu((int) event.x_root, (int) event.y_root);
				}

				return Gdk.EVENT_STOP;
			} else if (event.button == 1) { // Left click
				dbus_item.activate((int) event.x_root, (int) event.y_root);
				return Gdk.EVENT_STOP;
			} else if (event.button == 2) { // Middle click
				dbus_item.secondary_activate((int) event.x_root, (int) event.y_root);
				return Gdk.EVENT_STOP;
			}
		} catch (Error e) {
			warning("Failed to process button event: %s", e.message);
		}

		return base.button_release_event(event);
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
