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
	{ "application/x-icon-tasklist-launcher-id", 0, 0 },
	{ "text/uri-list", 0, 0 },
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
		// TODO: this.on_active_window_changed();

		this.show_all();
	}

	construct {
		get_style_context().add_class("icon-tasklist");

		/* Somewhere to store the window mappings */
		buttons = new HashTable<string, IconButton>(str_hash, str_equal);
		main_layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);

		/* Initial bootstrap of helpers */
		windowing = new Budgie.Windowing.Windowing();

		Gtk.drag_dest_set(main_layout, Gtk.DestDefaults.ALL, DRAG_TARGETS, Gdk.DragAction.COPY);
		main_layout.drag_data_received.connect(on_drag_data_received);

		add(main_layout);
	}

	/**
	 * Add IconButton for pinned apps
	 */
	private void startup() {
		string[] pinned = this.settings.get_strv("pinned-launchers");

		foreach (string launcher in pinned) {
			var info = new DesktopAppInfo(launcher);

			if (info == null) continue;

			var application = new Budgie.Application(info);
			var button = new IconButton(application, manager);

			add_icon_button(launcher, button);
		}
	}

	private void connect_app_signals() {
		windowing.active_window_changed.connect_after(on_active_window_changed);
		windowing.active_workspace_changed.connect_after(update_buttons);

		windowing.window_group_added.connect((group) => {});
		windowing.window_group_removed.connect((group) => {});

		// TODO: Figure out if any of this is really needed
		//  this.abomination.updated_group.connect((group) => { // try to properly group icons
		//  	Wnck.Window window = group.get_windows().nth_data(0);
		//  	if (window == null) {
		//  		return;
		//  	}

		//  	Budgie.Abomination.RunningApp app = this.abomination.get_app_from_window_id(window.get_xid());
		//  	if (app == null) {
		//  		return;
		//  	}

		//  	IconButton button = this.buttons.get(window.get_xid().to_string());

		//  	if (button == null && app.app_info != null) { // Button might be pinned, try to get button from launcher instead
		//  		string launcher = this.desktop_helper.get_app_launcher(app.app_info.get_filename());
		//  		button = this.buttons.get(launcher);
		//  	}

		//  	if (button == null) { // we don't manage this button
		//  		return;
		//  	}

		//  	ButtonWrapper wrapper = (button.get_parent() as ButtonWrapper);
		//  	if (wrapper == null) {
		//  		return;
		//  	}

		//  	if (!button.pinned) {
		//  		wrapper.gracefully_die();
		//  	} else {
		//  		// the button that we were going to replace is pinned, so instead of removing it from the view,
		//  		// just remove its class group and first app, then update it visually. this prevents apps like
		//  		// the LibreOffice launcher from vanishing after a document is opened, despite being pinned
		//  		button.set_class_group(null);
		//  		button.first_app = null;
		//  		button.update();
		//  	}

		//  	this.remove_button(window.get_xid().to_string());
		//  	this.on_app_opened(app);
		//  });
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

	private void on_drag_data_received(Gtk.Widget widget, Gdk.DragContext context, int x, int y, Gtk.SelectionData selection_data, uint item, uint time) {
		if (item != 0) {
			message("Invalid target type");
			return;
		}

		// id of app that is currently being dragged
		var app_id = (string) selection_data.get_data();
		ButtonWrapper? original_button = null;

		if (app_id.has_prefix("file://")) {
			app_id = app_id.split("://")[1];
			app_id = app_id.strip();

			DesktopAppInfo? info = new DesktopAppInfo.from_filename(app_id);
			if (info == null) return;

			// Don't allow d&d for Budgie Desktop Settings
			if (info.get_startup_wm_class() == "budgie-desktop-settings") return;

			string launcher = info.get_id();

			if (this.buttons.contains(launcher)) {
				original_button = (this.buttons[launcher].get_parent() as ButtonWrapper);
			} else {
				var application = new Budgie.Application(info);
				var button = new IconButton(application, manager);

				add_icon_button(launcher, button);

				original_button = button.get_parent() as ButtonWrapper;

				// Set the new launcher as pinned
				var launchers = settings.get_strv("pinned-launchers");
				launchers += app_id;
				settings.set_strv("pinned-launchers", launchers);
			}
		} else { // Doesn't start with file://
			unowned IconButton? button = null;
			string app_id_without_desktop_suffix = app_id.replace(".desktop", "");

			if (this.buttons.contains(app_id)) { // If buttons contains this ID for this application (can be a desktop file name or xid)
				button = this.buttons.get(app_id);
			} else {
				button = this.buttons.get(app_id_without_desktop_suffix);
			}

			if (button != null) {
				original_button = button.get_parent() as ButtonWrapper;
			}
		}

		if (original_button == null) {
			return;
		}

		// Iterate through launchers
		foreach (Gtk.Widget widget1 in this.main_layout.get_children()) {
			ButtonWrapper current_button = (widget1 as ButtonWrapper);

			Gtk.Allocation alloc;

			current_button.get_allocation(out alloc);

			if ((this.get_orientation() == Gtk.Orientation.HORIZONTAL && x <= (alloc.x + (alloc.width / 2))) ||
				(this.get_orientation() == Gtk.Orientation.VERTICAL && y <= (alloc.y + (alloc.height / 2)))) {
				int new_position, old_position;
				this.main_layout.child_get(original_button, "position", out old_position, null);
				this.main_layout.child_get(current_button, "position", out new_position, null);

				if (new_position == old_position) {
					break;
				}

				if (new_position == old_position + 1) {
					break;
				}

				if (new_position > old_position) {
					new_position = new_position - 1;
				}

				this.main_layout.reorder_child(original_button, new_position);
				break;
			}

			if ((this.get_orientation() == Gtk.Orientation.HORIZONTAL && x <= (alloc.x + alloc.width)) ||
				(this.get_orientation() == Gtk.Orientation.VERTICAL && y <= (alloc.y + alloc.height))) {
				int new_position, old_position;
				this.main_layout.child_get(original_button, "position", out old_position, null);
				this.main_layout.child_get(current_button, "position", out new_position, null);

				if (new_position == old_position) {
					break;
				}

				if (new_position == old_position - 1) {
					break;
				}

				if (new_position < old_position) {
					new_position = new_position + 1;
				}

				this.main_layout.reorder_child(original_button, new_position);
				break;
			}
		}
		original_button.set_transition_type(Gtk.RevealerTransitionType.NONE);
		original_button.set_reveal_child(true);

		Gtk.drag_finish(context, true, true, time);
	}

	/**
	 * on_app_opened handles when we open a new app
	 */
	private void on_app_opened(Budgie.Windowing.WindowGroup group) {
		string application_id = group.application.get_id().to_string();
		var app_info = new DesktopAppInfo(group.get_desktop_id());

		if (app_info == null) return;
		var application = new Budgie.Application(app_info);

		if (buttons.contains(application_id)) {
			application_id = application.desktop_id;
		}

		// Trigger an animation when a new instance of a window is launched while another is already open
		if (buttons.contains(application_id)) {
			IconButton first_button = buttons.get(application_id);
			if (!first_button.get_icon().waiting && first_button.get_icon().get_realized()) {
				first_button.get_icon().waiting = true;
				first_button.get_icon().animate_wait();
			}
		}

		IconButton? button = null;
		if (buttons.contains(application_id)) { // try to get existing button if any
			button = buttons.get(application_id);

			if (button != null) {
				this.add_button(application_id, button); // map app to it's button so that we can update it later on
			}
		}

		if (button == null) { // create a new button
			button = new IconButton.with_group(application, group, manager);
			add_icon_button(application_id, button);
		}

		if (button.get_window_group() == null) { // button was pinned without app opened, set window group in button to properly group windows
			button.set_window_group(group);
		}

		update_button(button);
	}

	private void on_app_closed(Budgie.Windowing.WindowGroup group) {
		var app_id = group.application.get_id().to_string();
		IconButton? button = buttons.get(app_id);

		if (button == null) { // Button might be pinned, try to get button from launcher instead
			app_id = group.get_desktop_id();
			button = buttons.get(app_id);
		}

		if (button == null) { // we don't manage this button
			return;
		}

		if (!button.pinned) { // Remove the button if it isn't a pinned launcher
			remove_button(app_id);
			return;
		}

		// Update the launcher button
		button.update();

		//  if (button.button_id != app_id && app_id in buttons) {
		//  	this.swap_button(app_id, button.button_id);
		//  	button.first_app = null;
		//  	button.set_app_for_class_group();
		//  } else {
		//  	this.remove_button(app_id);
		//  }
	}

	private void on_active_window_changed(libxfce4windowing.Window? old_active_window, libxfce4windowing.Window? new_active_window) {
		foreach (IconButton button in buttons.get_values()) {
			if (button.has_window(new_active_window)) {
				button.set_active_window(true);
				// TODO: button.attention(false);
			} else {
				button.set_active_window(false);
			}

			button.update();
		}
	}

	/**
	 * Our panel has moved somewhere, stash the positions
	 */
	public override void panel_position_changed(Budgie.PanelPosition position) {
		panel_position = position;

		foreach (IconButton button in buttons.get_values()) {
			button.set_panel_position(position);
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
		// Wnck.set_default_icon_size(this.desktop_helper.panel_size);

		this.buttons.foreach((id, button) => {
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
		this.add_button(app_id, button); // map app to it's button so that we can update it later on

		ButtonWrapper wrapper = new ButtonWrapper(button);
		wrapper.orient = this.get_orientation();

		// TODO: Kill button when there are no window left and its not pinned
		//  button.became_empty.connect(() => {
		//  	if (!button.pinned) {
		//  		if (wrapper != null) {
		//  			wrapper.gracefully_die();
		//  		}

		//  		this.remove_button(app_id);
		//  	}
		//  });

		// TODO: when button become pinned, make sure we identify it by its launcher instead of xid or grouping will fail
		//  button.pinned_changed.connect(() => {
		//  	if (button.first_window == null) return;

		//  	if (button.pinned) {
		//  		add_button(launcher, button);
		//  		remove_button(button.application.desktop_id);
		//  	} else {
		//  		add_button(button.application.desktop_id, button);
		//  		remove_button(launcher);
		//  	}
		//  });

		this.main_layout.add(wrapper);
		this.show_all();
		this.update_button(button);
	}

	private void update_button(IconButton button) {
		bool visible = true;

		if (restrict_to_workspace) { // Only show apps on this workspace
			var workspace = windowing.get_active_workspace();

			if (workspace == null) return;

			// TODO: visible = button.has_window_on_workspace(workspace); // Set if the button is pinned and on workspace
		}

		if (only_show_pinned) {
			visible = button.pinned;
		}

		visible = visible || button.pinned;

		((ButtonWrapper) button.get_parent()).orient = get_orientation();
		((Gtk.Revealer) button.get_parent()).set_reveal_child(visible);
		button.update();
	}

	/**
	 * Ensure that we don't access the resource simultaneously when adding new buttons.
	 */
	private void add_button(string key, IconButton button) {
		lock(this.buttons) {
			this.buttons.insert(key, button);
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
