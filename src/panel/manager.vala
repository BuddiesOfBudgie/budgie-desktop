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

using LibUUID;

namespace Budgie {
	public const string DBUS_NAME = "org.budgie_desktop.Panel";
	public const string DBUS_OBJECT_PATH = "/org/budgie_desktop/Panel";

	public const string MIGRATION_1_APPLETS[] = {
		"User Indicator",
		"Raven Trigger",
	};

	/**
	* Available slots
	*/
	class Screen : GLib.Object {
		public PanelPosition slots;
		public Gdk.Rectangle area;
	}

	/**
	* Permit a slot for each edge of the screen
	*/
	public const uint MAX_SLOTS = 4;

	/**
	* Root prefix for fixed schema
	*/
	public const string ROOT_SCHEMA = "com.solus-project.budgie-panel";

	/**
	* Relocatable schema ID for toplevel panels
	*/
	public const string TOPLEVEL_SCHEMA = "com.solus-project.budgie-panel.panel";

	/**
	* Prefix for all relocatable panel settings
	*/
	public const string TOPLEVEL_PREFIX = "/com/solus-project/budgie-panel/panels";

	/**
	* Schema ID for Raven settings
	*/
	public const string RAVEN_SCHEMA = "com.solus-project.budgie-raven";

	/**
	* Known panels
	*/
	public const string ROOT_KEY_PANELS = "panels";

	/** Panel position */
	public const string PANEL_KEY_POSITION = "location";

	/** Panel transparency */
	public const string PANEL_KEY_TRANSPARENCY = "transparency";

	/** Panel applets */
	public const string PANEL_KEY_APPLETS = "applets";

	/** Night mode/dark theme */
	public const string PANEL_KEY_DARK_THEME = "dark-theme";

	/** Panel size */
	public const string PANEL_KEY_SIZE = "size";

	/** Panel spacing */
	public const string PANEL_KEY_SPACING = "spacing";

	/** Autohide policy */
	public const string PANEL_KEY_AUTOHIDE = "autohide";

	/** Shadow */
	public const string PANEL_KEY_SHADOW = "enable-shadow";

	/** Dock mode */
	public const string PANEL_KEY_DOCK_MODE = "dock-mode";

	/** Theme regions permitted? */
	public const string PANEL_KEY_REGIONS = "theme-regions";

	/** Current migration level in settings */
	public const string PANEL_KEY_MIGRATION = "migration-level";

	/** Layout to select when reset/init for the first time */
	public const string PANEL_KEY_LAYOUT = "layout";

	/** Position that Raven should have when opening */
	public const string RAVEN_KEY_POSITION = "raven-position";

	/**
	* The current migration level of Budgie, or format change, if you will.
	*/
	public const int BUDGIE_MIGRATION_LEVEL = 1;


	[DBus (name="org.budgie_desktop.Panel")]
	public class PanelManagerIface {
		private Budgie.PanelManager? manager = null;

		[DBus (visible=false)]
		public PanelManagerIface(Budgie.PanelManager? manager) {
			this.manager = manager;
		}

		public string get_version() throws DBusError, IOError {
			return Budgie.VERSION;
		}

		public void ActivateAction(int action) throws DBusError, IOError {
			this.manager.activate_action(action);
		}

		public void OpenSettings() throws DBusError, IOError {
			this.manager.open_settings();
		}
	}

	public class PanelManager : DesktopManager {
		private PanelManagerIface? iface;
		bool setup = false;
		bool reset = false;

		/* Keep track of our SessionManager */
		private LibSession.SessionClient? sclient;

		HashTable<int,Screen?> screens;
		HashTable<string,Budgie.Panel?> panels;

		int primary_monitor = 0;
		Settings settings;
		Settings raven_settings;

		private Budgie.Raven? raven = null;
		RavenPosition raven_position;

		private Budgie.RavenPluginManager? raven_plugin_manager = null;
		private Budgie.PanelPluginManager? panel_plugin_manager = null;

		private Budgie.ThemeManager theme_manager;

		/* Manage all of the Budgie settings */
		private Budgie.SettingsWindow? settings_window = null;

		Budgie.Windowing.Windowing windowing;

		private string default_layout = "default";

		public void activate_action(int action) {
			unowned string? uuid = null;
			unowned Budgie.Panel? panel = null;

			var iter = HashTableIter<string?,Budgie.Panel?>(panels);
			/* Only let one panel take the action, and one applet per panel */
			while (iter.next(out uuid, out panel)) {
				if (panel.activate_action(action)) {
					break;
				}
			}
		}

		private void end_session(bool quit) {
			if (quit) {
				Gtk.main_quit();
				return;
			}
			try {
				sclient.EndSessionResponse(true, "");
			} catch (Error e) {
				warning("Unable to respond to session manager! %s", e.message);
			}
		}

