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

const string SETTINGS_DBUS_NAME = "org.budgie_desktop.Settings";
const string SETTINGS_DBUS_PATH = "/org/budgie_desktop/Settings";

[DBus (name="org.budgie_desktop.Settings")]
public interface SettingsRemote : GLib.Object {
	public abstract async void Close() throws Error;
}

public class ButtonPopover : Gtk.Popover {
	public Budgie.Application? app { get; construct; }
	public Budgie.Windowing.WindowGroup? group { get; construct set; }

	private bool _pinned = false;
	public bool pinned {
		get { return _pinned; }
		construct set {
			_pinned = value;
			if (pin_button == null) return;
			pin_button.tooltip_text = _pinned ? _("Unfavorite") : _("Favorite");

			if (value) {
				pin_icon.get_style_context().add_class("alert");
			} else {
				pin_icon.get_style_context().remove_class("alert");
			}
		}
	}

	private Gtk.Image pin_icon;
	private Gtk.Stack? stack;
	private Gtk.ListBox? desktop_actions;
	private Gtk.ListBox? windows;
	private Gtk.Button? pin_button;
	private Gtk.Button? new_instance_button;
	private Gtk.Button? close_all_button;

	public ButtonPopover(IconButton button, Budgie.Application? app, Budgie.Windowing.WindowGroup? group) {
		Object(relative_to: button, app: app, group: group);
	}

	construct {
		width_request = 200;

		get_style_context().add_class("icon-popover");

		desktop_actions = new Gtk.ListBox() {
			selection_mode = Gtk.SelectionMode.NONE,
		};

		if (app != null) {
			var app_info = new DesktopAppInfo(app.desktop_id);

			foreach (var action in app.actions) {
				var action_label = app_info.get_action_name(action);

				var action_button = new Gtk.Button.with_label(action_label) {
					relief = Gtk.ReliefStyle.NONE,
				};

				var label = action_button.get_child() as Gtk.Label;
				label.set_xalign(0);

				action_button.clicked.connect(() => {
					app.launch_action(action);
					hide();
				});

				desktop_actions.add(action_button);
			}
		}

		windows = new Gtk.ListBox() {
			selection_mode = Gtk.SelectionMode.NONE,
		};

		if (group != null) {
			foreach (var window in group.get_windows()) {
				add_window(window);
			}
		}

		pin_icon = new Gtk.Image.from_icon_name("budgie-emblem-favorite-symbolic", Gtk.IconSize.SMALL_TOOLBAR);
		pin_icon.get_style_context().add_class("icon-popover-pin");

		close_all_button = new Gtk.Button.from_icon_name("list-remove-all-symbolic", Gtk.IconSize.SMALL_TOOLBAR) {
			tooltip_text = _("Close all windows"),
			relief = Gtk.ReliefStyle.NONE,
		};

		close_all_button.clicked.connect(on_close_all_clicked);

		var button_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);

		if (app != null) {
			pin_button = new Gtk.Button() {
				image = pin_icon,
				tooltip_text = _pinned ? _("Unfavorite") : _("Favorite"),
				relief = Gtk.ReliefStyle.NONE,
			};

			pin_button.clicked.connect(on_pin_clicked);

			new_instance_button = new Gtk.Button.from_icon_name("window-new-symbolic", Gtk.IconSize.SMALL_TOOLBAR) {
				tooltip_text = _("Launch new instance"),
				relief = Gtk.ReliefStyle.NONE,
			};

			new_instance_button.clicked.connect(on_new_instance_clicked);

			button_box.pack_start(pin_button);
			button_box.pack_start(new_instance_button);
		}

		button_box.pack_start(close_all_button);

