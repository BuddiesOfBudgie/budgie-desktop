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
}

[DBus (name="org.kde.StatusNotifierItem")]
internal interface SnItemInterface : Object {
	public abstract string category {owned get;}
	public abstract string id {owned get;}
	public abstract string title {owned get;}
	public abstract string status {owned get;}
	public abstract uint32 window_id {owned get;}
	public abstract string icon_name {owned get;}
	public abstract IconPixmap[] icon_pixmap {owned get;}
	public abstract string overlay_icon_name {owned get;}
	public abstract IconPixmap[] overlay_icon_pixmap {owned get;}
	public abstract string attention_icon_name {owned get;}
	public abstract IconPixmap[] attention_icon_pixmap {owned get;}
	public abstract string attention_movie_name {owned get;}
	public abstract string icon_theme_path {owned get;}
	public abstract ToolTip? tool_tip {owned get;}
	public abstract bool item_is_menu {owned get;}
	public abstract ObjectPath? menu {owned get;}

	public abstract void context_menu(int x, int y) throws DBusError, IOError;
	public abstract void activate(int x, int y) throws DBusError, IOError;
	public abstract void secondary_activate(int x, int y) throws DBusError, IOError;
	public abstract void scroll(int delta, string orientation) throws DBusError, IOError;

	public abstract signal void new_title();
	public abstract signal void new_icon();
	public abstract signal void new_attention_icon();
	public abstract signal void new_overlay_icon();
	public abstract signal void new_tool_tip();
	public abstract signal void new_status();
}

internal class SnTrayItem : Gtk.EventBox {
	private SnItemInterface dbus_item;
	private string dbus_name;
	private DBusMenuInterface? dbus_menu;

	public Gtk.Image icon {get; private set;}
	public int target_icon_size = 8;

	public SnTrayItem(SnItemInterface dbus_item, string dbus_name, int applet_size) {
		warning("Creating new tray icon with icon theme path %s", dbus_item.icon_theme_path);

		this.dbus_item = dbus_item;
		this.dbus_name = dbus_name;

		icon = new Gtk.Image();
		resize(applet_size);
		add(icon);

		reset_tooltip();

		if (dbus_item.menu != null) {
			try {
				dbus_menu = Bus.get_proxy_sync(BusType.SESSION, dbus_name, dbus_item.menu);

				build_menu();
			} catch (Error e) {
				warning("Failed to get a proxy object for tray item menu: %s", e.message);
			}
		}

		dbus_item.new_icon.connect(reset_icon);
		dbus_item.new_status.connect(reset_icon);
		dbus_item.new_tool_tip.connect(reset_tooltip);
		show_all();
	}

	private void reset_icon() {
		string icon_name;
		if (dbus_item.status == "NeedsAttention") {
			icon_name = dbus_item.attention_icon_name;
		} else {
			icon_name = dbus_item.icon_name;
		}

		if (dbus_item.icon_theme_path != null) {
			Gtk.IconTheme icon_theme = new Gtk.IconTheme();
			icon_theme.append_search_path(dbus_item.icon_theme_path);
			icon.set_from_pixbuf(icon_theme.load_icon(icon_name, target_icon_size, Gtk.IconLookupFlags.FORCE_SIZE));
		} else {
			icon.set_from_icon_name(icon_name, Gtk.IconSize.INVALID);
		}

		if (target_icon_size > 0) {
			this.icon.pixel_size = target_icon_size;
		}
	}

	private void reset_tooltip() {
		if (dbus_item.tool_tip != null) {
			if (dbus_item.tool_tip.markup != "") {
				set_tooltip_markup(dbus_item.tool_tip.markup);
			} else {
				set_tooltip_text(dbus_item.tool_tip.title);
			}
		} else {
			set_tooltip_text(null);
		}
	}

	private void build_menu() {
		string[] props = {"type", "children-display"};
		uint32 revision;
		Variant layout;

		try {
			dbus_menu.get_layout(0, -1, props, out revision, out layout);
		} catch (Error e) {
			warning("Failed to get layout for dbus menu: %s", e.message);
		}
	}

	public override bool button_release_event(Gdk.EventButton event) {
		warning("Received button release event: x=%f, y=%f, x_root=%f, y_root=%f", event.x, event.y, event.x_root, event.y_root);
		try {
			if (event.button == 3) { // Right click
				dbus_item.context_menu((int) event.x_root, (int) event.y_root);
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
