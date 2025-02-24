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

namespace Workspaces {
	[Flags]
	public enum AddButtonVisibility {
		NEVER = 1 << 0,
		HOVER = 1 << 1,
		ALWAYS = 1 << 2
	}

	public class WorkspacesPlugin : Budgie.Plugin, Peas.ExtensionBase {
		public Budgie.Applet get_panel_widget(string uuid) {
			return new WorkspacesApplet(uuid);
		}
	}

	[GtkTemplate (ui="/com/solus-project/workspaces/settings.ui")]
	public class WorkspacesAppletSettings : Gtk.Grid {
		[GtkChild]
		private unowned Gtk.ComboBoxText? combobox_visibility;
		[GtkChild]
		private unowned Gtk.ComboBoxText? combobox_multiplier;

		private Settings? settings;

		public WorkspacesAppletSettings(Settings? settings) {
			this.settings = settings;
			settings.bind("addbutton-visibility", combobox_visibility, "active_id", SettingsBindFlags.DEFAULT);
			settings.bind("item-size-multiplier", combobox_multiplier, "active_id", SettingsBindFlags.DEFAULT);
		}
	}

	public class WorkspacesApplet : Budgie.Applet {
		private Gtk.EventBox ebox;
		private Gtk.Box main_layout;
		private Gtk.Box workspaces_layout;
		private Gtk.Revealer add_button_revealer;
		private Gtk.RevealerTransitionType show_transition = Gtk.RevealerTransitionType.SLIDE_RIGHT;
		private Gtk.RevealerTransitionType hide_transition = Gtk.RevealerTransitionType.SLIDE_LEFT;
		private bool startup = true;
		private int size_change = 0;
		private bool updating = false;
		private ulong[] connections = {};
		private HashTable<unowned libxfce4windowing.Window, ulong> window_connections;
		private List<int> dynamically_created_workspaces;
		private Settings settings;
		private AddButtonVisibility button_visibility = AddButtonVisibility.ALWAYS;
		private float item_size_multiplier = 1.0f;

		public string uuid { public set ; public get ; }

		public static Budgie.PanelPosition panel_position = Budgie.PanelPosition.BOTTOM;
		public static int panel_size = 0;
		public static unowned Budgie.PopoverManager? manager = null;
		public static libxfce4windowing.Screen xfce_screen;
		public static libxfce4windowing.WorkspaceManager workspace_manager;
		public static libxfce4windowing.WorkspaceGroup workspace_group;
		public static bool dragging = false;

		private int64 last_scroll_time = 0;

		public override Gtk.Widget? get_settings_ui() {
			return new WorkspacesAppletSettings(this.get_applet_settings(uuid));
		}

		public override bool supports_settings() {
			return true;
		}

