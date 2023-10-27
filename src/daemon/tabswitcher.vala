/*
* This file is part of budgie-desktop
*
* Copyright © taaem <taaem@mailbox.org>
* Copyright © Budgie Desktop Developers
*
* This program is free software; you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation; either version 2 of the License, or
* (at your option) any later version.
*/

using Gdk;
using Gtk;
using libxfce4windowing;

namespace Budgie {
	public const string SHOW_ALL_WINDOWS_KEY = "show-all-windows-tabswitcher";

	/**
	* Default width for an Switcher notification
	*/
	public const int SWITCHER_SIZE = -1;

	/**
	* How often it is checked if the meta key is still pressed
	*/
	public const int SWITCHER_MOD_EXPIRE_TIME = 50;

	/**
	* Our name on the session bus. Reserved for Budgie use
	*/
	public const string SWITCHER_DBUS_NAME = "org.budgie_desktop.TabSwitcher";

	/**
	* Unique object path on SWITCHER_DBUS_NAME
	*/
	public const string SWITCHER_DBUS_OBJECT_PATH = "/org/budgie_desktop/TabSwitcher";

	public uint64 get_time() {
		return (uint64) new DateTime.now().to_unix();
	}

	/**
	* A TabSwitcherWidget is used for each icon in the display
	*/
	public class TabSwitcherWidget : Gtk.FlowBoxChild {
		private Gtk.Image image;
		private uint64 activation_timestamp;
		private libxfce4windowing.Application? application;
		private DesktopAppInfo? info;
		public string id;
		public string title;

		public unowned libxfce4windowing.Window? window = null;

		public signal void closed(TabSwitcherWidget widget);
		public signal void window_activated(libxfce4windowing.Window window);
		public signal void workspace_changed();

		public TabSwitcherWidget(Budgie.AppSystem app_system, libxfce4windowing.Window? win) {
			Object();
			window = win;
			var uid = window.get_id();
			id = uid.to_string();
			set_title();

			application = win.get_application();

			// Running under X11
			if (libxfce4windowing.windowing_get() == libxfce4windowing.Windowing.X11) {
				info = app_system.query_window_by_xid((ulong)uid);
			}

			image = new Gtk.Image();
			add(image);
			set_property("margin", 10);
			set_icon();

			halign = Gtk.Align.CENTER;
			valign = Gtk.Align.CENTER;

			window.state_changed.connect((changed_mask, new_state) => {
				if (
					((changed_mask & libxfce4windowing.WindowState.ACTIVE) != 0) &&
					((new_state & libxfce4windowing.WindowState.ACTIVE) != 0)
				) {
					activation_timestamp = get_time();
					window_activated(window);
				}
			});

			window.closed.connect(() => closed(this));
			application.icon_changed.connect(set_icon);
			window.icon_changed.connect(set_icon);
			window.name_changed.connect(set_title);
			window.workspace_changed.connect(() => workspace_changed());
		}

		private void set_icon() {
			Icon? info_icon = info != null ? info.get_icon() : null;

			if (info_icon != null) {
				image.set_from_gicon(info_icon, Gtk.IconSize.DIALOG);
				return;
			}

			Pixbuf? windowing_app_icon = application != null ? application.get_icon(Gtk.IconSize.DIALOG, Gtk.IconSize.DIALOG) : null;
			Pixbuf? window_icon = window.get_icon(Gtk.IconSize.DIALOG, Gtk.IconSize.DIALOG);
			image.set_from_pixbuf(windowing_app_icon ?? window_icon);
		}

		private void set_title() {
			string? win_name = window.get_name() ?? "";
			title = win_name.strip();
		}
	}

	/**
	*
	*/
	[GtkTemplate (ui="/com/solus-project/budgie/daemon/tabswitcher.ui")]
	public class TabSwitcherWindow : Gtk.Window {
		[GtkChild]
		private unowned FlowBox window_box;

		[GtkChild]
		private unowned Label window_title;

