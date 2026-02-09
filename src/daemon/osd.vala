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

namespace Budgie {
	/**
	* Default width for an OSD notification
	*/
	public const int OSD_SIZE = 350;

	/**
	* How long before the visible OSD expires, default is 2.5 seconds
	*/
	public const int OSD_EXPIRE_TIME = 2500;

	/**
	* Our name on the session bus. Reserved for Budgie use
	*/
	public const string OSD_DBUS_NAME = "org.budgie_desktop.BudgieOSD";

	/**
	* Unique object path on OSD_DBUS_NAME
	*/
	public const string OSD_DBUS_OBJECT_PATH = "/org/budgie_desktop/BudgieOSD";


	/**
	* The BudgieOSD provides a very simplistic On Screen Display service, complying with the
	* private GNOME Settings Daemon -> GNOME Shell protocol.
	*
	* In short, all elements of the permanently present window should be able to hide or show
	* depending on the updated Show message, including support for a progress bar (level),
	* icon, optional label.
	*
	* This OSD is used by gnome-settings-daemon to portray special events, such as brightness/volume
	* changes, physical volume changes (disk eject/mount), etc. This special window should remain
	* above all other windows and be non-interactive, allowing unobtrosive overlay of information
	* even in full screen movies and games.
	*
	* Each request to Show will reset the expiration timeout for the OSD's current visibility,
	* meaning subsequent requests to the OSD will keep it on screen in a natural fashion, allowing
	* users to "hold down" the volume change buttons, for example.
	*/
	[GtkTemplate (ui="/com/solus-project/budgie/daemon/osd.ui")]
	public class OSD : Gtk.Window {
		/**
		* Main text display
		*/
		[GtkChild]
		private unowned Gtk.Label label_title;

		/**
		* Main display image. Prefer symbolic icons!
		*/
		[GtkChild]
		private unowned Gtk.Image image_icon;

		/**
		* Optional progressbar
		*/
		[GtkChild]
		public unowned Gtk.ProgressBar progressbar;

		/**
		* Current text to display. NULL hides the widget.
		*/
		public string? osd_title {
			public set {
				string? r = value;
				if (r == null) {
					label_title.set_visible(false);
				} else {
					label_title.set_visible(true);
					label_title.set_markup(r);
				}
			}
			public owned get {
				if (!label_title.get_visible()) {
					return null;
				}
				return label_title.get_label();
			}
		}

		/**
		* Current icon to display. NULL hides the widget
		*/
		public string? osd_icon {
			public set {
				string? r = value;
				if (r == null) {
					image_icon.set_visible(false);
				} else {
					image_icon.set_from_icon_name(r, Gtk.IconSize.INVALID);
					image_icon.pixel_size = 48;
					image_icon.set_visible(true);
				}
			}
			public owned get {
				if (!image_icon.get_visible()) {
					return null;
				}
				string ret;
				Gtk.IconSize _icon_size;
				image_icon.get_icon_name(out ret, out _icon_size);
				return ret;
			}
		}

		/**
		* Construct a new BudgieOSD widget
		*/
		public OSD() {
			Object(type: Gtk.WindowType.POPUP, type_hint: Gdk.WindowTypeHint.NOTIFICATION);
			/* Skip everything, appear above all else, everywhere. */
			resizable = false;
			skip_pager_hint = true;
			skip_taskbar_hint = true;

			GtkLayerShell.init_for_window(this);
			GtkLayerShell.set_layer(this, GtkLayerShell.Layer.OVERLAY);
			GtkLayerShell.set_margin(this, GtkLayerShell.Edge.BOTTOM, 80);
			GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.BOTTOM, true);

			set_decorated(false);
			stick();

			/* Set up an RGBA map for transparency styling */
			Gdk.Visual? vis = screen.get_rgba_visual();
			if (vis != null) {
				this.set_visual(vis);
			}

			/* Set up size */
			set_default_size(OSD_SIZE, -1);
			realize();

			osd_title = null;
			osd_icon = null;

			get_child().show_all();
			set_visible(false);

			move_osd();
		}

