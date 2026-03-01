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

public const Gtk.TargetEntry[] DRAG_TARGETS = {
	{ "application/x-desktop", 0, 0 },
	{ "text/uri-list", 0, 1 },
};

public const Gtk.TargetEntry[] SOURCE_TARGET = {
	{ "application/x-desktop", 0, 0 },
};

public class IconTasklist : Budgie.Plugin, Peas.ExtensionBase {
	public Budgie.Applet get_panel_widget(string uuid) {
		return new IconTasklistApplet(uuid);
	}
}

[GtkTemplate (ui="/com/solus-project/icon-tasklist/settings.ui")]
public class IconTasklistSettings : Gtk.Grid {
	[GtkChild]
	private unowned Gtk.Switch? switch_restrict;

	[GtkChild]
	private unowned Gtk.Switch? switch_lock_icons;

	[GtkChild]
	private unowned Gtk.Switch? switch_only_pinned;

	[GtkChild]
	private unowned Gtk.Switch? show_all_on_click;

	[GtkChild]
	private unowned Gtk.Switch? switch_middle_click_create_new_instance;

	[GtkChild]
	private unowned Gtk.Switch? switch_require_double_click_to_launch_new_instance;

	private Settings? settings;

	public IconTasklistSettings(Settings? settings) {
		this.settings = settings;
		settings.bind("restrict-to-workspace", switch_restrict, "active", SettingsBindFlags.DEFAULT);
		settings.bind("lock-icons", switch_lock_icons, "active", SettingsBindFlags.DEFAULT);
		settings.bind("only-pinned", switch_only_pinned, "active", SettingsBindFlags.DEFAULT);
		settings.bind("show-all-windows-on-click", show_all_on_click, "active", SettingsBindFlags.DEFAULT);
		settings.bind("middle-click-launch-new-instance", switch_middle_click_create_new_instance, "active", SettingsBindFlags.DEFAULT);
		settings.bind("require-double-click-to-launch", switch_require_double_click_to_launch_new_instance, "active", SettingsBindFlags.DEFAULT);
	}
}

public class IconTasklistApplet : Budgie.Applet {
	private Budgie.Windowing.Windowing windowing;
	private Settings settings;
	private Gtk.Box main_layout;

	private Budgie.ApplicationMatcher matcher;

	private bool lock_icons = false;
	private bool restrict_to_workspace = false;
	private bool only_show_pinned = false;

	private int icon_size = 0;
	private int panel_size = 0;

	private Budgie.PanelPosition panel_position = Budgie.PanelPosition.BOTTOM;

	/**
	 * Avoid inserting/removing/updating the hashmap directly and prefer using
	 * add_button and remove_button that provide thread safety.
	 */
	private HashTable<string, IconButton> buttons;

	/* Applet support */
	private unowned Budgie.PopoverManager? manager = null;

	public string uuid { public set; public get; }

	public override Gtk.Widget? get_settings_ui() {
		return new IconTasklistSettings(this.get_applet_settings(uuid));
	}

	public override bool supports_settings() {
		return true;
	}

	public IconTasklistApplet(string uuid) {
		Object(uuid: uuid);

		/* Get our settings working first */
		this.settings_schema = "com.solus-project.icon-tasklist";
		this.settings_prefix = "/com/solus-project/budgie-panel/instance/icon-tasklist";
		this.settings = this.get_applet_settings(uuid);

		/* Now hook up settings */
		this.settings.changed.connect(this.on_settings_changed);

		Idle.add(() => {
			this.rebuild_items();
			return false;
		});

		this.on_settings_changed("restrict-to-workspace");
		this.on_settings_changed("lock-icons");
		this.on_settings_changed("only-pinned");

		this.connect_app_signals();

		this.show_all();
	}

	construct {
		get_style_context().add_class("icon-tasklist");

		/* Somewhere to store the window mappings */
		buttons = new HashTable<string, IconButton>(str_hash, str_equal);
		main_layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);

		matcher = new Budgie.ApplicationMatcher();

		/* Initial bootstrap of helpers */
		windowing = new Budgie.Windowing.Windowing();