		var main_layout = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);

		if (!desktop_actions.get_children().is_empty()) {
			var separator = new Gtk.Separator(Gtk.Orientation.HORIZONTAL);

			main_layout.pack_start(desktop_actions);
			main_layout.pack_start(separator);
		}

		main_layout.pack_start(windows);
		main_layout.pack_start(button_box);

		stack = new Gtk.Stack() {
			transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT,
		};

		stack.add_named(main_layout, "main");
		stack.get_style_context().add_class("icon-popover-stack");

		add(stack);

		stack.show_all();
	}

	private void on_pin_clicked() {
		pinned = !pinned;
		hide();
	}

	private void on_new_instance_clicked() {
		if (app == null) return;
		app.launch();
		hide();
	}

	private void on_close_all_clicked() {
		var windows = group.get_windows();

		foreach (var window in windows) {
			try {
				window.close(Gtk.get_current_event_time());
			} catch (Error e) {
				warning("Unable to close window '%s': %s", window.get_name(), e.message);
			}
		}

		hide();
	}

	public override void hide() {
		base.hide();

		if (stack.get_visible_child_name() != "main") {
			var page = stack.get_visible_child();
			stack.set_visible_child_name("main");
			stack.remove(page);
			page.destroy();
		}
	}

	public void add_window(libxfce4windowing.Window window) {
		var window_item = new WindowItem(window);

		window_item.page_switch_clicked.connect(() => {
			var controls_layout = new WindowControls(window);

			controls_layout.return_clicked.connect(() => {
				stack.set_visible_child_name("main");
				stack.remove(controls_layout);
				controls_layout.destroy();
			});

			string id = ((ulong) window.x11_get_xid()).to_string();
			stack.add_named(controls_layout, id);
			stack.set_visible_child_name(id);
		});

		windows.add(window_item);
	}

	public void remove_window(libxfce4windowing.Window window) {
		ulong window_id = (ulong) window.x11_get_xid();
		WindowItem? window_item = null;

		// Get the window item for this window, if exists
		foreach (var child in windows.get_children()) {
			ulong child_id = (ulong) ((WindowItem) child).window.x11_get_xid();
			if (child_id == window_id) {
				window_item = child as WindowItem;
				break;
			}
		}

		if (window_item == null) return;

		window_item.destroy();

		string id = window_id.to_string();

		// Set the stack page to the main layout if we happen to have this window's page open
		if (stack.get_visible_child_name() == id) {
			stack.set_visible_child_name("main");
		}

		// If a page for this window exists, remove it
		var controls_layout = stack.get_child_by_name(id);

		if (controls_layout != null) {
			stack.remove(controls_layout);
			controls_layout.destroy();
		}
	}
}

private class WindowControls : Gtk.Box {
	public libxfce4windowing.Window window { get; construct; }

	private Gtk.CheckButton? keep_on_top_button;
	private Gtk.Button? maximize_button;
	private Gtk.Button? minimize_button;
	private Gtk.Button? return_button;

	public signal void return_clicked();

	public WindowControls(libxfce4windowing.Window window) {
		Object(window: window, orientation: Gtk.Orientation.VERTICAL, spacing: 0);
	}

	construct {
		keep_on_top_button = new Gtk.CheckButton.with_label(_("Always on top")) {
			relief = Gtk.ReliefStyle.NONE,
		};

		maximize_button = new Gtk.Button.with_label("") {
			relief = Gtk.ReliefStyle.NONE,
		};

		minimize_button = new Gtk.Button.with_label(_("Minimize")) {
			relief = Gtk.ReliefStyle.NONE,
		};

		var minimize_button_label = minimize_button.get_child() as Gtk.Label;
		minimize_button_label.halign = Gtk.Align.START;

		return_button = new Gtk.Button.from_icon_name("go-previous-symbolic", Gtk.IconSize.SMALL_TOOLBAR) {
			relief = Gtk.ReliefStyle.NONE,
		};

		var list_box = new Gtk.ListBox() {
			selection_mode = Gtk.SelectionMode.NONE,
		};

		list_box.add(keep_on_top_button);
		list_box.add(maximize_button);
		list_box.add(minimize_button);

		build_workspace_buttons(list_box);

		pack_start(list_box);
		pack_end(return_button, false, false, 0);

		keep_on_top_button.toggled.connect(() => {
			try {
				window.set_above(keep_on_top_button.active);
			} catch (Error e) {
				warning("Unable to set keep on top for window %s: %s", window.get_name(), e.message);
			}
		});

		maximize_button.clicked.connect(() => {
			var maximized = window.is_maximized();

			try {
				window.set_maximized(!maximized);
			} catch (Error e) {
				warning("Unable to set maximized on window %s: %s", window.get_name(), e.message);
			}
		});

		minimize_button.clicked.connect(() => {
			try {
				window.set_minimized(true);
			} catch (Error e) {
				warning("Unable to set minimized on window %s: %s", window.get_name(), e.message);
			}
		});

		return_button.clicked.connect(() => {
			return_clicked();
		});

		window.state_changed.connect((changed_mask, new_state) => {
			if (libxfce4windowing.WindowState.MAXIMIZED in changed_mask) {
				update_maximize_label();
			}
		});

		update_maximize_label();

		show_all();
	}

