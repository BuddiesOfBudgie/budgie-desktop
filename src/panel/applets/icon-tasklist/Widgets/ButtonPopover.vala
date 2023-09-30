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

public class ButtonPopover : Budgie.Popover {
	public Budgie.Application app { get; construct; }
	public Budgie.Windowing.WindowGroup? group { get; construct; }

	private Gtk.Stack? stack;
	private Gtk.ListBox? desktop_actions;
	private Gtk.ListBox? windows;
	private Gtk.Button? pin_button;
	private Gtk.Button? new_instance_button;
	private Gtk.Button? close_all_button;

	public ButtonPopover(IconButton button, Budgie.Application app, Budgie.Windowing.WindowGroup? group) {
		Object(relative_to: button, app: app, group: group);
	}

	construct {
		width_request = 200;

		get_style_context().add_class("icon-popover");

		desktop_actions = new Gtk.ListBox();

		foreach (var action in app.actions) {
			var action_button = new Gtk.Button.with_label(action);

			action_button.clicked.connect(() => {
				app.launch_action(action);
				hide();
			});

			desktop_actions.add(action_button);
		}

		windows = new Gtk.ListBox();

		if (group != null) {
			foreach (var window in group.get_windows()) {
				add_window(window);
			}
		}

		pin_button = new Gtk.Button.from_icon_name("emblem-favorite-symbolic", Gtk.IconSize.SMALL_TOOLBAR) {
			tooltip_text = _("Favorite"),
		};

		new_instance_button = new Gtk.Button.from_icon_name("window-new-symbolic", Gtk.IconSize.SMALL_TOOLBAR) {
			tooltip_text = _("Launch new instance"),
		};

		close_all_button = new Gtk.Button.from_icon_name("list-remove-all-symbolic", Gtk.IconSize.SMALL_TOOLBAR) {
			tooltip_text = _("Close all windows")
		};

		var button_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
		button_box.pack_start(pin_button);
		button_box.pack_start(new_instance_button);
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

		show_all();
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

			stack.add_named(controls_layout, window.get_id().to_string());
			stack.set_visible_child_name(window.get_id().to_string());
		});

		windows.add(window_item);
	}

	public void remove_window(libxfce4windowing.Window window) {
		WindowItem? window_item = null;

		// Get the window item for this window, if exists
		foreach (var child in windows.get_children()) {
			if (((WindowItem) child).window.get_id() == window.get_id()) {
				window_item = child as WindowItem;
				break;
			}
		}

		if (window_item == null) return;

		window_item.destroy();

		// Set the stack page to the main layout if we happen to have this window's page open
		if (stack.get_visible_child_name() == window.get_id().to_string()) {
			stack.set_visible_child_name("main");
		}

		// If a page for this window exists, remove it
		var controls_layout = stack.get_child_by_name(window.get_id().to_string());

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
		Object(window: window);
	}

	construct {
		keep_on_top_button = new Gtk.CheckButton.with_label(_("Always on top"));

		maximize_button = new Gtk.Button.with_label(_("Unmaximize"));

		minimize_button = new Gtk.Button.with_label(_("Minimize"));

		return_button = new Gtk.Button.from_icon_name("go-previous-symbolic", Gtk.IconSize.SMALL_TOOLBAR);

		var list_box = new Gtk.ListBox();

		list_box.add(keep_on_top_button);
		list_box.add(maximize_button);
		list_box.add(minimize_button);

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

		window.workspace_changed.connect(() => {
			// TODO: Not implemented yet
		});

		show_all();
	}

	private void update_maximize_label() {
		if (window.is_maximized()) {
			maximize_button.set_label(_("Unmaximize"));
		} else {
			maximize_button.set_label(_("Maximize"));
		}
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

		name_button = new Gtk.Button();
		var button_inner = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);

		button_inner.pack_start(name_label);
		name_button.add(button_inner);

		close_button = new Gtk.Button.from_icon_name("window-close-symbolic", Gtk.IconSize.SMALL_TOOLBAR) {
			tooltip_text = _("Close window"),
		};

		page_switch_button = new Gtk.Button.from_icon_name("go-next-symbolic", Gtk.IconSize.SMALL_TOOLBAR) {
			tooltip_text = _("Show window controls")
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