		add(main_layout);
	}

	/**
	 * Add IconButton for pinned apps
	 */
	private void startup() {
		var pinned = settings.get_strv("pinned-launchers");

		foreach (string launcher in pinned) {
			var info = new DesktopAppInfo(launcher);

			if (info == null) continue;

			var application = new Budgie.Application(info);
			var button = new IconButton(manager, application) {
				pinned = true,
			};

			button.button_press_event.connect(on_button_press);
			button.button_release_event.connect(on_button_release);
			button.notify["pinned"].connect(on_pinned_changed);

			add_icon_button(launcher, button);
		}
	}

	private void connect_app_signals() {
		windowing.active_window_changed.connect_after(on_active_window_changed);
		windowing.active_workspace_changed.connect_after(update_buttons);

		windowing.window_group_added.connect(on_app_opened);
		windowing.window_group_removed.connect(on_app_closed);
	}

	/**
	 * Remove every IconButton and add them back
	 */
	private void rebuild_items() {
		foreach (Gtk.Widget widget in this.main_layout.get_children()) {
			widget.destroy();
		}

		this.buttons.remove_all();

		this.startup();

		windowing.get_window_groups().foreach(this.on_app_opened); // for each running apps
	}

	private void on_settings_changed(string key) {
		switch (key) {
			case "lock-icons":
				lock_icons = this.settings.get_boolean(key);
				break;
			case "restrict-to-workspace":
				this.restrict_to_workspace = this.settings.get_boolean(key);
				break;
			case "only-pinned":
				this.only_show_pinned = this.settings.get_boolean(key);
				break;
		}

		this.update_buttons();
	}

	private void update_buttons() {
		this.buttons.foreach((id, button) => {
			this.update_button(button);
		});
	}

	/**
	 * Handles the drag_data_get signal for an icon button.
	 *
	 * This sets the button's application's desktop-id as the drag data.
	 */
	private void button_drag_data_get(Gtk.Widget widget, Gdk.DragContext context, Gtk.SelectionData data, uint info, uint time) {
		var button = widget as IconButton;
		var id = button.app.desktop_id;

		data.set(data.get_target(), 8, id.data);
	}

	/**
	 * Handles the drag_begin signal for an icon button.
	 *
	 * This sets the icon at the cursor when the button is dragged.
	 */
	private void button_drag_begin(Gtk.Widget widget, Gdk.DragContext context) {
		var button = widget as IconButton;
		int size = 0;

		if (!Gtk.icon_size_lookup(Gtk.IconSize.DND, out size, null)) {
			size = 32;
		}

		var icon_theme = Gtk.IconTheme.get_default();
		var icon_info = icon_theme.lookup_icon(button.app.icon.to_string(), size, Gtk.IconLookupFlags.USE_BUILTIN);

		// Check if icon_info is null (e.g., broken symlink or missing icon)
		if (icon_info == null) {
			warning("Unable to find icon: %s", button.app.icon.to_string());
			return;
		}

		Gdk.Pixbuf? pixbuf;

		try {
			pixbuf = icon_info.load_icon();
		} catch (Error e) {
			warning("Unable to get Pixbuf from Icon");
			return;
		}

		if (pixbuf == null) return;

		var surface = Gdk.cairo_surface_create_from_pixbuf(pixbuf, 1, null);

		Gtk.drag_set_icon_surface(context, surface);
	}

	/**
	 * Handles when a drag item is dropped on a icon button.
	 *
	 * If the source widget is another icon button, reorder the widgets in
	 * our container so that the dropped button is put in the place of this
	 * button.
	 */
	private void button_drag_data_received(Gtk.Widget widget, Gdk.DragContext context, int x, int y, Gtk.SelectionData data, uint info, uint time) {
		var source = Gtk.drag_get_source_widget(context);

		switch (info) {
			case 0: // Drag contains a desktop file info
				button_drag_data_received_handle_desktop_info(widget, context, data, source);
				break;
			case 1: // Drag contains a URI
				button_drag_data_received_handle_uri(context, data, time);
				break;
			default: // Unknown
				warning("Unknown data passed during drag and drop");
				Gtk.drag_finish(context, false, false, Gtk.get_current_event_time());
				break;
		}
	}

	private void button_drag_data_received_handle_desktop_info(Gtk.Widget widget, Gdk.DragContext context, Gtk.SelectionData data, Gtk.Widget source) {
		var button = widget as IconButton;

		List<weak Gtk.Widget> children = main_layout.get_children(); // Get the list of child buttons
		unowned var self = children.find_custom(button.get_parent(), (a, b) => {
			var wrapper_a = a as ButtonWrapper;
			var wrapper_b = b as ButtonWrapper;

			return strcmp(wrapper_a.button.app.desktop_id, wrapper_b.button.app.desktop_id);
		});

		if (self == null) {
			warning("Unable to find the correct wrapper");
			Gtk.drag_finish(context, false, false, Gtk.get_current_event_time());
			return;
		}

		var position = children.position(self); // Get our position

		main_layout.reorder_child(source.get_parent(), position); // Put the source button in our position
		update_pinned_launchers(); // Update our pin order
		Gtk.drag_finish(context, true, context.get_selected_action() == Gdk.DragAction.MOVE, Gtk.get_current_event_time());
	}

	private void button_drag_data_received_handle_uri(Gdk.DragContext context, Gtk.SelectionData data, uint time) {
		// id of app that is currently being dragged
		var app_id = (string) data.get_data();

		if (!app_id.has_prefix("file://")) {
			Gtk.drag_finish(context, false, false, time);
			return;
		}

		var parts = app_id.split("://");
		if (parts.length < 2) {
			warning("Malformed URI: %s", app_id);
			Gtk.drag_finish(context, false, false, time);
			return;
		}

		app_id = parts[1];
		app_id = app_id.strip();

		DesktopAppInfo? info = new DesktopAppInfo.from_filename(app_id);

		if (info == null) {
			Gtk.drag_finish(context, false, false, time);
			return;
		}

		// Don't allow d&d for Budgie Desktop Settings
		if (info.get_startup_wm_class() == "budgie-desktop-settings") {
			Gtk.drag_finish(context, false, false, time);
			return;
		}

		string launcher = info.get_id();

		if (buttons.contains(launcher)) {
			Gtk.drag_finish(context, true, context.get_selected_action() == Gdk.DragAction.MOVE, time);
			return;
		}

		var application = new Budgie.Application(info);
		var button = new IconButton(manager, application) {
			pinned = true,
		};

		button.button_press_event.connect(on_button_press);
		button.button_release_event.connect(on_button_release);
		button.notify["pinned"].connect(on_pinned_changed);

		add_icon_button(launcher, button);
		update_pinned_launchers(); // Update our pin order
		Gtk.drag_finish(context, true, context.get_selected_action() == Gdk.DragAction.MOVE, time);
	}

	/**
	 * Handles when the cursor leaves the space of a button during a drag.
	 */
	private void button_drag_leave(Gtk.Widget widget, Gdk.DragContext context, uint time) {
		Gtk.drag_unhighlight(widget);
	}

	/**
	 * Handles when a widget is dragged over a tasklist button.
	 */
	private bool button_drag_motion(Gtk.Widget widget, Gdk.DragContext context, int x, int y, uint time) {
		// Get the first matching drop target
		var ret = Gtk.drag_dest_find_target(widget, context, null);

		// Check if the drop target is acceptable
		if (ret == Gdk.Atom.NONE) {
			Gdk.drag_status(context, 0, time); // Show that the drop will not be accepted
			return false; // Send drag-motion to other widgets
		}

		Gtk.drag_highlight(widget); // Highlight this button
		Gdk.drag_status(context, Gdk.DragAction.MOVE, time); // Show that the drop will be accepted
		return true;
	}

	private bool button_drag_drop(Gtk.Widget widget, Gdk.DragContext context, int x, int y, uint time) {
		var ret = Gtk.drag_dest_find_target(widget, context, null);

		Gtk.drag_get_data(widget, context, ret, time);
		return true;
	}

	/**
	 * Get the application ID for a window group
	 *
	 * This method first tries to get the app_id from group.app_info (standard case).
	 * If that fails or doesn't match any existing buttons, it uses ApplicationMatcher
	 * to handle non-standard apps like Tilix, jEdit, and snap applications.
	 *
	 * @param group The window group to get an ID for
	 * @param application Output parameter set to the Application object if found
	 * @return The application desktop ID (e.g., "firefox.desktop")
	 */
	private string get_app_id_by_group(Budgie.Windowing.WindowGroup group, ref Budgie.Application? application) {
		// Standard case: group has app_info
		if (group.app_info != null) {
			application = new Budgie.Application(group.app_info);

			if (application.desktop_id in buttons) {
				return application.desktop_id;
			}
		}

		// Fallback: match for non-standard apps
		// This handles apps like Tilix (com.gexperts.Tilix.desktop → tilix WM_CLASS),
		// jEdit (jedit.desktop → org-gjt-sp-jedit-jEdit WM_CLASS),
		// and snap apps (snap-store_ubuntu-software.desktop → snap-store WM_CLASS)
		var match_result = matcher.match_window_group(group);

		if (match_result.matched()) {
			debug(@"ApplicationMatcher: Matched $(match_result.desktop_id) via $(match_result.match_method)");

			// Create Application from matched desktop ID
			application = matcher.create_application(match_result.desktop_id);

			if (application != null) {
				return match_result.desktop_id;
			}
		}

		// ultimate fallback - use the group_id as-is
		return group.group_id.to_string();
	}

	/**
	 * on_app_opened handles when we open a new app
	 */
	private void on_app_opened(Budgie.Windowing.WindowGroup group) {
		Budgie.Application? application = null;
		string app_id = get_app_id_by_group(group, ref application);

		// Trigger an animation when a new instance of a window is launched while another is already open
		if (app_id in buttons) {
			var first_button = buttons[app_id];

			if (!first_button.get_icon().waiting && first_button.get_icon().get_realized()) {
				first_button.get_icon().waiting = true;
				first_button.get_icon().animate_wait();
			}
		}

		IconButton? button = null;
		if (app_id in buttons) { // try to get existing button if any
			button = buttons[app_id];

			if (button != null) {
				add_button(app_id, button); // map app to it's button so that we can update it later on
			}
		}

		if (button == null) { // create a new button
			button = new IconButton.with_group(group, manager, application);

			// IMPORTANT: Set pinned BEFORE connecting signals to avoid spurious notify events
			button.pinned = false;

			button.button_press_event.connect(on_button_press);
			button.button_release_event.connect(on_button_release);
			button.notify["pinned"].connect(on_pinned_changed);

			add_icon_button(app_id, button);
		}

		if (button.get_window_group() == null) { // button was pinned without app opened, set window group in button to properly group windows
			button.set_window_group(group);
		}

		update_button(button);
	}

	/**
	 * on_app_closed handles when an app closes.
	 *
	 * find the correct button via:
	 * 1. Try get_app_id_by_group() (includes matcher fallback)
	 * 2. Search all buttons by window group reference
	 */
	private void on_app_closed(Budgie.Windowing.WindowGroup group) {
		Budgie.Application? application = null;
		var app_id = get_app_id_by_group(group, ref application);

		IconButton? button = buttons.get(app_id);

		// If not found by app_id, search by window group reference
		// This is critical for matched apps where the button was created
		// with a different ID than what get_app_id_by_group returns
		if (button == null) {
			debug(@"Button not found by app_id '$app_id', searching by window group...");

			buttons.foreach((key, btn) => {
				if (btn.get_window_group() == group) {
					button = btn;
					app_id = key; // Update app_id to the actual key the button is stored under
					debug(@"Found button by window group: key='$key'");
				}
			});
		}

		if (button == null) { // we don't manage this button
			warning(@"an application ($(group.group_id)) was closed, but we couldn't find its button");
			return;
		}

		if (!button.pinned) { // Remove the button if it isn't a pinned launcher
			if (button.get_parent() is ButtonWrapper) {
				((ButtonWrapper) button.get_parent()).gracefully_die();
			}

			remove_button(app_id);
			return;
		}

		// Update the launcher button
		button.update();
	}

	private void on_active_window_changed(Xfw.Window? old_active_window, Xfw.Window? new_active_window) {
		foreach (IconButton button in buttons.get_values()) {
			if (new_active_window != null && button.has_window(new_active_window)) {
				button.set_active_window(true);
			} else {
				button.set_active_window(false);
			}

			button.update();
		}
	}

	private bool on_button_press(Gtk.Widget widget, Gdk.EventButton event) {
		if (event.button != Gdk.BUTTON_PRIMARY) return Gdk.EVENT_PROPAGATE;
		if (!settings.get_boolean("require-double-click-to-launch")) return Gdk.EVENT_PROPAGATE;
		if (event.type != Gdk.EventType.DOUBLE_BUTTON_PRESS) return Gdk.EVENT_PROPAGATE;

		var button = widget as IconButton;

		if (button.get_window_group() != null && button.get_window_group().has_windows()) return Gdk.EVENT_PROPAGATE;

		if (!button.launch()) {
			warning("Failed to launch application: %s", button.app.name);
		}

		return Gdk.EVENT_STOP;
	}

	private bool on_button_release(Gtk.Widget widget, Gdk.EventButton event) {
		var button = widget as IconButton;

		switch (event.button) {
			case Gdk.BUTTON_PRIMARY:
				var has_open_windows = button.get_window_group() != null && button.get_window_group().has_windows();

				// Check for open windows, and handle showing all windows on click
				if (has_open_windows && settings.get_boolean("show-all-windows-on-click")) {
					var group = button.get_window_group();
					var windows = group.get_windows();

					if (button.has_active_window) {
						// remember active_window, because it should be the last one to minimize
						var active_window = group.get_active_window();

						// Hide any un-minimized windows in this group
						foreach (var window in windows) {
							if (window != active_window && !window.is_minimized()) {
								try {
									window.set_minimized(true);
								} catch (Error e) {
									warning("Unable to minimize window '%s': %s", window.get_name(), e.message);
								}
							}
						}

						// the active window gets minimized last
						try {
							active_window.set_minimized(true);
						} catch (Error e) {
							warning("Unable to minimize active window '%s': %s", active_window.get_name(), e.message);
						}
					}
					else {
						var last_active_window = group.get_active_window();

						foreach (var window in windows) {
							try {
								if (window.is_minimized()) window.set_minimized(false);
								if (window != last_active_window) window.activate(null, event.time);
							} catch (Error e) {
								warning("Unable to minimize window '%s': %s", window.get_name(), e.message);
							}
						}
						if (last_active_window != null) {
							try {
								last_active_window.activate(null, event.time);
							} catch (Error e) {
								warning("Unable to activate last window '%s': %s", last_active_window.get_name(), e.message);
							}
						}
					}
				} else if (has_open_windows) { // Has open windows, toggle the visibility of the current/last active window
					var group = button.get_window_group();

					// If this button has the currently active window, minimize it
					if (button.has_active_window) {
						var window = group.get_active_window();

						try {
							window.set_minimized(!window.is_minimized());
						} catch (Error e) {
							warning("Unable to set minimized state of window %s: %s", window.get_name(), e.message);
						}
					} else { // The button does not have the currently active window, so try to activate it's last active window
						var window = group.get_last_active_window();

						try {
							window.activate(null, event.time);
						} catch (Error e) {
							warning("Unable to activate window %s: %s", window.get_name(), e.message);
						}
					}
				} else { // No open windows, launch the application if we don't require double-click
					if (settings.get_boolean("require-double-click-to-launch")) break;

					if (!button.launch()) {
						warning("Failed to launch application: %s", button.app.name);
					}
				}
				break;
			case Gdk.BUTTON_SECONDARY:
				manager.show_popover(button);
				return Gdk.EVENT_STOP;
			case Gdk.BUTTON_MIDDLE:
				if (!settings.get_boolean("middle-click-launch-new-instance")) break;

				if (!button.launch()) {
					warning("Failed to launch application: %s", button.app.name);
				}

				break;
		}

		return Gdk.EVENT_PROPAGATE;
	}

	/**
	 * Our panel has moved somewhere, stash the positions
	 */
	public override void panel_position_changed(Budgie.PanelPosition position) {
		panel_position = position;

		foreach (IconButton button in buttons.get_values()) {
			button.set_panel_position(position);
			button.set_orientation(get_orientation());
		}

		main_layout.set_orientation(get_orientation());
		resize();
	}

	/**
	 * Our panel has changed size, record the new icon sizes
	 */
	public override void panel_size_changed(int panel, int icon, int small_icon) {
		icon_size = small_icon;
		panel_size = panel;

		resize();
	}

	private void resize() {
		this.buttons.foreach((id, button) => {
			button.set_icon_size(icon_size);
			button.set_panel_size(panel_size);
			button.queue_resize();
		});

		queue_resize();
	}

	public override void update_popovers(Budgie.PopoverManager? manager) {
		this.manager = manager;
	}

	/**
	 * Return our orientation in relation to the panel position
	 */
	private Gtk.Orientation get_orientation() {
		switch (panel_position) {
			case Budgie.PanelPosition.TOP:
			case Budgie.PanelPosition.BOTTOM:
				return Gtk.Orientation.HORIZONTAL;
			default:
				return Gtk.Orientation.VERTICAL;
		}
	}

	private void add_icon_button(string app_id, IconButton button) {
		add_button(app_id, button); // map app to it's button so that we can update it later on

		ButtonWrapper wrapper = new ButtonWrapper(button);
		wrapper.orient = get_orientation();

		Gtk.drag_dest_set(button, 0, DRAG_TARGETS, Gdk.DragAction.MOVE);

		button.drag_data_get.connect(button_drag_data_get);
		button.drag_begin.connect(button_drag_begin);
		button.drag_data_received.connect(button_drag_data_received);
		button.drag_motion.connect(button_drag_motion);
		button.drag_drop.connect(button_drag_drop);
		button.drag_leave.connect(button_drag_leave);

		this.main_layout.add(wrapper);
		this.update_button(button);
	}

	private void on_pinned_changed(Object object, ParamSpec pspec) {
		var button = object as IconButton;

		// If the button has been unpinned, remove it from the panel if
		// there are no open windows
		if (!button.pinned) {
			var group = button.get_window_group();

			if (group == null) {
				var id = button.app.desktop_id;

				((ButtonWrapper) button.get_parent()).gracefully_die();
				remove_button(id);
			}
		}

		update_pinned_launchers();
	}

	private void update_pinned_launchers() {
		var pinned = new string[]{};

		foreach (var child in main_layout.get_children()) {
			IconButton child_button = ((ButtonWrapper) child).button;

			if (child_button.pinned) {
				pinned += child_button.app.desktop_id;
			}
		}

		settings.set_strv("pinned-launchers", pinned);
	}

	private void update_button(IconButton button) {
		bool visible = true;

		if (restrict_to_workspace) { // Only show apps on this workspace
			var workspace = windowing.get_active_workspace();

			if (workspace != null) {
				var group = button.get_window_group();

				if (group != null) {
					visible = group.has_window_on_workspace(workspace);
				}
			}
		}

		if (only_show_pinned) {
			visible = button.pinned;
		}

		if (lock_icons) {
			Gtk.drag_source_unset(button);
		} else {
			Gtk.drag_source_set(button, Gdk.ModifierType.BUTTON1_MASK, SOURCE_TARGET, Gdk.DragAction.MOVE);
		}

		visible = visible || button.pinned;

		((ButtonWrapper) button.get_parent()).orient = get_orientation();
		((Gtk.Revealer) button.get_parent()).set_reveal_child(visible);

		button.set_panel_size(panel_size);
		button.set_panel_position(panel_position);
		button.set_orientation(get_orientation());
		button.update();
	}

	/**
	 * Ensure that we don't access the resource simultaneously when adding new buttons.
	 */
	private void add_button(string key, IconButton button) {
		lock(this.buttons) {
			this.buttons[key] = button;
		}
	}

	/**
	 * Ensure that we don't access the resource simultaneously when removing a button.
	 */
	private void remove_button(string key) {
		lock(this.buttons) {
			this.buttons.remove(key);
		}
	}

	/**
	 * Ensure that we don't access the resource simultaneously when swapping a button's key.
	 */
	private void swap_button(string old_key, string new_key) {
		lock(this.buttons) {
			this.buttons.insert(new_key, this.buttons.take(old_key));
		}
	}
}

[ModuleInit]
public void peas_register_types(TypeModule module) {
	// boilerplate - all modules need this
	var objmodule = module as Peas.ObjectModule;
	objmodule.register_extension_type(typeof(Budgie.Plugin), typeof(IconTasklist));
}
