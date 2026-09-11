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

/**
 * Factory widget to represent a menu item
 */
public class MenuButton : Gtk.Box {
	public Budgie.Application app { get; construct; }
	public Budgie.Category category { get; construct; }
	public int icon_size { get; construct; }
	public FavoritesManager favorites { get; construct; }

	/**
	 * Emitted when the application should be launched.
	 */
	public signal void clicked();

	/**
	 * Emitted when one of the application's desktop actions is launched.
	 */
	public signal void action_launched();

	/**
	 * Emitted when this item reveals its actions.
	 */
	public signal void expanded();

	private Gtk.Button launch_button;
	private Gtk.Revealer revealer;
	private Gtk.Label favorite_label;

	public MenuButton(Budgie.Application app, Budgie.Category category, int icon_size, FavoritesManager favorites) {
		Object(
			app: app,
			category: category,
			icon_size: icon_size,
			favorites: favorites,
			orientation: Gtk.Orientation.VERTICAL,
			spacing: 0
		);
	}

	construct {
		launch_button = new Gtk.Button() {
			can_focus = false,
			tooltip_text = app.description
		};
		launch_button.get_style_context().add_class("flat");

		var img = new Gtk.Image.from_gicon(app.icon, Gtk.IconSize.INVALID) {
			pixel_size = icon_size,
			margin_end = 7
		};

		var lab = new Gtk.Label(app.name) {
			valign = Gtk.Align.CENTER,
			xalign = 0.0f,
			max_width_chars = 1,
			ellipsize = Pango.EllipsizeMode.END,
			hexpand = true,
		};

		var layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
		layout.set_size_request(250, -1);
		layout.pack_start(img, false, false, 0);
		layout.pack_start(lab, true, true, 0);
		launch_button.add(layout);

		const Gtk.TargetEntry[] drag_targets = { {"text/uri-list", 0, 0 } };
		Gtk.drag_source_set(launch_button, Gdk.ModifierType.BUTTON1_MASK, drag_targets, Gdk.DragAction.COPY);
		launch_button.drag_begin.connect(this.on_drag_begin);
		launch_button.drag_end.connect(this.on_drag_end);
		launch_button.drag_data_get.connect(this.on_drag_data_get);
		launch_button.clicked.connect(this.on_launch_clicked);
		launch_button.button_press_event.connect(this.on_button_press);

		pack_start(launch_button, false, false, 0);
		pack_start(this.build_revealer(), false, false, 0);

		update_favorite_label();
	}

	private Gtk.Revealer build_revealer() {
		favorite_label = new Gtk.Label(null) {
			xalign = 0.0f
		};

		var favorite_button = new Gtk.Button() {
			relief = Gtk.ReliefStyle.NONE
		};
		favorite_button.add(favorite_label);
		favorite_button.clicked.connect(this.on_favorite_clicked);

		var favorite_list = new Gtk.ListBox() {
			selection_mode = Gtk.SelectionMode.NONE
		};
		favorite_list.add(favorite_button);

		var layout = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
		layout.get_style_context().add_class("menu-item-actions");
		layout.pack_start(favorite_list, false, false, 0);

		var actions = new Budgie.ApplicationActionList(app);
		if (!actions.is_empty()) {
			actions.action_launched.connect(this.on_action_launched);
			layout.pack_start(actions, false, false, 0);
		}

		revealer = new Gtk.Revealer() {
			transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN,
			reveal_child = false
		};
		revealer.add(layout);

		return revealer;
	}

	/**
	 * Check if this item is for a control center panel.
	 */
	public bool is_control_center_panel() {
		var control_center = "budgie-control-center";
		return (
			control_center in app.exec &&
			app.exec.length != control_center.length
		);
	}

	public bool get_revealed() {
		return revealer.reveal_child;
	}

	public void set_revealed(bool revealed) {
		revealer.reveal_child = revealed;

		if (revealed) {
			this.expanded();
		}
	}

	public void update_favorite_label() {
		favorite_label.label = favorites.is_favorite(app.desktop_id)
			? _("Remove from favorites")
			: _("Add to favorites");
	}

	private bool hide_menu() {
		unowned var menu = this.get_ancestor(typeof(BudgieMenuWindow)) as BudgieMenuWindow;
		if (menu != null) {
			menu.hide();
		}

		return false;
	}

	private void on_launch_clicked() {
		this.clicked();
	}

	private void on_favorite_clicked() {
		favorites.toggle(app.desktop_id);
	}

	private void on_action_launched() {
		this.action_launched();
	}

	private bool on_button_press(Gdk.EventButton event) {
		if (event.button != Gdk.BUTTON_SECONDARY) {
			return Gdk.EVENT_PROPAGATE;
		}

		set_revealed(!revealer.reveal_child);
		return Gdk.EVENT_STOP;
	}

	private void on_drag_begin(Gtk.Widget widget, Gdk.DragContext context) {
		Gtk.drag_set_icon_gicon(context, this.app.icon, 0, 0);
	}

	private void on_drag_end(Gtk.Widget widget, Gdk.DragContext context) {
		Idle.add(this.hide_menu);
	}

	private void on_drag_data_get(Gtk.Widget widget, Gdk.DragContext context, Gtk.SelectionData data, uint info, uint timestamp) {
		try {
			string[] urls = { Filename.to_uri(this.app.desktop_path) };
			data.set_uris(urls);
		} catch (Error e) {
			warning("Failed to set copy data: %s", e.message);
		}
	}
}
