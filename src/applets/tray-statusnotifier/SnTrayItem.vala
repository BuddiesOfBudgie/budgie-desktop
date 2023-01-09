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

	private DbusmenuGtk.Menu? context_menu;

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
			context_menu = new DbusmenuGtk.Menu(dbus_name, dbus_properties.menu);
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