		public WorkspacesApplet(string uuid) {
			Object(uuid: uuid);

			settings_schema = "com.solus-project.workspaces";
			settings_prefix = "/com/solus-project/budgie-panel/instance/workspaces";

			settings = this.get_applet_settings(uuid);
			settings.changed.connect(on_settings_change);

			xfce_screen = libxfce4windowing.Screen.get_default();
			workspace_manager = xfce_screen.get_workspace_manager();

			workspace_group = workspace_manager.list_workspace_groups().nth_data(0);

			dynamically_created_workspaces = new List<int>();
			window_connections = new HashTable<unowned libxfce4windowing.Window, ulong>(str_hash, str_equal);

			ebox = new Gtk.EventBox();
			ebox.add_events(Gdk.EventMask.SCROLL_MASK);
			this.add(ebox);

			main_layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
			main_layout.get_style_context().add_class("workspace-switcher");
			main_layout.spacing = 4;
			ebox.add(main_layout);

			workspaces_layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
			workspaces_layout.get_style_context().add_class("workspace-layout");
			main_layout.pack_start(workspaces_layout, true, true, 0);

			add_button_revealer = new Gtk.Revealer();
			add_button_revealer.set_transition_duration(200);
			add_button_revealer.set_transition_type(hide_transition);
			add_button_revealer.set_reveal_child(false);

			Gtk.Button add_button = new Gtk.Button.from_icon_name("list-add-symbolic", Gtk.IconSize.MENU);
			add_button.get_style_context().add_class("workspace-add-button");
			add_button.valign = Gtk.Align.CENTER;
			add_button.halign = Gtk.Align.CENTER;

			if (!(libxfce4windowing.WorkspaceGroupCapabilities.CREATE_WORKSPACE in workspace_group.get_capabilities())) {
				add_button.sensitive = false;
				add_button.set_tooltip_text(_("Not able to create new workspaces"));
			} else {
				add_button.set_tooltip_text(_("Create a new workspace"));
			}

			add_button_revealer.add(add_button);
			main_layout.pack_start(add_button_revealer, false, false, 0);

			on_settings_change("addbutton-visibility");
			on_settings_change("item-size-multiplier");

			Gtk.drag_dest_set(
				add_button,
				Gtk.DestDefaults.MOTION | Gtk.DestDefaults.HIGHLIGHT,
				target_list,
				Gdk.DragAction.MOVE
			);

			add_button.drag_drop.connect(on_add_button_drag_drop);
			add_button.drag_data_received.connect(on_add_button_drag_data_received);

			add_button.button_release_event.connect((event) => {
				try {
					add_new_workspace();
					uint new_index = workspace_group.get_workspace_count() - 1;

					 if (new_index != -1) {
					 	set_current_workspace();
					 }
				} catch (Error e) {
					warning("Failed to append new workspace: %s", e.message);
				}

				return false;
			});

			Idle.add(() => {
				Timeout.add(500, () => {
					startup = false;
					update_workspaces.begin();
					return false;
				});
				return false;
			});

			populate_workspaces();
			this.show_all();

			ebox.enter_notify_event.connect(() => {
				if (button_visibility != AddButtonVisibility.HOVER) {
					return Gdk.EVENT_PROPAGATE;
				}

				if (below_max_workspaces()) {
					add_button_revealer.set_transition_type(show_transition);
					add_button_revealer.set_reveal_child(true);
				}

				return Gdk.EVENT_PROPAGATE;
			});

			ebox.leave_notify_event.connect(() => {
				if (dragging || button_visibility != AddButtonVisibility.HOVER) {
					return Gdk.EVENT_PROPAGATE;
				}
				add_button_revealer.set_transition_type(hide_transition);
				add_button_revealer.set_reveal_child(false);
				return Gdk.EVENT_PROPAGATE;
			});

			ebox.scroll_event.connect((e) => {
				if (e.direction >= 4) {
					return Gdk.EVENT_STOP;
				}

				bool down = e.direction == Gdk.ScrollDirection.DOWN;
				bool up = e.direction == Gdk.ScrollDirection.UP;

				if (!down && !up) return Gdk.EVENT_STOP;

				if (get_monotonic_time() - last_scroll_time < 300000) {
					return Gdk.EVENT_STOP;
				}

				unowned libxfce4windowing.Workspace current = workspace_group.get_active_workspace();
				unowned libxfce4windowing.Workspace? next = current.get_neighbor(
					(down) ? libxfce4windowing.Direction.RIGHT : libxfce4windowing.Direction.DOWN
				);

				if (next != null) {
					try {
						next.activate();
					} catch (Error e) {
						warning("Failed to switch to workspace: %s", e.message);
					}
					last_scroll_time = get_monotonic_time();
				}

				return Gdk.EVENT_STOP;
			});

			workspace_group.capabilities_changed.connect((changed_mask, new_capabilities) => {
				if (libxfce4windowing.WorkspaceGroupCapabilities.CREATE_WORKSPACE in changed_mask) {
					if (!(libxfce4windowing.WorkspaceGroupCapabilities.CREATE_WORKSPACE in new_capabilities)) {
						add_button.sensitive = false;
						add_button.set_tooltip_text(_("Not able to create new workspaces"));
					} else {
						add_button.sensitive = true;
						add_button.set_tooltip_text(_("Create a new workspace"));
					}
				}
			});
		}

		private void on_settings_change(string key) {
			if (key == "addbutton-visibility") {
				button_visibility = (AddButtonVisibility) settings.get_enum(key);
				var should_show = below_max_workspaces() && button_visibility == AddButtonVisibility.ALWAYS;
				add_button_revealer.set_reveal_child(should_show);
			} else if (key == "item-size-multiplier") {
				item_size_multiplier = (float) settings.get_enum(key) / 4;
				foreach (Gtk.Widget widget in workspaces_layout.get_children()) {
					Gtk.Revealer revealer = widget as Gtk.Revealer;
					WorkspaceItem item = revealer.get_child() as WorkspaceItem;
					item.set_size_multiplier(item_size_multiplier);
					item.queue_resize();
				}
				Timeout.add(100, () => {
					update_workspaces.begin();
					return false;
				});
			}
		}

		private void populate_workspaces() {
			foreach (libxfce4windowing.Workspace workspace in workspace_group.list_workspaces()) {
				workspace_added(workspace);
			}
			this.connect_signals();
			this.queue_resize();
			foreach (libxfce4windowing.Window window in xfce_screen.get_windows()) {
				window_opened(window);
			}
		}

		private bool below_max_workspaces() {
			return workspace_group.get_workspace_count() < 8;
		}

		private void connect_signals() {
			connections += workspace_group.workspace_added.connect(workspace_added);
			connections += workspace_group.workspace_removed.connect(workspace_removed);
			connections += workspace_group.active_workspace_changed.connect(set_current_workspace);
			connections += xfce_screen.active_window_changed.connect(update_workspaces);
			connections += xfce_screen.window_opened.connect(window_opened);
			connections += xfce_screen.window_closed.connect(window_closed);
		}