		private async bool register_with_session() {
			sclient = yield LibSession.register_with_session("budgie-panel");

			if (sclient == null) {
				return false;
			}

			sclient.QueryEndSession.connect(() => {
				end_session(false);
			});
			sclient.EndSession.connect(() => {
				end_session(false);
			});
			sclient.Stop.connect(() => {
				end_session(true);
			});
			return true;
		}

		public PanelManager(bool reset) {
			Object();
			this.reset = reset;
			libxfce4windowing.set_client_type(libxfce4windowing.ClientType.PAGER);
			windowing = new Budgie.Windowing.Windowing();
			screens = new HashTable<int,Screen?>(direct_hash, direct_equal);
			panels = new HashTable<string,Budgie.Panel?>(str_hash, str_equal);
		}

		/**
		* Initial setup of the dynamic transparency routine
		* Executed after the initial setup of the panel manager
		*/
		private void do_dynamic_transparency_setup() {
			windowing.window_state_changed.connect((window) => {
				if (window.is_skip_pager() || window.is_skip_tasklist()) return;
				check_windows();
			});

			windowing.window_added.connect(window_opened);
			windowing.window_removed.connect(check_windows);
			windowing.active_window_changed.connect(active_window_changed);
			windowing.active_workspace_changed.connect(check_windows);
		}

		private void active_window_changed() {
			// Handle transparency
			check_windows();
		}

		/*
		* Callback for newly opened, not yet tracked windows
		*/
		private void window_opened(libxfce4windowing.Window window) {
			window.state_changed.connect(() => {
				if (window.is_skip_pager() || window.is_skip_tasklist()) return;
				check_windows();
			});

			check_windows();
		}

		private unowned Gdk.Monitor? get_primary_monitor() {
			Budgie.Panel? panel = null;

			var iter = HashTableIter<string,Budgie.Panel?>(panels);
			iter.next(null, out panel);

			if (panel == null) return null;

			var display = ((Gtk.Window) panel).get_display();
			var gdk_window = ((Gtk.Widget) panel).get_window();

			return display.get_monitor_at_window(gdk_window);
		}

		/**
		* Determine if the window is on the primary screen, i.e. where the main
		* budgie panels will show
		*/
		bool window_on_primary(libxfce4windowing.Window? window) {
			unowned Gdk.Monitor? primary_monitor = this.get_primary_monitor();

			if (primary_monitor == null) {
				debug("Primary monitor is NULL");
				return false;
			}

			unowned var monitors = window.get_monitors();

			foreach (var monitor in monitors) {
				unowned var gdk_monitor = monitor.get_gdk_monitor();

				if (gdk_monitor == primary_monitor) {
					return true;
				}
			}

			return false;
		}

		/*
		* Decide whether or not the panel should be opaque
		* The panel should be opaque when:
		* - Raven is open
		* - a window fills these requirements:
		*   - Maximized horizontally or verically
		*   - Not minimized/iconified
		*/
		public void check_windows() {
			if (raven.get_expanded()) {
				set_panel_transparent(false, true);
				return;
			}
			bool found = false;

			libxfce4windowing.Workspace? active_workspace = windowing.get_active_workspace();

			windowing.windows.foreach((window) => {
				if (window.is_skip_pager()) return;
				if (!this.window_on_primary(window)) return;
				if ((window.is_maximized() && !window.is_minimized())) {
					found = true;
					return;
				}
			});

			set_panel_transparent(!found);
		}

		/*
		* Control the transparency for panels with dynamic transparency on
		*/
		void set_panel_transparent(bool transparent, bool raven_force = false) {
			Budgie.Panel? panel = null;
			var iter = HashTableIter<string,Budgie.Panel?>(panels);
			while (iter.next(null, out panel)) {
				if (panel.transparency == PanelTransparency.DYNAMIC) {
					panel.set_transparent(transparent);
				}
				if (panel.autohide == AutohidePolicy.AUTOMATIC) {
					panel.set_occluded(raven_force ? transparent : !transparent);
				}
			}
		}

		/**
		* Attempt to reset the given path
		*/
		public void reset_dconf_path(Settings? settings) {
			if (settings == null) {
				return;
			}
			string path = settings.path;
			Settings.sync();
			if (settings.path == null) {
				return;
			}
			string argv[] = { "dconf", "reset", "-f", path};
			message("Resetting dconf path: %s", path);
			try {
				Process.spawn_command_line_sync(string.joinv(" ", argv), null, null, null);
			} catch (Error e) {
				warning("Failed to reset dconf path %s: %s", path, e.message);
			}
			Settings.sync();
		}

		public Budgie.AppletInfo? get_applet(string key) {
			return null;
		}