		private libxfce4windowing.Workspace? active_workspace = null;
		private unowned libxfce4windowing.WorkspaceGroup? workspace_group = null;
		private Gdk.Screen? default_screen;
		private libxfce4windowing.Screen xfce_screen;
		private unowned libxfce4windowing.WorkspaceManager workspace_manager;
		private Budgie.AppSystem? app_system = null;

		private Gdk.Monitor primary_monitor;

		private List<string?> recency = null;
		private HashTable<string?,TabSwitcherWidget?> ids = null;

		private GLib.Settings? settings = null;
		private bool show_all_windows = false;

		/**
		* Construct a new TabSwitcherWindow
		*/
		public TabSwitcherWindow() {
			Object(type: Gtk.WindowType.POPUP, type_hint: Gdk.WindowTypeHint.NOTIFICATION);
		}

		construct {
			app_system = new Budgie.AppSystem();
			recency = new List<string?>();
			ids = new HashTable<string?,TabSwitcherWidget?>(str_hash, str_equal);

			window_box.set_selection_mode(SelectionMode.SINGLE);

			settings = new GLib.Settings("com.solus-project.budgie-wm");

			show_all_windows = settings.get_boolean(SHOW_ALL_WINDOWS_KEY);
			if (settings != null) settings.changed[SHOW_ALL_WINDOWS_KEY].connect(update_show_all_windows);

			default_screen = Gdk.Screen.get_default();

			xfce_screen = libxfce4windowing.Screen.get_default();

			xfce_screen.get_windows().foreach(add_window);
			xfce_screen.window_opened.connect(add_window);
			workspace_manager = xfce_screen.get_workspace_manager();

			unowned var groups = workspace_manager.list_workspace_groups();

			if (groups != null && groups.length() > 0) {
				workspace_group = groups.nth_data(0);
				workspace_group.active_workspace_changed.connect(on_workspace_changed);
				active_workspace = workspace_group.active_workspace;
			}

			window_box.set_filter_func(flowbox_filter);
			window_box.set_sort_func(flowbox_sort);

			set_position(Gtk.WindowPosition.CENTER_ALWAYS);

			this.hide.connect(this.on_hide);

			/* Skip everything, appear above all else, everywhere. */
			resizable = false;
			skip_pager_hint = true;
			skip_taskbar_hint = true;
			set_decorated(false);
			set_keep_above(true);
			stick();

			/* Set up an RGBA map for transparency styling */
			Gdk.Visual? vis = default_screen.get_rgba_visual();
			if (vis != null) {
				this.set_visual(vis);
			}

			/* Update the primary monitor notion */
			if (screen != null) default_screen.monitors_changed.connect(on_monitors_changed);

			/* Set up size */
			set_default_size(SWITCHER_SIZE, -1);
			realize();

			/* Get everything into position prior to the first showing */
			on_monitors_changed();
		}

		private void add_window(libxfce4windowing.Window window) {
			if (window.is_skip_pager() || window.is_skip_tasklist()) return;

			var window_widget = new TabSwitcherWidget(app_system, window);
			var id = window_widget.id;

			ids.insert(id, window_widget);

			if (get_position_in_recency(id) == -1) recency.append(id);
			window_box.insert(window_widget, -1);

			window_box.set_max_children_per_line(ids.size() < 8 ? ids.size() : 8);

			window_widget.window_activated.connect(set_window_as_activated);

			window_widget.closed.connect(remove_window);

			window_widget.workspace_changed.connect(() => {
				window_box.invalidate_filter(); // Re-filter, maybe window is now on active workspace
			});

			window_box.invalidate_filter(); // Re-filter
			window_box.invalidate_sort(); // Re-sort

			queue_resize();
		}

		private bool flowbox_filter(FlowBoxChild box_child) {
			TabSwitcherWidget? tab =  box_child as TabSwitcherWidget;

			if ((tab == null) || (tab.window == null)) return false; // Hide if we can't cast

			if (tab.window.is_skip_pager() || tab.window.is_skip_tasklist()) return false;
			if (show_all_windows) return true;

			return window_on_active_workspace(tab.window);
		}