	private void build_workspace_buttons(Gtk.ListBox list_box) {
		unowned var current_workspace = window.get_workspace();

		if (current_workspace == null) return;

		unowned var workspace_group = current_workspace.get_workspace_group();

		if (workspace_group == null) return;

		foreach (var workspace in workspace_group.list_workspaces()) {
			// Translators: This is used for buttons to move applications to another Workspace
			var button = new Gtk.Button.with_label(_("Move to %s").printf(workspace.get_name())) {
				relief = Gtk.ReliefStyle.NONE,
			};
			var button_label = button.get_child() as Gtk.Label;
			button_label.halign = Gtk.Align.START;

			button.clicked.connect(() => {
				if (workspace == window.get_workspace()) {
					return;
				}

				try {
					window.move_to_workspace(workspace);
				} catch (Error e) {
					warning("Unable to move window '%s' to new workspace: %s", window.get_name(), e.message);
				}
			});

			list_box.add(button);
		}
	}

	private void update_maximize_label() {
		maximize_button.set_label(window.is_maximized() ? _("Unmaximize") : _("Maximize"));

		var maximize_button_label = maximize_button.get_child() as Gtk.Label;
		maximize_button_label.halign = Gtk.Align.START;
	}
}

private class WindowItem : Gtk.ListBoxRow {
	public libxfce4windowing.Window window { get; construct; }

	private Gtk.Label? name_label;
	private Gtk.Button? name_button;
	private Gtk.Button? close_button;
	private Gtk.Button? page_switch_button;

	public signal void page_switch_clicked();

	public WindowItem(libxfce4windowing.Window window) {
		Object(window: window);
	}

	construct {
		name_label = new Gtk.Label(window.get_name()) {
			ellipsize = Pango.EllipsizeMode.END,
			halign = Gtk.Align.START,
			justify = Gtk.Justification.LEFT,
			max_width_chars = 20,
			tooltip_text = window.get_name(),
		};

		name_button = new Gtk.Button() {
			relief = Gtk.ReliefStyle.NONE,
		};
		var button_inner = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);

		button_inner.pack_start(name_label);
		name_button.add(button_inner);

		close_button = new Gtk.Button.from_icon_name("window-close-symbolic", Gtk.IconSize.SMALL_TOOLBAR) {
			tooltip_text = _("Close window"),
			relief = Gtk.ReliefStyle.NONE,
		};

		page_switch_button = new Gtk.Button.from_icon_name("go-next-symbolic", Gtk.IconSize.SMALL_TOOLBAR) {
			tooltip_text = _("Show window controls"),
			relief = Gtk.ReliefStyle.NONE,
		};

		var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);

		box.pack_start(name_button);
		box.pack_end(close_button, false, false, 0);
		box.pack_end(page_switch_button, false, false, 0);

		add(box);

		name_button.clicked.connect(() => {
			try {
				window.activate(Gtk.get_current_event_time());
			} catch (Error e) {
				warning("Unable to activate window %s: %s", window.get_name(), e.message);
			}
		});

		close_button.clicked.connect(() => {
			try {
				window.close(Gtk.get_current_event_time());
			} catch (Error e) {
				warning("Unable to close window %s: %s", window.get_name(), e.message);
			}
		});

		page_switch_button.clicked.connect(() => {
			page_switch_clicked();
		});

		show_all();

		window.name_changed.connect(() => {
			name_label.label = window.get_name();
		});
	}
}