		string create_panel_path(string uuid) {
			return "%s/{%s}/".printf(Budgie.TOPLEVEL_PREFIX, uuid);
		}

		/**
		* Discover all possible monitors, and move things accordingly.
		* In future we'll support per-monitor panels, but for now everything
		* must be in one of the edges on the primary monitor
		*/
		public void on_monitors_changed() {
			var scr = Gdk.Screen.get_default();
			var dis = scr.get_display();
			HashTableIter<string,Budgie.Panel?> iter;
			unowned string uuid;
			unowned Budgie.Panel panel;
			unowned Screen? primary;
			unowned Budgie.Panel? top = null;
			unowned Budgie.Panel? bottom = null;

			screens.remove_all();

			/* When we eventually get monitor-specific panels we'll find the ones that
			* were left stray and find new homes, or temporarily disable
			* them */
			for (int i = 0; i < dis.get_n_monitors(); i++) {
				Gdk.Monitor mon = dis.get_monitor(i);
				Gdk.Rectangle usable_area = mon.get_geometry();
				Budgie.Screen? screen = new Budgie.Screen();
				screen.area = usable_area;
				screen.slots = PanelPosition.NONE;
				screens.insert(i, screen);

				if (mon.is_primary()) {
					primary_monitor = i;
				}
			}

			primary = screens.lookup(primary_monitor);

			/* Fix all existing panels here */
			Gdk.Rectangle raven_screen;

			iter = HashTableIter<string,Budgie.Panel?>(panels);
			while (iter.next(out uuid, out panel)) {
				/* Force existing panels to update to new primary display */
				panel.update_geometry(primary.area, panel.position);
				if (panel.position == Budgie.PanelPosition.TOP) {
					top = panel;
				} else if (panel.position == Budgie.PanelPosition.BOTTOM) {
					bottom = panel;
				}
				/* Re-take the position */
				primary.slots |= panel.position;
			}

			raven_screen = primary.area;
			if (top != null) {
				raven_screen.y += top.intended_size;
				raven_screen.height -= top.intended_size;
			}
			if (bottom != null) {
				raven_screen.height -= bottom.intended_size;
			}


			this.raven.update_geometry(raven_screen);
		}

		private void on_bus_acquired(DBusConnection conn) {
			try {
				iface = new PanelManagerIface(this);
				conn.register_object(Budgie.DBUS_OBJECT_PATH, iface);
			} catch (Error e) {
				stderr.printf("Error registering PanelManager: %s\n", e.message);
				Process.exit(1);
			}
		}

		public void on_name_acquired(DBusConnection conn, string name) {
			this.setup = true;
			/* Well, off we go to be a panel manager. */
			do_setup();
			do_dynamic_transparency_setup();
		}

		/**
		* Reset the entire panel configuration
		*/
		void do_reset() {
			message("Resetting budgie-panel configuration to defaults");
			Settings s = new Settings(Budgie.ROOT_SCHEMA);
			this.default_layout = s.get_string(PANEL_KEY_LAYOUT);
			this.reset_dconf_path(s);
			// Preserve the default layout once more
			s = new Settings(Budgie.ROOT_SCHEMA);
			s.set_string(PANEL_KEY_LAYOUT, this.default_layout);
		}

		/**
		* Reset after a failed load
		*/
		void do_live_reset() {
			message("Resetting budgie-panel configuration due to failed load");

			string[]? toplevel_ids = null;

			foreach (var toplevel in this.get_panels()) {
				toplevel_ids += toplevel.uuid;
			}

			if (toplevel_ids != null) {
				foreach (var toplevel_id in toplevel_ids) {
					this.delete_panel(toplevel_id);
				}
			}

			this.do_reset();
		}

