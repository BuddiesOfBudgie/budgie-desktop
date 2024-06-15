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
	public const string RAVEN_DBUS_NAME = "org.budgie_desktop.Raven";
	public const string RAVEN_DBUS_OBJECT_PATH = "/org/budgie_desktop/Raven";

	/**
	 * Possible positions for Raven to be in.
	 *
	 * Automatic positioning will make Raven open on whichever side
	 * of the screen that the Raven toggle button is on.
	 */
	public enum RavenPosition {
		AUTOMATIC = 1,
		LEFT = 2,
		RIGHT = 3;

		/**
		 * Get a user-friendly localized name for the position.
		 */
		public string get_display_name() {
			switch (this) {
			case RavenPosition.LEFT:
				return _("Left");
			case RavenPosition.RIGHT:
				return _("Right");
			case RavenPosition.AUTOMATIC:
			default:
				return _("Automatic");
			}
		}
	}

	public enum NotificationSort {
		NEW_OLD = 1,
		OLD_NEW = 2;

		public string get_display_name() {
			switch (this) {
				case OLD_NEW: return _("Oldest to newest");
				case NEW_OLD:
				default:
					return _("Newest to oldest");
			}
		}
	}

	[DBus (name="org.budgie_desktop.Raven")]
	public class RavenIface {
		private Raven? parent = null;

		[DBus (visible=false)]
		public uint notifications = 0;

		[DBus (visible=false)]
		public RavenIface(Raven? parent) {
			this.parent = parent;
		}

		public bool is_expanded {
			public get {
				return parent.get_expanded();
			}

			public set {
				parent.set_expanded(value);
			}
		}

		public void ClearNotifications() throws DBusError, IOError {
			notifications = 0; // Set our notifications to zero
			this.ReadNotifications(); // Call our ReadNotifications signal
			this.ClearAllNotifications(); // Call our ClearAllNotifications signal
		}

		public signal void ExpansionChanged(bool expanded);
		public signal void AnchorChanged(bool anchored);

		public bool GetExpanded() throws DBusError, IOError {
			return this.is_expanded;
		}

		public bool GetLeftAnchored() throws DBusError, IOError {
			return parent.screen_edge == Gtk.PositionType.LEFT;
		}

		public void SetExpanded(bool b) throws DBusError, IOError {
			this.is_expanded = b;
		}

		public void Toggle() throws DBusError, IOError {
			this.is_expanded = !this.is_expanded;

			if (this.is_expanded) {
				if (this.notifications == 0){
					parent.expose_main_view();
				} else {
					parent.expose_notification();
					this.ReadNotifications();
				}
			}
		}

		/**
		* Toggle Raven, opening only the "main" applet view
		*/
		public void ToggleAppletView() throws DBusError, IOError {
			if (this.is_expanded) {
				this.is_expanded = !this.is_expanded;
				return;
			}
			parent.expose_main_view();
			this.is_expanded = !this.is_expanded;
		}

		/**
		* Toggle Raven, opening only the "main" applet view
		*/
		public void ToggleNotificationsView() throws DBusError, IOError {
			if (this.is_expanded) {
				this.is_expanded = !this.is_expanded;
				return;
			}
			parent.expose_notification();
			this.is_expanded = !this.is_expanded;
		}

		public void Dismiss() throws DBusError, IOError {
			if (this.is_expanded) {
				this.is_expanded = !this.is_expanded;
			}
		}


		public signal void NotificationsChanged();

		public uint GetNotificationCount() throws DBusError, IOError {
			return this.notifications;
		}

		public signal void ClearAllNotifications();
		public signal void UnreadNotifications();
		public signal void ReadNotifications();

		public string get_version() throws DBusError, IOError {
			return "1";
		}
	}

	public class Raven : Gtk.Window {
		private static Raven? _instance = null;

		private Gtk.PositionType _screen_edge = Gtk.PositionType.RIGHT;

		private List<Budgie.RavenWidgetData>? widgets = null;

		/* Anchor to the right by default */
		public Gtk.PositionType screen_edge {
			public set {
				this._screen_edge = value;
				bool is_right = this._screen_edge == Gtk.PositionType.RIGHT;

				if (this.iface != null) {
					this.iface.AnchorChanged(this.screen_edge == Gtk.PositionType.LEFT);
				}

				if (is_right) {
					layout.child_set(shadow, "position", 0);
					this.get_style_context().add_class(Budgie.position_class_name(PanelPosition.RIGHT));
					this.get_style_context().remove_class(Budgie.position_class_name(PanelPosition.LEFT));
					this.shadow.position = Budgie.PanelPosition.RIGHT;
				} else {
					layout.child_set(shadow, "position", 1);
					this.get_style_context().add_class(Budgie.position_class_name(PanelPosition.LEFT));
					this.get_style_context().remove_class(Budgie.position_class_name(PanelPosition.RIGHT));
					this.shadow.position = Budgie.PanelPosition.LEFT;
				}

				GtkLayerShell.Edge raven_edge = is_right ? GtkLayerShell.Edge.RIGHT : GtkLayerShell.Edge.LEFT;
				GtkLayerShell.Edge old_edge = is_right ? GtkLayerShell.Edge.LEFT : GtkLayerShell.Edge.RIGHT;

				GtkLayerShell.set_anchor(
					this,
					old_edge,
					false
				);

				GtkLayerShell.set_anchor(
					this,
					raven_edge,
					true
				);
		}
			public get {
				return this._screen_edge;
			}
		}

		int our_width = 0;
		int our_height = 0;

		private Budgie.ShadowBlock? shadow;
		private RavenIface? iface = null;
		private Settings? settings = null;
		private Settings? widget_settings = null;

		bool expanded = false;

		Gdk.Rectangle old_rect;
		Gtk.Box layout;

		private double scale = 0.0;

		public int required_size { public get ; protected set; }

		private Budgie.MainView? main_view = null;

		private uint n_count = 0;

		public Budgie.DesktopManager? manager { public set; public get; }

		private unowned Budgie.RavenPluginManager? plugin_manager;

		public double nscale {
			public set {
				scale = value;
			}
			public get {
				return scale;
			}
		}

		public void ReadNotifications() {
			if (iface != null) {
				iface.ReadNotifications();
			}
		}

		public void UnreadNotifications() {
			if (iface != null) {
				iface.UnreadNotifications();
			}
		}

		private void on_bus_acquired(DBusConnection conn) {
			try {
				iface = new RavenIface(this);
				conn.register_object(Budgie.RAVEN_DBUS_OBJECT_PATH, iface);
				plugin_manager.setup_plugins();
				load_existing_widgets();
			} catch (Error e) {
				stderr.printf("Error registering Raven: %s\n", e.message);
				Process.exit(1);
			}
		}

		public void expose_main_view() {
			main_view.set_clean();
		}

		public void expose_notification() {
			main_view.expose_notification();
		}

		public static unowned Raven? get_instance() {
			return Raven._instance;
		}

		public void set_notification_count(uint count) {
			if (this.n_count != count && this.iface != null) {
				this.n_count = count;
				this.iface.notifications = count;
				this.iface.NotificationsChanged();
			}
		}

		bool on_focus_out() {
			if (this.expanded) {
				this.set_expanded(false);
			}
			return Gdk.EVENT_PROPAGATE;
		}

		private void steal_focus() {
			unowned Gdk.Window? window = get_window();
			if (window == null) {
				return;
			}
			if (!has_toplevel_focus) {
				/* X11 specific. */
				Gdk.Display? display = screen.get_display();
				if (display is Gdk.X11.Display) {
					window.focus(((Gdk.X11.Display) display).get_user_time());
				} else {
					window.focus(Gtk.get_current_event_time());
				}
			}
		}

		public Raven(Budgie.DesktopManager? manager, Budgie.RavenPluginManager? plugin_manager) {
			Object(type_hint: Gdk.WindowTypeHint.DOCK, manager: manager);
			if (libxfce4windowing.windowing_get() == libxfce4windowing.Windowing.WAYLAND) {
				GtkLayerShell.init_for_window(this);
				GtkLayerShell.set_layer(this, GtkLayerShell.Layer.OVERLAY);
			}

			get_style_context().add_class("budgie-container");

			settings = new Settings("com.solus-project.budgie-raven");

			widget_settings = new Settings("org.buddiesofbudgie.budgie-desktop.raven.widgets");

			Raven._instance = this;

			this.widgets = new List<RavenWidgetData>();
			this.plugin_manager = plugin_manager;

			var vis = screen.get_rgba_visual();
			if (vis == null) {
				warning("No RGBA functionality");
			} else {
				set_visual(vis);
			}

			// Response to a scale factor change
			notify["scale-factor"].connect(() => {
				this.update_geometry(this.old_rect);
				queue_resize();
			});

			focus_out_event.connect(on_focus_out);

			/* Set up our main layout */
			layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
			add(layout);

			enter_notify_event.connect((e) => {
				steal_focus();
				return Gdk.EVENT_PROPAGATE;
			});

			shadow = new Budgie.ShadowBlock(PanelPosition.RIGHT);
			layout.pack_start(shadow, false, false, 0);
			/* For now Raven is always on the right */

			var frame = new Gtk.Frame(null);
			frame.get_style_context().add_class("raven-frame");
			layout.pack_start(frame, true, true, 0);

			var main_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			main_box.get_style_context().add_class("raven");
			frame.add(main_box);

			/* Applets + Notifications */
			main_view = new Budgie.MainView();
			main_box.pack_start(main_view, true, true, 0);

			// TODO HACK: see if there is an opportunity for improvement when on magpie v1
			set_default_size(400, -1);

			main_view.requested_draw.connect(() => {
				queue_draw();
			});

			resizable = false;
			skip_taskbar_hint = true;
			skip_pager_hint = true;
			set_keep_above(true);
			set_decorated(false);

			//set_size_request(-1, -1);
			if (!this.get_realized()) {
				this.realize();
			}

			this.get_child().show_all();

			this.screen_edge = Gtk.PositionType.RIGHT;
		}

		public override void size_allocate(Gtk.Allocation rect) {
			int w = 0;

			base.size_allocate(rect);
			if ((w = get_allocated_width()) != this.required_size) {
				this.required_size = w;
				this.update_geometry(this.old_rect);
			}
		}

		public void setup_dbus() {
			Bus.own_name(BusType.SESSION, Budgie.RAVEN_DBUS_NAME, BusNameOwnerFlags.ALLOW_REPLACEMENT|BusNameOwnerFlags.REPLACE,
				on_bus_acquired, () => {}, () => { warning("Raven could not take dbus!"); });
		}

		/**
		* Update our geometry based on other panels in the neighbourhood, and the screen we
		* need to be on */
		public void update_geometry(Gdk.Rectangle rect) {
			int width = layout.get_allocated_width();

			int height = rect.height;

			this.old_rect = rect;

			our_height = height;
			our_width = width;

			if (!get_visible()) {
				queue_resize();
			}
		}

		public override void get_preferred_height(out int m, out int n) {
			m = our_height;
			n = our_height;
		}

		public override void get_preferred_height_for_width(int w, out int m, out int n) {
			m = our_height;
			n = our_height;
		}

		public override bool draw(Cairo.Context cr) {
			if (nscale == 0.0 || nscale == 1.0) {
				return base.draw(cr);
			}

			/* Clear out the background before we draw anything */
			cr.save();
			cr.set_source_rgba(1.0, 1.0, 1.0, 0.0);
			cr.set_operator(Cairo.Operator.SOURCE);
			cr.paint();
			cr.restore();

			var window = this.get_window();
			if (window == null) {
				return Gdk.EVENT_STOP;
			}

			Gtk.Allocation alloc;
			get_allocation(out alloc);
			/* Create a compatible buffer for the current scaling factor */
			var buffer = window.create_similar_image_surface(Cairo.Format.ARGB32,
															alloc.width * this.scale_factor,
															alloc.height * this.scale_factor,
															this.scale_factor);
			var cr2 = new Cairo.Context(buffer);

			propagate_draw(get_child(), cr2);
			var x = ((double)alloc.width) * nscale;

			if (this.screen_edge == Gtk.PositionType.RIGHT) {
				cr.set_source_surface(buffer, alloc.width - x, 0);
			} else {
				cr.set_source_surface(buffer, x - alloc.width, 0);
			}

			cr.paint();

			return Gdk.EVENT_STOP;
		}

		/**
		* Slide Raven in or out of view
		*/
		public void set_expanded(bool exp) {

			if (exp == this.expanded) {
				return;
			}
			double old_nscale_op, new_nscale_op;
			if (exp) {
				this.update_geometry(this.old_rect);
				old_nscale_op = 0.0;
				new_nscale_op = 1.0;
			} else {
				old_nscale_op = 1.0;
				new_nscale_op = 0.0;
			}
			nscale = old_nscale_op;

			this.expanded = exp;
			main_view.raven_expanded(this.expanded);
			this.iface.ExpansionChanged(this.expanded);

			if (!this.get_settings().gtk_enable_animations) {
				if (!exp) {
					this.nscale = 0.0;
					this.hide();
				} else {
					this.nscale = 1.0;
					this.present();
					this.grab_focus();
					this.steal_focus();
				}
				return;
			}

			var anim = new Budgie.Animation();
			anim.widget = this;
			if (exp) {
				anim.length = 360 * Budgie.MSECOND;
				anim.tween = Budgie.expo_ease_out;
			} else {
				anim.tween = Budgie.sine_ease_in;
				anim.length = 190 * Budgie.MSECOND;
			}
			anim.changes = new Budgie.PropChange[] {
				Budgie.PropChange() {
					property = "nscale",
					old = old_nscale_op,
					@new = new_nscale_op
				},
			};

			if (!exp) { // Going to be hiding Raven
				shadow.set_opacity(0.0); // Hide the shadow since it gets glitchy
				shadow.hide();
			} else {
				shadow.show();
			}

			anim.start((a) => {
				Budgie.Raven? r = a.widget as Budgie.Raven;
				Gtk.Window? w = a.widget as Gtk.Window;

				if (r != null && r.nscale == 0.0) {
					set_opacity(0.0); // Mask scaling weirdness
					Timeout.add(100, () => {
						r.hide();
						return false;
					}); // Defer until opacity set otherwise it glitches
				} else if (w != null) {
					shadow.set_opacity(1.0);
					set_opacity(1.0);
					w.present();
					w.grab_focus();
					this.steal_focus();
					steal_focus();
				}
			});
		}

		public bool get_expanded() {
			return this.expanded;
		}

		public void update_uuids() {
			string[] uuids = null;

			widgets.foreach((widget_data) => {
				uuids += widget_data.uuid;
			});

			widget_settings.set_strv("uuids", uuids);
		}

		public RavenWidgetCreationResult create_widget_instance(string module_name) {
			Budgie.RavenWidgetData? widget_data;
			var result = plugin_manager.new_widget_instance_for_plugin(module_name, null, out widget_data);
			if (result == RavenWidgetCreationResult.SUCCESS) {
				widgets.append(widget_data);
				main_view.add_widget_instance(widget_data.widget_instance);
				on_widget_added(widget_data);
				update_uuids();
			}

			return result;
		}

		private void create_widget_instance_with_uuid(string module_name, string? uuid) {
			Budgie.RavenWidgetData? widget_data;
			var result = plugin_manager.new_widget_instance_for_plugin(module_name, uuid, out widget_data);
			switch (result) {
				case RavenWidgetCreationResult.SUCCESS:
					widgets.append(widget_data);
					main_view.add_widget_instance(widget_data.widget_instance);
					on_widget_added(widget_data);
					break;
				case RavenWidgetCreationResult.PLUGIN_INFO_MISSING:
					warning("Failed to create Raven widget instance with uuid %s: No plugin info found for module %s", uuid, module_name);
					break;
				case RavenWidgetCreationResult.INVALID_MODULE_NAME:
					var builder = new StringBuilder();
					builder.append("Failed to create Raven widget instance with uuid %s: Module name must be in reverse-DNS format.");
					builder.append("(e.g. 'tld.domain.group.WidgetName.so' for C/Vala or 'tld_domain_group_WidgetName' for Python)");
					warning(builder.str, uuid, module_name);
					break;
				case RavenWidgetCreationResult.PLUGIN_LOAD_FAILED:
					warning("Failed to create Raven widget instance with uuid %s: Plugin with module %s failed to load", uuid, module_name);
					break;
				case RavenWidgetCreationResult.SCHEMA_LOAD_FAILED:
					warning("Failed to create Raven widget instance with uuid %s: Plugin with module %s supports settings, but does not install a schema with the same name", uuid, module_name);
					break;
				case RavenWidgetCreationResult.INSTANCE_CREATION_FAILED:
					warning("Failed to create Raven widget instance with uuid %s: Unknown failure", uuid);
					break;
			}
		}

		private void load_existing_widgets() {
			string[] stored_uuids = widget_settings.get_strv("uuids");

			if (stored_uuids.length == 0 && !widget_settings.get_boolean("initialized")) {
				update_uuids();

				/**
				* Try in order, and load the first one that exists:
				* - /etc/budgie-desktop/raven/widgets.ini
				* - /usr/share/budgie-desktop/raven/widgets.ini
				* - Built in widgets.ini
				*/
				string[] system_configs = {
					@"file://$(Budgie.CONFDIR)/budgie-desktop/raven/widgets.ini",
					@"file://$(Budgie.DATADIR)/budgie-desktop/raven/widgets.ini",
					"resource:///org/buddiesofbudgie/budgie-desktop/raven/widgets.ini"
				};

				foreach (string? filepath in system_configs) {
					if (load_default_from_config(filepath)) {
						update_uuids();
						widget_settings.set_boolean("initialized", true);
						break;
					}
				}

				return;
			}

			widget_settings.set_boolean("initialized", true);

			unowned string uuid;
			GLib.Settings? widget_info;

			for (int i = 0; i < stored_uuids.length; i++) {
				uuid = stored_uuids[i];
				widget_info = plugin_manager.get_widget_info_from_uuid(uuid);

				if (widget_info == null) {
					warning("Widget info for uuid %s is null", uuid);
					continue;
				}

				string? module_name = widget_info.get_string("module");
				if (module_name == null) {
					warning("Module name of widget instance %s is null", uuid);
					continue;
				}

				create_widget_instance_with_uuid(module_name, uuid);
			}

			update_uuids();
		}

		public List<unowned RavenWidgetData> get_existing_widgets() {
			return widgets.copy();
		}

		public void remove_widget(RavenWidgetData widget_data) {
			widgets.remove(widget_data);
			main_view.remove_widget_instance(widget_data.widget_instance);
			plugin_manager.clear_widget_instance_info(widget_data.uuid);
			if (widget_data.supports_settings) {
				plugin_manager.clear_widget_instance_settings(widget_data.uuid);
			}
			update_uuids();
		}

		public void move_widget_by_offset(RavenWidgetData widget_data, int offset) {
			var new_index = widgets.index(widget_data) + offset;

			if (new_index < widgets.length() && new_index >= 0) {
				widgets.remove(widget_data);
				widgets.insert(widget_data, new_index);

				main_view.move_widget_instance_by_offset(widget_data.widget_instance, offset);
				update_uuids();
			}
		}

		/**
		* Attempt to load the configuration from the given URL
		*/
		private bool load_default_from_config(string uri) {
			File f = null;
			KeyFile config_file = new KeyFile();
			StringBuilder builder = new StringBuilder();
			string? line = null;

			try {
				f = File.new_for_uri(uri);
				if (!f.query_exists()) return false;

				var dis = new DataInputStream(f.read());
				while ((line = dis.read_line()) != null) {
					builder.append_printf("%s\n", line);
				}
				config_file.load_from_data(builder.str, builder.len, KeyFileFlags.NONE);
			} catch (Error e) {
				warning("Failed to load default Raven widget config: %s", e.message);
				return false;
			}

			try {
				if (!config_file.has_key("Widgets", "Widgets")) {
					warning("widgets.ini is missing required Widgets section");
					return false;
				}

				var widgets = config_file.get_string_list("Widgets", "Widgets");

				foreach (string widget in widgets) {
					widget = widget.strip();

					if (!config_file.has_group(widget)) {
						warning("Raven widget %s missing from widgets.ini", widget);
						continue;
					}

					if (!config_file.has_key(widget, "Module")) {
						warning("Raven widget %s is missing Module key in widgets.ini", widget);
						continue;
					}

					var module_name = config_file.get_string(widget, "Module").strip();
					create_widget_instance_with_uuid(module_name, null);
				}
			} catch (Error e) {
				warning("Error configuring Raven widgets from raven-widget.ini: %s", e.message);
				return false;
			}

			return true;
		}

		/* As cheap as it looks. The DesktopManager responds to this signal and
		* will show the Settings UI
		*/
		public signal void request_settings_ui();

		public signal void on_widget_added(Budgie.RavenWidgetData widget_data);
	}
}
