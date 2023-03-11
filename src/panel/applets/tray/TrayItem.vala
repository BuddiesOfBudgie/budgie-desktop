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

public struct SnIconPixmap {
	int width;
	int height;
	uint8[] data;
}

public struct SnToolTip {
	string icon_name;
	SnIconPixmap[] icon_data;
	string title;
	string markup;
}

const double TARGET_ICON_SCALE = 2.0 / 3.0;

[DBus (name="org.kde.StatusNotifierItem")]
internal interface SnItemProperties : Object {
	public abstract string category {owned get;}
	public abstract string id {owned get;}
	public abstract string title {owned get;}
	public abstract string status {owned get;}
	public abstract uint32 window_id {get;}
	public abstract string icon_name {owned get;}
	public abstract SnIconPixmap[] icon_pixmap {owned get;}
	public abstract string overlay_icon_name {owned get;}
	public abstract SnIconPixmap[] overlay_icon_pixmap {owned get;}
	public abstract string attention_icon_name {owned get;}
	public abstract SnIconPixmap[] attention_icon_pixmap {owned get;}
	public abstract string attention_movie_name {owned get;}
	public abstract string icon_theme_path {owned get;}
	public abstract SnToolTip? tool_tip {owned get;}
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

internal class TrayItem : Gtk.EventBox {
	private SnItemInterface dbus_item;
	private SnItemProperties dbus_properties;

	private string dbus_name;
	private string dbus_object_path;

	private DBusMenu context_menu;

	private string? icon_theme_path = null;
	private Gtk.Image primary_icon;
	private Gtk.Image overlay_icon;

	public int target_icon_size = 8;

	public TrayItem(string dbus_name, string dbus_object_path, int applet_size) throws DBusError, IOError {
		this.dbus_item = Bus.get_proxy_sync(BusType.SESSION, dbus_name, dbus_object_path);
		this.dbus_properties = Bus.get_proxy_sync(BusType.SESSION, dbus_name, dbus_object_path);

		this.dbus_name = dbus_name;
		this.dbus_object_path = dbus_object_path;

		add_events(Gdk.EventMask.SCROLL_MASK);

		reset_icon_theme();

		primary_icon = new Gtk.Image();
		overlay_icon = new Gtk.Image();

		var overlay = new Gtk.Overlay();
		overlay.add(primary_icon);
		overlay.add_overlay(overlay_icon);

		resize(applet_size);
		add(overlay);

		reset_tooltip();

		if (dbus_properties.menu != null) {
			context_menu = new DBusMenu(dbus_name, dbus_properties.menu);
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
		string? icon_name = null;
		SnIconPixmap[] icon_pixmaps = {};
		if ((status ?? dbus_properties.status) == "NeedsAttention") {
			icon_name = dbus_properties.attention_icon_name;
			icon_pixmaps = dbus_properties.attention_icon_pixmap;
		} else {
			icon_name = dbus_properties.icon_name;
			icon_pixmaps = dbus_properties.icon_pixmap;
		}

		update_icon(primary_icon, icon_name, icon_pixmaps, "application-default-icon");
		update_icon(overlay_icon, dbus_properties.overlay_icon_name, dbus_properties.overlay_icon_pixmap, null);

		if (target_icon_size > 0) {
			primary_icon.pixel_size = target_icon_size;
			overlay_icon.pixel_size = target_icon_size;
		}
	}

	private void update_icon(Gtk.Image icon, string? icon_name, SnIconPixmap[] icon_pixmaps, string? fallback_icon_name) {
		SnIconPixmap? icon_pixmap = null;
		foreach (SnIconPixmap pixmap in icon_pixmaps) {
			icon_pixmap = pixmap;
			if (icon_pixmap.width >= target_icon_size && icon_pixmap.height >= target_icon_size) {
				break;
			}
		}

		if (icon_name != null && icon_name.length > 0) {
			var icon_theme = Gtk.IconTheme.get_default();
			if (icon_theme_path != null && !icon_theme.has_icon(icon_name)) {
				icon_theme.prepend_search_path(icon_theme_path);
			}
			icon.set_from_icon_name(icon_name, Gtk.IconSize.LARGE_TOOLBAR);
			icon.visible = true;
		} else if (icon_pixmap != null) {
			// ARGB32 to RGBA32
			var array = icon_pixmap.data.copy();
			for (var i = 0; i < icon_pixmap.data.length; i += 4) {
				array[i] = icon_pixmap.data[i + 1];
				array[i + 1] = icon_pixmap.data[i + 2];
				array[i + 2] = icon_pixmap.data[i + 3];
				array[i + 3] = icon_pixmap.data[i];
			}

			var pixbuf = new Gdk.Pixbuf.from_data(
				array,
				Gdk.Colorspace.RGB,
				true,
				8,
				icon_pixmap.width, icon_pixmap.height,
				Cairo.Format.ARGB32.stride_for_width(icon_pixmap.width)
			);
			pixbuf = pixbuf.scale_simple(target_icon_size, target_icon_size, Gdk.InterpType.BILINEAR);
			icon.set_from_pixbuf(pixbuf);
			icon.visible = true;
		} else if (fallback_icon_name != null) {
			icon.set_from_icon_name(fallback_icon_name, Gtk.IconSize.LARGE_TOOLBAR);
		} else {
			icon.visible = false;
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
		if (event.button == 2) { // Middle click
			secondary_activate(event);
			return Gdk.EVENT_STOP;
		} else if (event.button == 3 || dbus_properties.item_is_menu) { // Right click
			show_context_menu(event);
			return Gdk.EVENT_STOP;
		} else if (event.button == 1) { // Left click
			primary_activate(event);
			return Gdk.EVENT_STOP;
		}

		return base.button_release_event(event);
	}

	public override bool scroll_event(Gdk.EventScroll event) {
		switch (event.direction) {
			case Gdk.ScrollDirection.UP:
				send_scroll_event(1, "vertical");
				return Gdk.EVENT_STOP;
			case Gdk.ScrollDirection.DOWN:
				send_scroll_event(-1, "vertical");
				return Gdk.EVENT_STOP;
			case Gdk.ScrollDirection.LEFT:
				send_scroll_event(-1, "horizontal");
				return Gdk.EVENT_STOP;
			case Gdk.ScrollDirection.RIGHT:
				send_scroll_event(1, "horizontal");
				return Gdk.EVENT_STOP;
			default: {
				if (Math.fabs(event.delta_x) > 0.0) {
					send_scroll_event((int) Math.ceil(event.delta_x), "horizontal");
				}

				if (Math.fabs(event.delta_y) > 0.0) {
					send_scroll_event((int) Math.ceil(event.delta_y), "vertical");
				}

				return Gdk.EVENT_STOP;
			}
		}
	}

	private void primary_activate(Gdk.EventButton event) {
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

	private void send_scroll_event(int delta, string orientation) {
		try {
			dbus_item.scroll(delta, orientation);
		} catch (DBusError e) {
			// this happens if the application doesn't implement the scroll dbus method
			debug("Failed to call scroll method on StatusNotifier item: %s", e.message);
		} catch (IOError e) {
			warning("Failed to call scroll method on StatusNotifier item: %s", e.message);
		}
	}

	public void resize(int applet_size) {
		target_icon_size = (int) Math.round(TARGET_ICON_SCALE * applet_size);
		reset_icon();
	}
}