		/**
		* Initial setup, once we've owned the dbus name
		* i.e. no risk of dying
		*/
		void do_setup() {
			if (this.reset) {
				this.do_reset();
			}
			var scr = Gdk.Screen.get_default();
			var dis = scr.get_display();

			for (int i = 0; i < dis.get_n_monitors(); i++) {
				if (dis.get_monitor(i).is_primary()) {
					primary_monitor = i;
				}
			}

			scr.monitors_changed.connect(this.on_monitors_changed);
			scr.size_changed.connect(this.on_monitors_changed);

			settings = new Settings(Budgie.ROOT_SCHEMA);

			// Listen to the Raven position setting for changes
			raven_settings = new Settings(RAVEN_SCHEMA);
			raven_position = (RavenPosition)raven_settings.get_enum(RAVEN_KEY_POSITION);
			raven_settings.changed[RAVEN_KEY_POSITION].connect(() => {
				RavenPosition new_position = (RavenPosition)raven_settings.get_enum(RAVEN_KEY_POSITION);
				if (new_position != raven_position) {
					raven_position = new_position;

					// Raven needs to know about its new position
					update_screen();
				}
			});

			this.default_layout = settings.get_string(PANEL_KEY_LAYOUT);
			theme_manager = new Budgie.ThemeManager();

			raven_plugin_manager = new Budgie.RavenPluginManager();
			panel_plugin_manager = new Budgie.PanelPluginManager();

			raven = new Budgie.Raven(this, raven_plugin_manager);
			raven.request_settings_ui.connect(this.on_settings_requested);

			this.on_monitors_changed();

			/* Some applets might want raven */
			raven.setup_dbus();

			if (!load_panels()) {
				message("Creating default panel layout");

				// TODO: Add gsetting for this name
				create_default(this.default_layout);
			}

			/* Whatever route we took, set the migration level to the current now */
			settings.set_int(PANEL_KEY_MIGRATION, BUDGIE_MIGRATION_LEVEL);

			register_with_session.begin((o, res) => {
				bool success = register_with_session.end(res);
				if (!success) {
					message("Failed to register with Session manager");
				}
			});
		}

		public override List<Peas.PluginInfo?> get_panel_plugins() {
			return panel_plugin_manager.get_all_plugins();
		}

		public override List<Peas.PluginInfo?> get_raven_plugins() {
			return raven_plugin_manager.get_all_plugins();
		}

		public override void rescan_panel_plugins() {
			panel_plugin_manager.rescan_plugins();
		}

		public override void rescan_raven_plugins() {
			raven_plugin_manager.rescan_plugins();
		}

		/**
		* Find the next available position on the given monitor
		*/
		public PanelPosition get_first_position(int monitor) {
			if (!screens.contains(monitor)) {
				error("No screen for monitor: %d - This should never happen!", monitor);
			}
			Screen? screen = screens.lookup(monitor);

			if ((screen.slots & PanelPosition.TOP) == 0) {
				return PanelPosition.TOP;
			} else if ((screen.slots & PanelPosition.BOTTOM) == 0) {
				return PanelPosition.BOTTOM;
			} else if ((screen.slots & PanelPosition.LEFT) == 0) {
				return PanelPosition.LEFT;
			} else if ((screen.slots & PanelPosition.RIGHT) == 0) {
				return PanelPosition.RIGHT;
			} else {
				return PanelPosition.NONE;
			}
		}

		/**
		* Determine how many slots are available
		*/
		public override uint slots_available() {
			return MAX_SLOTS - panels.size();
		}

		/**
		* Determine how many slots have been used
		*/
		public override uint slots_used() {
			return panels.size();
		}

		/**
		* Load a panel by the given UUID, and optionally configure it
		*/
		void load_panel(string uuid, bool configure = false) {
			if (panels.contains(uuid)) {
				warning("Asked to load already loaded panel: %s", uuid);
				return;
			}

			string path = this.create_panel_path(uuid);
			PanelPosition position;
			PanelTransparency transparency;
			AutohidePolicy policy;
			bool dock_mode;
			bool shadow_visible;
			int size, spacing;

			var settings = new Settings.with_path(Budgie.TOPLEVEL_SCHEMA, path);
			Budgie.Panel? panel = new Budgie.Panel(this, panel_plugin_manager, uuid, settings);
			panels.insert(uuid, panel);

			if (!configure) {
				return;
			}

			position = (PanelPosition)settings.get_enum(Budgie.PANEL_KEY_POSITION);
			transparency = (PanelTransparency)settings.get_enum(Budgie.PANEL_KEY_TRANSPARENCY);
			policy = (AutohidePolicy)settings.get_enum(Budgie.PANEL_KEY_AUTOHIDE);
			dock_mode = settings.get_boolean(Budgie.PANEL_KEY_DOCK_MODE);
			shadow_visible = settings.get_boolean(Budgie.PANEL_KEY_SHADOW);

			size = settings.get_int(Budgie.PANEL_KEY_SIZE);
			panel.intended_size = (int)size;
			spacing = (int) settings.get_int(Budgie.PANEL_KEY_SPACING);
			this.show_panel(uuid, position, transparency, policy, dock_mode, shadow_visible, spacing);
		}

		void show_panel(string uuid, PanelPosition position, PanelTransparency transparency, AutohidePolicy policy,
						bool dock_mode, bool shadow_visible, int spacing) {

			Budgie.Panel? panel = panels.lookup(uuid);
			unowned Screen? scr;

			if (panel == null) {
				warning("Asked to show non-existent panel: %s", uuid);
				return;
			}

			scr = screens.lookup(this.primary_monitor);
			scr.slots |= position;
			this.set_placement(uuid, position);
			this.set_transparency(uuid, transparency);
			this.set_autohide(uuid, policy);
			this.set_dock_mode(uuid, dock_mode);
			this.set_shadow(uuid, shadow_visible);
			this.set_spacing(uuid, spacing);
		}