		private int flowbox_sort(FlowBoxChild child1, FlowBoxChild child2) {
			TabSwitcherWidget? tab1 =  child1 as TabSwitcherWidget;
			TabSwitcherWidget? tab2 =  child2 as TabSwitcherWidget;
			int64 pos1 = get_position_in_recency(tab1.id);
			int64 pos2 = get_position_in_recency(tab2.id);
			return pos1 < pos2 ? -1 : 1;
		}

		// get_position_in_recency will get the position in recency
		// You might think "hey, but List has an index function, just use that!"
		// No, because for whatever reason it fails at such a basic task
		private int64 get_position_in_recency(string id) {
			for (int i = 0; i < recency.length(); i++) {
				var val = recency.nth_data((uint) i);
				if (val == id) return i;
			}

			return -1;
		}

		/**
		* Make the current selection the active window
		*/
		private void on_hide() {
			var selection = window_box.get_selected_children();
			Gtk.FlowBoxChild? current = null;
			if (selection != null && !selection.is_empty()) {
				current = selection.nth_data(0) as Gtk.FlowBoxChild;
			}

			if (current == null) return;

			/* Get the window, which should be activated and activate that */
			TabSwitcherWidget? tab = current as TabSwitcherWidget;
			window_box.unselect_child(current);

			try {
				tab.window.activate(get_time());
			} catch (GLib.Error e) {
				warning("Failed to activate window: %s\n", e.message);
			}
		}

		private void on_monitors_changed() {
			primary_monitor = default_screen.get_display().get_primary_monitor();
			move_switcher();
		}

		private void on_workspace_changed() {
			if (workspace_group != null) active_workspace = workspace_group.active_workspace;
		}


		public void move_switcher() {
			/* Find the primary monitor bounds */
			Gdk.Rectangle bounds = primary_monitor.get_geometry();
			Gtk.Allocation alloc;

			get_child().get_allocation(out alloc);

			/* For now just center it */
			int x = bounds.x + ((bounds.width / 2) - (alloc.width / 2));
			int y = bounds.y + ((bounds.height / 2) - (alloc.height / 2));
			move(x, y);
		}

		private void remove_window(TabSwitcherWidget? widget) {
			if (widget == null) return;
			ids.remove(widget.id);
			window_box.remove(widget);
			unowned List<string> entries = recency.find_custom(widget.id, strcmp);
			recency.remove_link(entries);
		}

		private void set_window_as_activated(libxfce4windowing.Window window) {
			string id = window.get_id().to_string();
			unowned List<string> entries = recency.find_custom(id, strcmp);
			recency.remove_link(entries);
			recency.prepend(id);
			window_box.invalidate_sort(); // Re-sort
		}

		private void update_show_all_windows() {
			if (settings == null) return;
			show_all_windows = settings.get_boolean(SHOW_ALL_WINDOWS_KEY);
			window_box.invalidate_filter(); // Re-filter
		}

		private bool window_on_active_workspace(libxfce4windowing.Window window) {
			unowned libxfce4windowing.Workspace? win_workspace = window.get_workspace(); // Get workspace
			if (active_workspace == null || win_workspace == null) return true;
			return win_workspace.get_id() == active_workspace.get_id();
		}