		private void disconnect_signals() {
			foreach (ulong id in connections) {
				if (SignalHandler.is_connected(workspace_group, id)) {
					SignalHandler.disconnect(workspace_group, id);
				} else if (SignalHandler.is_connected(xfce_screen, id)) {
					SignalHandler.disconnect(xfce_screen, id);
				}
			}

			window_connections.@foreach((key, val) => {
				if (SignalHandler.is_connected(key, val)) {
					SignalHandler.disconnect(key, val);
				}
				window_connections.remove(key);
			});
		}

		private void workspace_added(libxfce4windowing.Workspace space) {
			WorkspaceItem item = new WorkspaceItem(space, item_size_multiplier);
			var _workspace = workspace_group.get_active_workspace();
			if (_workspace != null && _workspace == space) {
				item.get_style_context().add_class("current-workspace");
			}
			item.remove_workspace.connect(remove_workspace);
			Gtk.Revealer revealer = new Gtk.Revealer();
			revealer.add(item);
			revealer.set_transition_type(show_transition);
			revealer.set_transition_duration(200);
			revealer.valign = Gtk.Align.CENTER;
			revealer.halign = Gtk.Align.CENTER;
			revealer.show_all();
			workspaces_layout.pack_start(revealer, true, true, 0);
			revealer.set_reveal_child(true);

			if (!below_max_workspaces()) {
				add_button_revealer.set_reveal_child(false);
			}
		}

		private void workspace_removed(libxfce4windowing.Workspace space) {
			foreach (var widget in workspaces_layout.get_children()) {
				Gtk.Revealer revealer = widget as Gtk.Revealer;
				WorkspaceItem item = revealer.get_child() as WorkspaceItem;
				if (item.get_workspace() == space) {
					revealer.set_transition_type(hide_transition);
					revealer.set_reveal_child(false);
					Timeout.add(200, () => {
						widget.destroy();
						return false;
					});
					break;
				}
			}

			add_button_revealer.set_reveal_child(true);
		}

		private void window_opened(libxfce4windowing.Window window) {
			if (window.get_window_type() != libxfce4windowing.WindowType.NORMAL) {
				return;
			}

			if (libxfce4windowing.windowing_get() != libxfce4windowing.Windowing.WAYLAND) return;

			if (window_connections.contains(window)) {
				ulong conn = window_connections.get(window);
				if (SignalHandler.is_connected(window, conn)) {
					SignalHandler.disconnect(window, conn);
				}
				window_connections.remove(window);
			}
			ulong conn = window.workspace_changed.connect(update_workspaces);
			window_connections.set(window, conn);
		}

		private void window_closed(libxfce4windowing.Window window) {
			if (window_connections.contains(window)) {
				ulong conn = window_connections.get(window);
				if (SignalHandler.is_connected(window, conn)) {
					SignalHandler.disconnect(window, conn);
				}
				window_connections.remove(window);
			}

			update_workspaces.begin();
		}

		private bool on_add_button_drag_drop(Gtk.Widget widget, Gdk.DragContext context, int x, int y, uint time) {
			bool is_valid_drop_site = true;

			if (context.list_targets() != null) {
				var target_type = (Gdk.Atom)context.list_targets().nth_data(0);
				Gtk.drag_get_data(
					widget,
					context,
					target_type,
					time
				);
			} else {
				is_valid_drop_site = false;
			}

			return is_valid_drop_site;
		}

		private void on_add_button_drag_data_received(Gtk.Widget widget, Gdk.DragContext context, int x, int y, Gtk.SelectionData selection_data, uint target_type, uint time) {
			if (selection_data == null || selection_data.get_length() == 0) {
				Gtk.drag_finish(context, false, true, time);
				return;
			}

			string? data = selection_data.get_text();
			if (data == null) {
				Gtk.drag_finish(context, false, true, time);
				return;
			}

			libxfce4windowing.Window? window = null;
			foreach (libxfce4windowing.Window win in xfce_screen.get_windows()) {
				string all_class_names = string.joinv(",", window.get_class_ids());
				if (all_class_names == data) {
					window = win;
					break;
				}
			}

			if (window == null)	{
				Gtk.drag_finish(context, false, true, time);
				return;
			}

			add_new_workspace();
			uint new_index = workspace_group.get_workspace_count() - 1;

			if (new_index != -1) { // Successfully added workspace
				dynamically_created_workspaces.append((int) new_index);
				Timeout.add(50, () => {
					libxfce4windowing.Workspace? workspace = get_workspace_by_index(new_index);
					try {
						if (workspace != null) window.move_to_workspace(workspace);
					} catch (Error e) {
						warning("Failed to move window to workspace: %s", e.message);
					}
					return false;
				});
			}

			Gtk.drag_finish(context, true, true, time);
		}