		/**
		* Set size of the given panel
		*/
		public override void set_size(string uuid, int size) {
			Budgie.Panel? panel = panels.lookup(uuid);

			if (panel == null) {
				warning("Asked to resize non-existent panel: %s", uuid);
				return;
			}

			panel.intended_size = size;
			this.update_screen();
		}

		/**
		* Set spacing of the given panel
		*/
		public override void set_spacing(string uuid, int spacing) {
			Budgie.Panel? panel = panels.lookup(uuid);

			if (panel == null) {
				warning("Asked to resize non-existent panel: %s", uuid);
				return;
			}

			panel.intended_spacing = spacing;
			panel.update_spacing();
		}

		/**
		* Enforce panel placement
		*/
		public override void set_placement(string uuid, PanelPosition position) {
			Budgie.Panel? panel = panels.lookup(uuid);
			string? key = null;
			Budgie.Panel? val = null;
			Budgie.Panel? conflict = null;

			if (panel == null) {
				warning("Trying to move non-existent panel: %s", uuid);
				return;
			}
			Screen? area = screens.lookup(primary_monitor);

			PanelPosition old = panel.position;

			if (old == position) {
				warning("Attempting to move panel to the same position it's already in: %s %s %s", uuid, old.to_string(), position.to_string());
				return;
			}

			/* Attempt to find a conflicting position */
			var iter = HashTableIter<string,Budgie.Panel?>(panels);
			while (iter.next(out key, out val)) {
				if (val.position == position) {
					conflict = val;
					break;
				}
			}

			panel.hide();
			if (conflict != null) {
				conflict.hide();
				conflict.update_geometry(area.area, old);
				conflict.show();
				panel.hide();
				panel.update_geometry(area.area, position);
				panel.show();
			} else {
				area.slots ^= old;
				area.slots |= position;
				panel.update_geometry(area.area, position);
			}

			/* This does mean re-configuration a couple of times that could
			* be avoided, but it's just to ensure proper functioning..
			*/
			this.update_screen();
			panel.show();
		}

		/**
		* Set panel transparency
		*/
		public override void set_transparency(string uuid, PanelTransparency transparency) {
			Budgie.Panel? panel = panels.lookup(uuid);

			if (panel == null) {
				warning("Trying to set transparency on non-existent panel: %s", uuid);
				return;
			}

			panel.update_transparency(transparency);
		}


		public override void set_autohide(string uuid, Budgie.AutohidePolicy policy) {
			Budgie.Panel? panel = panels.lookup(uuid);

			if (panel == null) {
				warning("Trying to set autohide on non-existent panel: %s", uuid);
				return;
			}
			panel.set_autohide_policy(policy);

			// Raven needs to know about the autohide mode
			this.update_screen();
		}

		/**
		* Set panel dock mode
		*/
		public override void set_dock_mode(string uuid, bool dock_mode) {
			Budgie.Panel? panel = panels.lookup(uuid);

			if (panel == null) {
				warning("Trying to set dock mode on non-existent panel: %s", uuid);
				return;
			}

			panel.dock_mode = dock_mode;

			// Raven needs to know about the dock mode
			this.update_screen();
		}

		void set_shadow(string uuid, bool visible) {
			Budgie.Panel? panel = panels.lookup(uuid);

			if (panel == null) {
				warning("Trying to set dock mode on non-existent panel: %s", uuid);
				return;
			}

			panel.update_shadow(visible);
		}