		/**
		* Move the OSD into the correct position
		*/
		public void move_osd() {
			var wayland_client = new WaylandClient();

			if (!wayland_client.is_initialised()) {
				warning("Cannot move OSD: WaylandClient not initialized");
				return;
			}

			wayland_client.with_valid_monitor(() => {
				var monitor = wayland_client.gdk_monitor;
				if (monitor != null) {
					GtkLayerShell.set_monitor(this, monitor);
				} else {
					warning("Failed to get valid monitor for OSD");
				}
				return true;
			});
		}
	}

	/**
	* BudgieOSDManager is responsible for managing the BudgieOSD over d-bus, receiving
	* requests, for example, from budgie-wm
	*/
	[DBus (name="org.budgie_desktop.BudgieOSD")]
	public class OSDManager {
		private OSD? osd_window = null;
		private uint32 expire_timeout = 0;

		// Signal to notify when OSD service is ready
		public signal void ready();

		private bool _is_ready = false;

		[DBus (visible=false)]
		public OSDManager() {
			osd_window = new OSD();
		}

		/**
		* Own the OSD_DBUS_NAME
		*/
		[DBus (visible=false)]
		public void setup_dbus(bool replace) {
			var flags = BusNameOwnerFlags.ALLOW_REPLACEMENT;
			if (replace) {
				flags |= BusNameOwnerFlags.REPLACE;
			}
			Bus.own_name(BusType.SESSION, Budgie.OSD_DBUS_NAME, flags,
				on_bus_acquired,
				on_name_acquired,
				Budgie.DaemonNameLost);
		}

		/**
		* Acquired OSD_DBUS_NAME, register ourselves on the bus
		*/
		private void on_bus_acquired(DBusConnection conn) {
			try {
				conn.register_object(Budgie.OSD_DBUS_OBJECT_PATH, this);
				debug("OSDManager: Registered object on DBus");
			} catch (Error e) {
				critical("Error registering BudgieOSD: %s\n", e.message);
			}
			Budgie.setup = true;
		}

		/**
		* Called when name is acquired on the bus
		*/
		private void on_name_acquired() {
			if (!_is_ready) {
				_is_ready = true;
				debug("OSDManager: Name acquired, service is ready");
				ready();
			}
		}

		/**
		* Show the OSD on screen with the given parameters:
		* icon: string Icon-name to use
		* label: string Text to display, if any
		* level: Progress-level to display in the OSD (double or int32 depending on gsd release)
		* monitor: int32 The monitor to display the OSD on (currently ignored)
		*/
		public void Show(HashTable<string,Variant> params) throws DBusError, IOError {
			string? icon_name = null;
			string? label = null;

			if (params.contains("icon")) {
				var icon_variant = params.lookup("icon");
				if (icon_variant != null) {
					icon_name = icon_variant.get_string();
				}
			}

			if (params.contains("label")) {
				var label_variant = params.lookup("label");
				if (label_variant != null) {
					label = label_variant.get_string();
				}
			}

			double prog_value = -1;

			if (params.contains("level")) {
				var level_variant = params.lookup("level");
				if (level_variant != null) {
	#if USE_GSD_DOUBLES
					prog_value = level_variant.get_double();
	#else
					int32 prog_int = level_variant.get_int32();
					prog_value = prog_int.clamp(0, 100) / 100.0;
	#endif
				}
			}

			/* Update the OSD accordingly */
			osd_window.osd_title = label;
			osd_window.osd_icon = icon_name;

			if (prog_value < 0) {
				osd_window.progressbar.set_visible(false);
			} else {
				osd_window.progressbar.set_fraction(prog_value);
				osd_window.progressbar.set_visible(true);
			}

			this.reset_osd_expire(OSD_EXPIRE_TIME);
		}

		/**
		* Reset and update the expiration for the OSD timeout
		*/
		private void reset_osd_expire(int timeout_length) {
			if (expire_timeout > 0) {
				Source.remove(expire_timeout);
				expire_timeout = 0;
			}

			osd_window.show();
			osd_window.move_osd();

			expire_timeout = Timeout.add(timeout_length, this.osd_expire);
		}

		/**
		* Expiration timeout was met, so hide the OSD Window
		*/
		private bool osd_expire() {
			if (expire_timeout == 0) {
				return false;
			}

			osd_window.hide();
			expire_timeout = 0;

			return false;
		}
	}
}
