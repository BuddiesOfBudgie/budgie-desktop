/*
 * This file is part of budgie-desktop
 *
 * Copyright © 2017-2022 Budgie Desktop Developers
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

	[DBus (name="org.budgie_desktop.BudgieWM")]
	public interface BudgieWM : GLib.Object {
		public abstract void RemoveWorkspaceByIndex(int index, uint32 time) throws Error;
		public abstract int AppendNewWorkspace(uint32 time) throws Error;
	}

	public class WorkspacesApplet : Budgie.Applet {
		private BudgieWM? wm_proxy = null;
		private Gtk.EventBox ebox;
		private Gtk.Box main_layout;
		private Gtk.Box workspaces_layout;
		private Gtk.Revealer add_button_revealer;
		private Gtk.RevealerTransitionType show_transition = Gtk.RevealerTransitionType.SLIDE_RIGHT;
		private Gtk.RevealerTransitionType hide_transition = Gtk.RevealerTransitionType.SLIDE_LEFT;
		private bool startup = true;
		private int size_change = 0;
		private bool updating = false;
		private ulong[] wnck_connections = {};
		private HashTable<unowned Wnck.Window, ulong> window_connections;
		private List<int> dynamically_created_workspaces;
		private Settings settings;
		private AddButtonVisibility button_visibility = AddButtonVisibility.ALWAYS;
		private float item_size_multiplier = 1.0f;

		public string uuid { public set ; public get ; }

		public static Budgie.PanelPosition panel_position = Budgie.PanelPosition.BOTTOM;
		public static int panel_size = 0;
		public static unowned Budgie.PopoverManager? manager = null;
		public static Wnck.Screen wnck_screen;
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

			WorkspacesApplet.wnck_screen = Wnck.Screen.get_default();

			dynamically_created_workspaces = new List<int>();
			window_connections = new HashTable<unowned Wnck.Window, ulong>(str_hash, str_equal);

			Bus.watch_name(BusType.SESSION, "org.budgie_desktop.BudgieWM", BusNameWatcherFlags.NONE,
				has_wm, lost_wm);

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
					int new_index = wm_proxy.AppendNewWorkspace(event.time);

					if (new_index != -1) {
						set_current_workspace();
					} else if (!below_max_workspace_count()) { // Last workspace
						add_button_revealer.set_reveal_child(false); // Hide add button
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
					return false;
				}

				if (below_max_workspace_count()) { // Is below max workspace count
					add_button_revealer.set_transition_type(show_transition);
					add_button_revealer.set_reveal_child(true);
				}

				return false;
			});

			ebox.leave_notify_event.connect(() => {
				if (dragging || button_visibility != AddButtonVisibility.HOVER) {
					return false;
				}
				add_button_revealer.set_transition_type(hide_transition);
				add_button_revealer.set_reveal_child(false);
				return false;
			});

			ebox.scroll_event.connect((e) => {
				if (e.direction >= 4) {
					return Gdk.EVENT_STOP;
				}

				if (get_monotonic_time() - last_scroll_time < 300000) {
					return Gdk.EVENT_STOP;
				}

				unowned Wnck.Workspace current = wnck_screen.get_active_workspace();
				unowned Wnck.Workspace? next = null;

				if (e.direction == Gdk.ScrollDirection.DOWN) {
					next = wnck_screen.get_workspace(current.get_number() + 1);
				} else if (e.direction == Gdk.ScrollDirection.UP) {
					next = wnck_screen.get_workspace(current.get_number() - 1);
				}

				if (next != null) {
					next.activate(e.time);
					last_scroll_time = get_monotonic_time();
				}

				return Gdk.EVENT_STOP;
			});
		}

		private void on_settings_change(string key) {
			if (key == "addbutton-visibility") {
				button_visibility = (AddButtonVisibility)settings.get_enum(key);
				add_button_revealer.set_reveal_child(((button_visibility == AddButtonVisibility.ALWAYS) && below_max_workspace_count()));
			} else if (key == "item-size-multiplier") {
				item_size_multiplier = float.parse(settings.get_string(key));
				foreach (Gtk.Widget widget in workspaces_layout.get_children()) {
					Gtk.Revealer revealer = widget as Gtk.Revealer;
					WorkspaceItem item = revealer.get_child() as WorkspaceItem;
					item.set_size_multiplier(item_size_multiplier);
				}
				Timeout.add(100, () => {
					update_workspaces.begin();
					return false;
				});
			}
		}

		private void populate_workspaces() {
			foreach (Wnck.Workspace workspace in wnck_screen.get_workspaces()) {
				workspace_added(workspace);
			}
			this.connect_signals();
			this.queue_resize();
			foreach (Wnck.Window window in wnck_screen.get_windows()) {
				window_opened(window);
			}
		}

		private void lost_wm() {
			wm_proxy = null;
		}

		private void on_wm_get(Object? o, AsyncResult? res) {
			try {
				wm_proxy = Bus.get_proxy.end(res);
			} catch (Error e) {
				warning("Failed to get BudgieWM proxy: %s", e.message);
			}
		}

		private void has_wm() {
			if (wm_proxy == null) {
				Bus.get_proxy.begin<BudgieWM>(BusType.SESSION,
					"org.budgie_desktop.BudgieWM",
					"/org/budgie_desktop/BudgieWM", 0, null, on_wm_get);
			}
		}

		private bool below_max_workspace_count() {
			return (wnck_screen.get_workspace_count() < 8);
		}

		private void connect_signals() {
			wnck_connections += wnck_screen.workspace_created.connect(workspace_added);
			wnck_connections += wnck_screen.workspace_destroyed.connect(workspace_removed);
			wnck_connections += wnck_screen.active_workspace_changed.connect(set_current_workspace);
			wnck_connections += wnck_screen.active_window_changed.connect(update_workspaces);
			wnck_connections += wnck_screen.window_opened.connect(window_opened);
			wnck_connections += wnck_screen.window_closed.connect(window_closed);
		}

		private void disconnect_signals() {
			foreach (ulong id in wnck_connections) {
				if (SignalHandler.is_connected(wnck_screen, id)) {
					SignalHandler.disconnect(wnck_screen, id);
				}
			}

			window_connections.@foreach((key, val) => {
				if (SignalHandler.is_connected(key, val)) {
					SignalHandler.disconnect(key, val);
				}
				window_connections.remove(key);
			});
		}

		private void workspace_added(Wnck.Workspace space) {
			WorkspaceItem item = new WorkspaceItem(space, item_size_multiplier);
			var _workspace = wnck_screen.get_active_workspace();
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

			if (!below_max_workspace_count()) {
				add_button_revealer.set_reveal_child(false);
			}
		}

		private void workspace_removed(Wnck.Workspace space) {
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

		private void window_opened(Wnck.Window window) {
			if (window.get_window_type() != Wnck.WindowType.NORMAL) {
				return;
			}

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

		private void window_closed(Wnck.Window window) {
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
			bool dnd_success = false;
			if (selection_data != null && selection_data.get_length() >= 0) {
				ulong* data = (ulong*) selection_data.get_data();
				if (data != null) {
					Wnck.Window window = Wnck.Window.@get(*data);

					try {
						int index = wm_proxy.AppendNewWorkspace(time);

						if (index != -1) { // Successfully added workspace
							dynamically_created_workspaces.append(index);
							Timeout.add(50, () => {
								window.move_to_workspace(wnck_screen.get_workspace(index));
								return false;
							});
							dnd_success = true;
						}
					} catch (Error e) {
						warning("Failed to append new workspace: %s", e.message);
					}
				}
			}

			Gtk.drag_finish(context, dnd_success, true, time);
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

		private void remove_workspace(int index, uint32 time) {
			if (wm_proxy == null) {
				return;
			}

			var workspace = wnck_screen.get_workspace(index);

			try {
				wm_proxy.RemoveWorkspaceByIndex(index, time);

				var _workspace = wnck_screen.get_active_workspace();
				if (_workspace != null && _workspace == workspace) {
					var previous = wnck_screen.get_workspace((index == 0) ? index : index - 1);
					previous.activate(time);
				}
			} catch (Error e) {
				warning("Failed to remove workspace at index %i: %s", index, e.message);
			}
		}

		private void set_current_workspace() {
			foreach (Gtk.Widget widget in workspaces_layout.get_children()) {
				Gtk.Revealer revealer = widget as Gtk.Revealer;
				WorkspaceItem item = revealer.get_child() as WorkspaceItem;
				item.get_style_context().remove_class("current-workspace");
				if (item.get_workspace() == wnck_screen.get_active_workspace()) {
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
				List<unowned Wnck.Window> windows = wnck_screen.get_windows_stacked().copy();
				windows.reverse();
				List<unowned Wnck.Window> window_list = new List<unowned Wnck.Window>();
				windows.foreach((window) => {
					if (window.get_workspace() == item.get_workspace() && !window.is_skip_tasklist() && !window.is_skip_pager() && window.get_window_type() == Wnck.WindowType.NORMAL) {
						window_list.append(window);
					}
				});
				int index = item.get_workspace().get_number();
				unowned List<int>? dyn = dynamically_created_workspaces.find(index);
				if (window_list.length() == 0 && dyn != null) {
					dynamically_created_workspaces.remove(index);
					dyn = dynamically_created_workspaces.find(index+1);
					if (dyn == null) {
						Timeout.add(200, () => {
							try {
								wm_proxy.RemoveWorkspaceByIndex(index, Gdk.CURRENT_TIME);
							} catch (Error e) {
								warning("Failed to remove workspace at index %i: %s", index, e.message);
							}

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
	}
}

[ModuleInit]
public void peas_register_types(TypeModule module) {
	Peas.ObjectModule objmodule = module as Peas.ObjectModule;
	objmodule.register_extension_type(typeof(Budgie.Plugin), typeof(Workspaces.WorkspacesPlugin));
}