		/**
		* Force update geometry for all panels
		*/
		void update_screen() {
			Budgie.Toplevel? top = null;
			Budgie.Toplevel? bottom = null;
			Budgie.Toplevel? right = null;
			Budgie.Toplevel? left = null;
			Gdk.Rectangle raven_screen;

			string? key = null;
			Budgie.Panel? val = null;
			Screen? area = screens.lookup(primary_monitor);
			var iter = HashTableIter<string,Budgie.Panel?>(panels);

			// First loop, edges that conflict with Raven
			while (iter.next(out key, out val)) {
				switch (val.position) {
				case Budgie.PanelPosition.TOP:
					top = val;
					break;
				case Budgie.PanelPosition.BOTTOM:
					bottom = val;
					break;
				case Budgie.PanelPosition.RIGHT:
					right = val;
					break;
				case Budgie.PanelPosition.LEFT:
					left = val;
					break;
				default:
					continue;
				}
			}

			var iter2 = HashTableIter<string,Budgie.Panel?>(panels);

			string? key2 = null;
			Budgie.Panel? val2 = null;

			while (iter2.next(out key2, out val2)) {
				switch (val2.position) {
				case Budgie.PanelPosition.LEFT:
				case Budgie.PanelPosition.RIGHT:
					Gdk.Rectangle geom = Gdk.Rectangle();
					geom.x = area.area.x;
					geom.y = area.area.y;
					geom.width = area.area.width;
					geom.height = area.area.height;
					if (this.is_panel_huggable(top)) {
						geom.y += top.intended_size;
						geom.height -= top.intended_size;
					}
					if (this.is_panel_huggable(bottom)) {
						geom.height -= bottom.intended_size;
					}
					val2.update_geometry(geom, val2.position, val2.intended_size);
					break;
				default:
					val2.update_geometry(area.area, val2.position, val2.intended_size);
					break;
				}
			}

			raven_screen = area.area;
			if (top != null && !top.dock_mode && top.autohide == AutohidePolicy.NONE) {
				raven_screen.y += top.intended_size;
				raven_screen.height -= top.intended_size;
			}

			if (bottom != null && !bottom.dock_mode && bottom.autohide == AutohidePolicy.NONE) {
				raven_screen.height -= bottom.intended_size;
			}

			// Set which side of the screen Raven should appear on
			switch (raven_position) {
				case RavenPosition.LEFT:
					/* Stick/maybe hug left */
					raven.screen_edge = Gtk.PositionType.LEFT;
					if (left != null) {
						raven_screen.x += left.intended_size;
					}
					break;
				case RavenPosition.RIGHT:
					/* Stick/maybe hug right */
					raven.screen_edge = Gtk.PositionType.RIGHT;
					if (right != null) {
						raven_screen.width -= (right.intended_size);
					}
					break;
				case RavenPosition.AUTOMATIC:
				default:
					set_raven_position(left, right, ref raven_screen);
					break;
			}

			/* Let Raven update itself accordingly */
			raven.update_geometry(raven_screen);
			this.panels_changed();
		}

		bool is_panel_huggable(Budgie.Toplevel? panel) {
			if (panel == null) {
				return false;
			}
			if (panel.autohide != AutohidePolicy.NONE) {
				return false;
			}
			if (panel.dock_mode) {
				return false;
			}
			return true;
		}

		/**
		 * Use the current panel layouts to figure out Raven's position.
		 *
		 * This function sets which side of the screen Raven should be on,
		 * as well as Raven's position or width (if it's on the right side).
		 */
		void set_raven_position(Toplevel? left, Toplevel? right, ref Gdk.Rectangle raven_screen) {
			if (left != null && right == null) {
				if (this.is_panel_huggable(left)) {
					/* Hug left */
					raven.screen_edge = Gtk.PositionType.LEFT;
					raven_screen.x += left.intended_size;
				} else {
					/* Stick right */
					raven.screen_edge = Gtk.PositionType.RIGHT;
				}
			} else if (right != null && left == null) {
				if (this.is_panel_huggable(right)) {
					/* Hug right */
					raven_screen.width -= (right.intended_size);
					raven.screen_edge = Gtk.PositionType.RIGHT;
				} else {
					/* Stick left */
					raven.screen_edge = Gtk.PositionType.LEFT;
				}
			} else if (is_panel_huggable(left) && !is_panel_huggable(right)) {
				/* Hug left */
				raven.screen_edge = Gtk.PositionType.LEFT;
				raven_screen.x += left.intended_size;
			} else if (is_panel_huggable(right) && !is_panel_huggable(left)) {
				/* Hug right */
				raven_screen.width -= (right.intended_size);
				raven.screen_edge = Gtk.PositionType.RIGHT;
			} else {
				/* Stick/maybe hug right */
				raven.screen_edge = Gtk.PositionType.RIGHT;
				if (right != null) {
					raven_screen.width -= (right.intended_size);
				}
			}
		}

		/**
		* Load all known panels
		*/
		bool load_panels() {
			string[] panels = this.settings.get_strv(Budgie.ROOT_KEY_PANELS);
			if (panels.length == 0) {
				warning("No panels to load");
				return false;
			}

			foreach (string uuid in panels) {
				this.load_panel(uuid, true);
			}

			this.update_screen();
			return true;
		}

		public override void create_new_panel() {
			create_panel();
		}

		public override void delete_panel(string uuid) {
			if (this.slots_used() <= 1) {
				warning("Asked to delete final panel");
				return;
			}

			unowned Budgie.Panel? panel = panels.lookup(uuid);
			if (panel == null) {
				warning("Asked to delete non-existent panel: %s", uuid);
				return;
			}
			Screen? area = screens.lookup(primary_monitor);
			area.slots ^= panel.position;

			this.panel_deleted(uuid);

			var spath = this.create_panel_path(panel.uuid);
			remove_panel(uuid, true);

			var psettings = new Settings.with_path(Budgie.TOPLEVEL_SCHEMA, spath);
			this.reset_dconf_path(psettings);
		}