		/* Switch focus to the item with the xid */
		public void focus_item(bool backwards) {
			unowned libxfce4windowing.Window? active_window = xfce_screen.get_active_window();
			TabSwitcherWidget? widget = active_window != null ? ids.get(active_window.get_id().to_string()) : null;

			// Visible, each input should cycle to previous / next
			if (visible) {
				widget = window_box.get_selected_children().nth_data(0) as TabSwitcherWidget;
				if (widget != null) active_window = widget.window;
			} else if (!visible && widget != null) {
				window_box.select_child(widget);
			}

			FlowBoxChild? new_child = null;
			TabSwitcherWidget? new_widget = null;

			var len = recency.length();
			int64 id_pos = (widget != null) ? get_position_in_recency(widget.id).clamp(0, len - 1) : 0;

			for (var i = 0; i < len; i++) {
				uint64 new_id_pos = 0;

				if (backwards) {
					// If our current position is 0, we can't go any further "back" so wrap around to end
					// Otherwise, use the current position of window in recency
					// Then, minus the position by next index + 1
					// e.g. first iteration for last item in array of 5 is (5 - 0+1) -> 4 -> 0-based index means this is last item
					new_id_pos = (id_pos == 0 ? len : id_pos) - (i+1);
				} else {
					// Similar behavior as backwards..just forwards and wrap to beginning instead of end
					new_id_pos = id_pos == len - 1 ? 0 : id_pos + (i+1);
				}

				var child_at_pos = window_box.get_child_at_index((int)new_id_pos);
				if (child_at_pos == null) continue;

				var widget_at_pos = child_at_pos as TabSwitcherWidget;
				if (widget_at_pos == null || widget_at_pos.window == null) continue;

				if (!show_all_windows && !window_on_active_workspace(widget_at_pos.window)) continue;

				new_child = child_at_pos;
				new_widget = widget_at_pos;
				break;
			}

			if (new_child == null) return;
			if (new_widget == null) return;

			window_title.set_text(new_widget.title);
			window_box.select_child(new_child);
		}
	}

	/**
	* TabSwitcher is responsible for managing the BudgieSwitcher over d-bus, receiving
	* requests, for example, from budgie-wm
	*/
	[DBus (name="org.budgie_desktop.TabSwitcher")]
	public class TabSwitcher : GLib.Object {
		private TabSwitcherWindow? switcher_window = null;
		private uint32 mod_timeout = 0;

		[DBus (visible=false)]
		public TabSwitcher() {
			switcher_window = new TabSwitcherWindow();
		}

		/**
		* Own the SWITCHER_DBUS_NAME
		*/
		[DBus (visible=false)]
		public void setup_dbus(bool replace) {
			var flags = BusNameOwnerFlags.ALLOW_REPLACEMENT;
			if (replace) {
				flags |= BusNameOwnerFlags.REPLACE;
			}
			Bus.own_name(BusType.SESSION, SWITCHER_DBUS_NAME, flags,
				on_bus_acquired, ()=> {}, DaemonNameLost);
			}

			/**
			* Acquired SWITCHER_DBUS_NAME, register ourselves on the bus
			*/
			private void on_bus_acquired(DBusConnection conn) {
				try {
					conn.register_object(SWITCHER_DBUS_OBJECT_PATH, this);
				} catch (GLib.Error e) {
					stderr.printf("Error registering TabSwitcher: %s\n", e.message);
				}
				setup = true;
			}

			public void ShowSwitcher(bool backwards) throws DBusError, IOError {
				this.add_mod_key_watcher();

				switcher_window.move_switcher();
				switcher_window.focus_item(backwards);
				switcher_window.show_all();
			}

			public void StopSwitcher() throws DBusError, IOError {
				switcher_window.hide();
			}

			private void add_mod_key_watcher() {
				if (mod_timeout != 0) {
					Source.remove(mod_timeout);
					mod_timeout = 0;
				}
				mod_timeout = Timeout.add(SWITCHER_MOD_EXPIRE_TIME, (SourceFunc)this.check_mod_key);
			}

			private bool check_mod_key() {
				mod_timeout = 0;
				Gdk.ModifierType modifier;
				Gdk.Display.get_default().get_default_seat().get_pointer().get_state(Gdk.get_default_root_window(), null, out modifier);
				if ((modifier & Gdk.ModifierType.MOD1_MASK) == 0 && (modifier & Gdk.ModifierType.MOD3_MASK) == 0 && (modifier & Gdk.ModifierType.MOD4_MASK) == 0 && (modifier & Gdk.ModifierType.CONTROL_MASK) == 0) {
					switcher_window.hide();
					return false;
				}

				/* restart the timeout */
				return true;
			}
		}
	}
