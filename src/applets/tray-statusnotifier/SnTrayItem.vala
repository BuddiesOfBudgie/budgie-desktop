public struct IconPixmap {
	int width;
	int height;
	char[] data;
}

[DBus (name="org.kde.StatusNotifierItem")]
public interface StatusNotifierItem : Object {
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
	//  public abstract Variant tool_tip {owned get;}
	public abstract bool item_is_menu {owned get;}
	//  public abstract Variant menu {owned get;}

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

public class SnTrayItem : Gtk.EventBox {
	private StatusNotifierItem dbus_item;
	public Gtk.Image icon {get; private set;}

	public SnTrayItem(StatusNotifierItem dbus_item) {
		warning("Creating new tray icon with icon theme path %s", dbus_item.icon_theme_path);

		this.dbus_item = dbus_item;

		icon = new Gtk.Image();
		icon.pixel_size = 24;
		reset_icon();
		add(icon);

		dbus_item.new_icon.connect(reset_icon);
		show_all();
	}

	private void reset_icon() {
		if (dbus_item.icon_theme_path != null) {
			Gtk.IconTheme icon_theme = new Gtk.IconTheme();
			icon_theme.append_search_path(dbus_item.icon_theme_path);
			icon.set_from_pixbuf(icon_theme.load_icon(dbus_item.icon_name, 24, Gtk.IconLookupFlags.FORCE_SIZE));
		} else {
			icon.set_from_icon_name(dbus_item.icon_name, Gtk.IconSize.INVALID);
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
}