		void create_panel(string? name = null, KeyFile? new_defaults = null) {
			PanelPosition position = PanelPosition.NONE;
			PanelTransparency transparency = PanelTransparency.NONE;
			Budgie.AutohidePolicy policy = Budgie.AutohidePolicy.NONE;
			bool dock_mode = false;
			bool shadow_visible = true;
			int size = -1;
			int spacing = 2;

			if (this.slots_available() < 1) {
				warning("Asked to create panel with no slots available");
				return;
			}

			if (name != null && new_defaults != null) {
				try {
					/* Determine new panel position */
					if (new_defaults.has_key(name, "Position")) {
						switch (new_defaults.get_string(name, "Position").down()) {
							case "top":
								position = PanelPosition.TOP;
								break;
							case "left":
								position = PanelPosition.LEFT;
								break;
							case "right":
								position = PanelPosition.RIGHT;
								break;
							default:
								position = PanelPosition.BOTTOM;
								break;
						}
					}
					if (new_defaults.has_key(name, "Size")) {
						size = new_defaults.get_integer(name, "Size");
					}
					if (new_defaults.has_key(name, "Spacing")) {
						spacing = new_defaults.get_integer(name, "Spacing");
					}
					if (new_defaults.has_key(name, "Dock")) {
						dock_mode = new_defaults.get_boolean(name, "Dock");
					}
					if (new_defaults.has_key(name, "Shadow")) {
						shadow_visible = new_defaults.get_boolean(name, "Shadow");
					}
					if (new_defaults.has_key(name, "Autohide")) {
						switch(new_defaults.get_string(name, "Autohide").down()) {
							case "automatic":
								policy = Budgie.AutohidePolicy.AUTOMATIC;
								break;
							case "intelligent":
								policy = Budgie.AutohidePolicy.INTELLIGENT;
								break;
							default:
								policy = Budgie.AutohidePolicy.NONE;
								break;
						}
					}
					if (new_defaults.has_key(name, "Transparency")) {
						switch(new_defaults.get_string(name, "Transparency").down()) {
							case "always":
								transparency = PanelTransparency.ALWAYS;
								break;
							case "dynamic":
								transparency = PanelTransparency.DYNAMIC;
								break;
							default:
								transparency = PanelTransparency.NONE;
								break;
						}
					}
				} catch (Error e) {
					warning("create_panel(): %s", e.message);
				}
			} else {
				position = get_first_position(this.primary_monitor);
				if (position == PanelPosition.NONE) {
					critical("No slots available, this should not happen");
					return;
				}
			}

			var uuid = LibUUID.new(UUIDFlags.LOWER_CASE|UUIDFlags.TIME_SAFE_TYPE);
			load_panel(uuid, false);

			set_panels();
			show_panel(uuid, position, transparency, policy, dock_mode, shadow_visible, spacing);

			if (new_defaults == null || name == null) {
				this.panel_added(uuid, panels.lookup(uuid));
				return;
			}
			/* TODO: Add size clamp */
			if (size > 0) {
				set_size(uuid, size);
			}

			var panel = panels.lookup(uuid);
			/* TODO: Pass off the configuration here.. */
			panel.create_default_layout(name, new_defaults);
			this.panel_added(uuid, panel);
		}

		public override void remove_panel(string uuid, bool remove_from_dconf = true) {
			Budgie.Panel? panel = panels.lookup(uuid);
			if (panel == null) {
				warning("Asked to remove non-existent panel: %s", uuid);
				return;
			}
			panels.steal(panel.uuid);
			if (remove_from_dconf) {
				set_panels();
				update_screen();
				panel.destroy_children();
				panel.destroy();
			}
		}

		public override void move_panel(string uuid, PanelPosition position) {
			Budgie.Panel? panel = panels.lookup(uuid);
			if (panel == null) {
				warning("Asked to move non-existent panel: %s", uuid);
				return;
			}

			// This is horrible and I know it
			// This will destroy and recreate the panel to re-enable interactivity under Wayland

			// Start by hiding the panel to mask recreation
			panel.hide();
			// Move the panel to the new position
			set_placement(uuid, position);

			// Ensure panel position is saved
			panel.set_position_setting(position);

			// Close the panel
			panel.close();
			// Steal so we can add new panel entry
			panels.steal(panel.uuid);

			// Load panel again
			load_panel(uuid, true);

			// Look up again
			panel = panels.lookup(uuid);

			// Show moved panel
			panel.show();
		}

