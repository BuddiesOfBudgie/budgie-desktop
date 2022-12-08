/*
 * This file is part of budgie-desktop
 *
 * Copyright © 2015-2022 Budgie Desktop Developers
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

		/* Anchor to the right by default */
		public Gtk.PositionType screen_edge {
			public set {
				this._screen_edge = value;

				if (this.iface != null) {
					this.iface.AnchorChanged(this.screen_edge == Gtk.PositionType.LEFT);
				}

				if (this._screen_edge == Gtk.PositionType.RIGHT) {
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
			}
			public get {
				return this._screen_edge;
			}
		}

		int our_width = 0;
		int our_height = 0;
		int our_x = 0;
		int our_y = 0;

		private Budgie.ShadowBlock? shadow;
		private RavenIface? iface = null;
		private Settings? settings = null;

		bool expanded = false;

		Gdk.Rectangle old_rect;
		Gtk.Box layout;

		private double scale = 0.0;

		public int required_size { public get ; protected set; }

		private PowerStrip? strip = null;

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
			get_style_context().add_class("budgie-container");

			settings = new Settings("com.solus-project.budgie-raven");
			settings.changed["show-power-strip"].connect(on_power_strip_change);

			Raven._instance = this;

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

			main_view.requested_draw.connect(() => {
				queue_draw();
			});

			strip = new PowerStrip(this);
			main_box.pack_end(strip, false, false, 0);

			resizable = false;
			skip_taskbar_hint = true;
			skip_pager_hint = true;
			set_keep_above(true);
			set_decorated(false);

			set_size_request(-1, -1);
			if (!this.get_realized()) {
				this.realize();
			}

			this.get_child().show_all();

			this.screen_edge = Gtk.PositionType.LEFT;

			on_power_strip_change(); // Trigger our power strip change func immediately

			plugin_manager.plugin_loaded.connect((module_name) => {
				var instance = plugin_manager.new_widget_instance_for_plugin(module_name);
				main_view.add_widget_instance(instance);
				warning("%s loaded", module_name);
			});
		}

		/**
		* on_power_strip_change will handle when the settings for Raven's Power Strip has changed
		*/
		private void on_power_strip_change() {
			bool show_strip = settings.get_boolean("show-power-strip");

			if (show_strip) { // If we should show the strip
				strip.show_all();
			} else { // If we should hide the strip
				strip.hide();
			}
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
			int x;

			if (this.screen_edge == Gtk.PositionType.RIGHT) {
				x = (rect.x+rect.width)-width;
			} else {
				x = rect.x;
			}

			int y = rect.y;
			int height = rect.height;

			this.old_rect = rect;

			move(x, y);

			our_height = height;
			our_width = width;
			our_x = x;
			our_y = y;

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
			double old_op, new_op;
			if (exp) {
				this.update_geometry(this.old_rect);
				old_op = 0.0;
				new_op = 1.0;
			} else {
				old_op = 1.0;
				new_op = 0.0;
			}
			nscale = old_op;

			if (exp) {
				show();
			}

			this.expanded = exp;
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
					old = old_op,
					@new = new_op
				}
			};

			anim.start((a) => {
				Budgie.Raven? r = a.widget as Budgie.Raven;
				Gtk.Window? w = a.widget as Gtk.Window;

				if (r != null && r.nscale == 0.0) {
					r.hide();
				} else if (w != null) {
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

		/* As cheap as it looks. The DesktopManager responds to this signal and
		* will show the Settings UI
		*/
		public signal void request_settings_ui();
	}
}