		public override void panel_size_changed(int panel_size, int icon_size, int small_icon_size) {
			WorkspacesApplet.panel_size = panel_size;

			if (startup) {
				return;
			}

			size_change++;
			if (size_change == 2) {
				update_workspaces.begin();
				size_change = 0;
			}
		}

		public override void panel_position_changed(Budgie.PanelPosition position) {
			WorkspacesApplet.panel_position = position;

			Gtk.Orientation orient = Gtk.Orientation.HORIZONTAL;
			if (position == Budgie.PanelPosition.LEFT || position == Budgie.PanelPosition.RIGHT) {
				orient = Gtk.Orientation.VERTICAL;
			}

			this.main_layout.set_orientation(orient);
			this.workspaces_layout.set_orientation(orient);

			if (get_orientation() == Gtk.Orientation.HORIZONTAL) {
				show_transition = Gtk.RevealerTransitionType.SLIDE_RIGHT;
				hide_transition = Gtk.RevealerTransitionType.SLIDE_LEFT;
			} else {
				show_transition = Gtk.RevealerTransitionType.SLIDE_DOWN;
				hide_transition = Gtk.RevealerTransitionType.SLIDE_UP;
			}

			if (!startup) {
				Timeout.add(500, () => {
					update_workspaces.begin();
					return false;
				});
			}
		}

		private void add_new_workspace() {
			try {
				workspace_group.create_workspace("Workspace %lu".printf(workspace_group.get_workspace_count() + 1));
				workspace_group.set_layout((int) workspace_group.get_workspace_count(), 1);
			} catch (Error e) {
				warning("Failed to append new workspace: %s", e.message);
			}
		}

		private void remove_workspace(uint index, uint32 time) {
			var workspace = get_workspace_by_index((uint)index);

			try {
				workspace.remove();
			} catch (Error e) {
				warning("Failed to remove workspace at index %lu: %s", index, e.message);
			}
		}

		private void set_current_workspace() {
			foreach (Gtk.Widget widget in workspaces_layout.get_children()) {
				Gtk.Revealer revealer = widget as Gtk.Revealer;
				WorkspaceItem item = revealer.get_child() as WorkspaceItem;
				item.get_style_context().remove_class("current-workspace");
				if (item.get_workspace() == workspace_group.get_active_workspace()) {
					item.get_style_context().add_class("current-workspace");
				}
			}
		}

		private async void update_workspaces() {
			if (updating || startup) {
				return;
			}

			updating = true;

			if (this.get_parent() == null) {
				disconnect_signals();
				return;
			}

			foreach (Gtk.Widget widget in workspaces_layout.get_children()) {
				Gtk.Revealer revealer = widget as Gtk.Revealer;
				WorkspaceItem item = revealer.get_child() as WorkspaceItem;
				unowned List<libxfce4windowing.Window>? windows = xfce_screen.get_windows();
				List<libxfce4windowing.Window> window_list = new List<libxfce4windowing.Window>();

				windows.foreach((window) => {
					if (window.get_workspace() == item.get_workspace() && !window.is_skip_tasklist() && !window.is_skip_pager() && window.get_window_type() == libxfce4windowing.WindowType.NORMAL) {
						window_list.append(window);
					}
				});

				int index = (int)item.get_workspace().get_number();
				unowned List<int>? dyn = dynamically_created_workspaces.find(index);

				if (window_list.is_empty() && dyn != null) {
					dynamically_created_workspaces.remove(index);
					dyn = dynamically_created_workspaces.find(index+1);

					if (dyn == null) {
						Timeout.add(200, () => {
							remove_workspace(index, Gdk.CURRENT_TIME);

							return false;
						});
					}
				}

				item.update_windows(window_list);
			}

			updating = false;
		}

		public override void update_popovers(Budgie.PopoverManager? manager) {
			WorkspacesApplet.manager = manager;
		}

		public static Gtk.Orientation get_orientation() {
			switch (panel_position) {
				case Budgie.PanelPosition.TOP:
				case Budgie.PanelPosition.BOTTOM:
					return Gtk.Orientation.HORIZONTAL;
				default:
					return Gtk.Orientation.VERTICAL;
			}
		}

		private libxfce4windowing.Workspace? get_workspace_by_index(uint num) {
			unowned GLib.List<libxfce4windowing.Workspace>? workspaces = workspace_group.list_workspaces();
			return workspaces.nth_data(num);
		}
	}
}

[ModuleInit]
public void peas_register_types(TypeModule module) {
	Peas.ObjectModule objmodule = module as Peas.ObjectModule;
	objmodule.register_extension_type(typeof(Budgie.Plugin), typeof(Workspaces.WorkspacesPlugin));
}