		/**
		* Update our known panels
		*/
		void set_panels() {
			unowned Budgie.Panel? panel;
			unowned string? key;
			string[]? keys = null;

			var iter = HashTableIter<string,Budgie.Panel?>(panels);
			while (iter.next(out key, out panel)) {
				keys += key;
			}

			this.settings.set_strv(Budgie.ROOT_KEY_PANELS, keys);
		}

		void create_default(string layout_name) {
			if (layout_name == "default") {
				this.create_system_default();
				return;
			}

			// /etc/budgie-desktop/layouts then /usr/share/budgie-desktop/layouts
			string[] panel_dirs = {
				Budgie.CONFDIR,
				Budgie.DATADIR
			};

			foreach (string panel_dir in panel_dirs) {
				string path = "file://%s/budgie-desktop/layouts/%s.layout".printf(panel_dir, layout_name);
				if (this.load_default_from_config(path)) {
					return;
				}
			}

			warning("Failed to find layout '%s'", layout_name);

			// Absolute fallback = built in INI config
			this.load_default_from_config("resource:///com/solus-project/budgie/panel/panel.ini");
		}


		/**
		* Create new default panel layout
		*/
		void create_system_default() {
			/**
			* Try in order, and load the first one that exists:
			* - /etc/budgie-desktop/panel.ini
			* - /usr/share/budgie-desktop/panel.ini
			* - Built in panel.ini
			*/
			string[] system_configs = {
				@"file://$(Budgie.CONFDIR)/budgie-desktop/panel.ini",
				@"file://$(Budgie.DATADIR)/budgie-desktop/panel.ini",
				""
			};

			foreach (string? filepath in system_configs) {
				if (this.load_default_from_config(filepath)) {
					return;
				}
			}

			this.load_default_from_config("resource:///com/solus-project/budgie/panel/panel.ini");
		}


		/**
		* Attempt to load the configuration from the given URL
		*/
		bool load_default_from_config(string uri) {
			File f = null;
			KeyFile config_file = new KeyFile();
			StringBuilder builder = new StringBuilder();
			string? line = null;
			PanelPosition pos;

			try {
				f = File.new_for_uri(uri);
				if (!f.query_exists()) {
					return false;
				}
				var dis = new DataInputStream(f.read());
				while ((line = dis.read_line()) != null) {
					builder.append_printf("%s\n", line);
				}
				config_file.load_from_data(builder.str, builder.len, KeyFileFlags.NONE);
			} catch (Error e) {
				warning("Failed to load default config: %s", e.message);
				return false;
			}

			try {
				if (!config_file.has_key("Panels", "Panels")) {
					warning("Config is missing required Panels section");
					return false;
				}

				var panels = config_file.get_string_list("Panels", "Panels");

				/* Begin creating named panels */
				foreach (var panel in panels) {
					panel = panel.strip();
					pos = PanelPosition.TOP;
					if (!config_file.has_group(panel)) {
						warning("Missing Panel config: %s", panel);
						continue;
					}
					create_panel(panel, config_file);
				}
			} catch (Error e) {
				warning("Error configuring panels!");
				this.do_live_reset();
				return false;
			}
			return true;
		}

		private void on_name_lost(DBusConnection conn, string name) {
			if (setup) {
				message("Replaced existing budgie-panel");
			} else {
				message("Another panel is already running. Use --replace to replace it");
			}
			Gtk.main_quit();
		}

		public void serve(bool replace = false) {
			var flags = BusNameOwnerFlags.ALLOW_REPLACEMENT;
			if (replace) {
				flags |= BusNameOwnerFlags.REPLACE;
			}
			Bus.own_name(BusType.SESSION, Budgie.DBUS_NAME, flags,
				on_bus_acquired, on_name_acquired, on_name_lost);
		}

		public override List<Budgie.Toplevel?> get_panels() {
			var list = new List<Budgie.Toplevel?>();
			unowned string? key;
			unowned Budgie.Panel? panel;
			var iter = HashTableIter<string?,Budgie.Panel?>(panels);
			while (iter.next(out key, out panel)) {
				list.append((Budgie.Toplevel)panel);
			}
			return list;
		}

		/* Raven asked for the settings to be shown */
		private void on_settings_requested() {
			this.open_settings();
		}

		/**
		* Open up the settings window on screen
		*/
		public void open_settings() {
			Idle.add(() => {
				if (this.settings_window == null) {
					this.settings_window = new Budgie.SettingsWindow(this);
					this.settings_window.destroy.connect(() => {
						this.settings_window = null;
					});

					/* Say hullo to the settings_window */
					foreach (var panel in this.get_panels()) {
						this.panel_added(panel.uuid, panel);
					}
				}
				this.settings_window.present();
				this.settings_window.grab_focus();
				Gdk.Window? window = this.settings_window.get_window();
				if (window != null) {
					window.focus(Gdk.CURRENT_TIME);
				}
				return false;
			});
		}
	}
}
