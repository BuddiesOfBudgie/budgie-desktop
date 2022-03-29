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

const string APPS_ID = "gnome-applications.menu";
const string LOGOUT_BINARY = "budgie-session-dialog";

/**
 * Return a string suitable for working on.
 * This works around the issue of GNOME Control Center and others deciding to
 * use soft hyphens in their .desktop files.
 */
static string? searchable_string(string input) {
	/* Force dup in vala */
	string mod = "" + input;
	return mod.replace("\u00AD", "").ascii_down().strip();
}

public class BudgieMenuWindow : Budgie.Popover {
	protected Gtk.SearchEntry search_entry;
	protected Gtk.Box main_layout;
	protected ApplicationView view;

	public BudgieMenuWindow(Settings? settings, Gtk.Widget? leparent) {
		Object(relative_to: leparent);
		this.get_style_context().add_class("budgie-menu");

		this.main_layout = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
		this.add(main_layout);

		// search entry up north
		this.search_entry = new Gtk.SearchEntry();
		this.main_layout.pack_start(search_entry, false, false, 0);

		// middle holds the categories and applications
		this.view = new ApplicationListView(settings);
		this.main_layout.pack_start(this.view, true, true, 0);

		// searching functionality :)
		this.search_entry.changed.connect(()=> {
			var search_term = searchable_string(this.search_entry.text);
			this.view.search_changed(search_term);
		});

		this.search_entry.grab_focus();

		// Enabling activation by search entry
		this.search_entry.activate.connect(view.on_search_entry_activated);
	}

	/**
	 * Refresh the category and application views.
	 */
	public void refresh(Tracker app_tracker, bool now = false) {
		if (now) {
			this.view.refresh(app_tracker);
		} else {
			this.view.queue_refresh(app_tracker);
		}
	}

	/**
	 * We need to make some changes to our display before we go showing ourselves
	 * again! :)
	 */
	public override void show() {
		this.view.search_term = "";
		this.search_entry.text = "";
		Idle.add(() => {
			/* grab focus when we're not busy, ensuring it works.. */
			this.search_entry.grab_focus();
			return false;
		});
		base.show();
	}
}
