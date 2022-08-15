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

public class BudgieMenuWindow : Budgie.Popover {
	protected Gtk.Box main_layout;
	protected Gtk.SearchEntry search_entry;
	protected ApplicationView view;

	private Gtk.Overlay overlay;
	private UserButton user_indicator;
	private Gtk.Button budgie_desktop_prefs_button;
	private Gtk.Button system_settings_button;
	private Gtk.Button power_button;
	private OverlayMenus overlay_menu;

	public BudgieMenuWindow(Settings? settings, Gtk.Widget? leparent) {
		Object(relative_to: leparent);
		this.get_style_context().add_class("budgie-menu");

		this.main_layout = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
		this.add(main_layout);

		// Header items at the top with search input
		var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
		header.get_style_context().add_class("budgie-menu-header");

		this.search_entry = new Gtk.SearchEntry();
		this.search_entry.grab_focus();
		header.pack_start(search_entry, true, true, 0);

		this.main_layout.pack_start(header, false, false, 0);

		// middle holds the categories and applications
		this.overlay = new Gtk.Overlay();
		var view_container = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);

		this.overlay_menu = new OverlayMenus();

		this.overlay.add(view_container);
		this.overlay.add_overlay(this.overlay_menu);

		this.view = new ApplicationListView(settings);

		view_container.pack_end(this.view, true, true, 0);
		this.main_layout.pack_start(this.overlay, true, true, 0);

		// Footer at the bottom for user and power stuff
		var footer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
		footer.get_style_context().add_class("budgie-menu-footer");

		this.user_indicator = new UserButton();
		user_indicator.valign = Gtk.Align.CENTER;
		user_indicator.halign = Gtk.Align.START;

		this.budgie_desktop_prefs_button = this.create_icon_button("preferences-desktop");
		this.budgie_desktop_prefs_button.set_tooltip_text(_("Budgie Desktop Settings"));

		this.system_settings_button = this.create_icon_button("preferences-system");
		this.system_settings_button.set_tooltip_text(_("System Settings"));

		this.power_button = this.create_icon_button("system-shutdown-symbolic");
		this.power_button.set_tooltip_text(_("Power"));

		footer.pack_start(this.user_indicator, false, false, 0);
		footer.pack_end(this.power_button, false, false, 0);
		footer.pack_end(this.system_settings_button, false, false, 0);
		footer.pack_end(this.budgie_desktop_prefs_button, false, false, 0);
		this.main_layout.pack_end(footer, false, false, 0);

		// Close the power menu on click if it is open
		this.button_press_event.connect((event) => {
			// Only care about left clicks
			if (event.button != 1) {
				return Gdk.EVENT_PROPAGATE;
			}

			// Don't do work if we don't need to
			if (!this.overlay_menu.get_reveal_child()) {
				return Gdk.EVENT_PROPAGATE;
			}

			this.reset(false);
			return Gdk.EVENT_STOP;
		});

		// searching functionality
		this.search_entry.changed.connect(()=> {
			var search_term = Budgie.RelevancyService.searchable_string(this.search_entry.text);
			this.view.search_changed(search_term);
		});

		this.system_settings_button.clicked.connect(() => {
			this.open_desktop_entry("budgie-control-center.desktop");
		});

		this.budgie_desktop_prefs_button.clicked.connect(() => {
			this.open_desktop_entry("org.buddiesofbudgie.BudgieDesktopSettings.desktop");
		});

		// Enabling activation by search entry
		this.search_entry.activate.connect(() => {
			// Make the view (and filter) is updated before calling activate
			var search_term = Budgie.RelevancyService.searchable_string(this.search_entry.text);
			this.view.search_changed(search_term);

			this.view.on_search_entry_activated();
		});

		this.user_indicator.clicked.connect(() => {
			if (this.overlay_menu.get_reveal_child()) {
				this.reset(false);
			} else {
				this.open_overlay_menu("xdg");
			}
		});

		// Open or close the session controls menu when
		// the user indicator is clicked
		this.power_button.clicked.connect(() => {
			if (this.overlay_menu.get_reveal_child()) {
				this.reset(false);
			} else {
				this.open_overlay_menu("power");
			}
		});

		// We should go away when a user menu button is clicked
		this.overlay_menu.item_clicked.connect(this.hide);

		// We should go away when an app is launched from the menu
		this.view.app_launched.connect(this.hide);
	}

	private Gtk.Button create_icon_button(string icon_name) {
		Gtk.Button btn = new Gtk.Button.from_icon_name(icon_name);
		btn.relief = Gtk.ReliefStyle.NONE;
		btn.valign = Gtk.Align.CENTER;
		btn.halign = Gtk.Align.END;
		return btn;
	}

	/*
	* open_desktop_entry will open the specified desktop entry
	*/
	public void open_desktop_entry(string name) {
		try {
			var info = new DesktopAppInfo(name);
			if (info != null) {
				info.launch(null, null);
			}
		} catch (Error e) {
			warning("Unable to launch %s: %s", name, e.message);
		}
	}

	/**
	 * Refresh the category and application views.
	 */
	public void refresh(Budgie.AppIndex app_index, bool now = false) {
		if (now) {
			this.view.refresh(app_index);
		} else {
			this.view.queue_refresh(app_index);
		}
	}

	/**
	 * Reset the popover UI to the base state.
	 *
	 * If `clear_search` is set to true, the search entry text will be cleared.
	 */
	public void reset(bool clear_search) {
		this.view.on_show();
		this.overlay_menu.set_reveal_child(false);
		this.search_entry.sensitive = true;
		this.search_entry.grab_focus();
		this.view.set_sensitive(true);

		if (clear_search) {
			this.search_entry.text = "";
		}
	}

	public override void show() {
		this.reset(true);
		base.show();
	}

	/**
	 * Opens our overlay menu and makes all other widgets insensitive.
	 */
	private void open_overlay_menu(string vis) {
		this.overlay_menu.set_visible_menu(vis);
		this.overlay_menu.set_reveal_child(true);
		this.search_entry.sensitive = false;
		this.view.set_sensitive(false);
	}
}
