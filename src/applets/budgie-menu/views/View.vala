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

/**
 * Abstract class for different views for the application menu to
 * extend.
 */
public abstract class ApplicationView : Gtk.Box {
	/** Mapped id to MenuButton */
	public HashTable<string,MenuButton?> application_buttons { get; construct set; default = null; }
	public Gee.ArrayList<MenuButton> control_center_buttons { get; construct set; default = null; }
	public string search_term { get; public set; default = ""; }
	public int icon_size { get; protected set; default = 24; }

	protected Budgie.RelevancyService relevancy_service;
	private uint timeout_id = 0;

	/**
	 * Emitted when an app is launched.
	 */
	public signal void app_launched();

	construct {
		this.application_buttons = new HashTable<string,MenuButton?>(str_hash, str_equal);
		this.control_center_buttons = new Gee.ArrayList<MenuButton>();
		this.relevancy_service = new Budgie.RelevancyService();
	}

	/**
	 * This should be called when the user activates a search entry.
	 */
	public abstract void on_search_entry_activated();

	/**
	 * Performs any work that should be done to the view when the menu
	 * is opened, e.g. resetting the current category or invalidating filters.
	 */
	public abstract void on_show();

	/**
	 * Refreshes the entire application view.
	 */
	public abstract void refresh(Budgie.AppIndex app_tracker);

	/**
	 * Invalidate aspects of the view, e.g. category headers.
	 */
	public abstract void invalidate();

	/**
	 * Queue a refresh of the application view.
	 *
	 * The time to wait before refreshing can be set by passing in `seconds`.
	 * By default, the time is 1 second.
	 */
	public void queue_refresh(Budgie.AppIndex app_tracker, int seconds = 1) {
		// Reset the refresh timer if an update is already queued
		if (this.timeout_id != 0) {
			Source.remove(this.timeout_id);
			this.timeout_id = 0;
		}

		// Update the view after the timeout
		this.timeout_id = Timeout.add_seconds(seconds, () => {
			this.refresh(app_tracker);
			this.timeout_id = 0;
			return Source.REMOVE;
		});
	}

	/**
	 * To be called when the search entry changes.
	 */
	public void search_changed(string search_term) {
		this.search_term = search_term;

		// Update the relevancy of all apps when
		// the search term changes
		foreach (var child in this.application_buttons.get_values()) {
			this.relevancy_service.update_relevancy(child.app, search_term);
		}

		this.invalidate();
	}

	/**
	 * Checks if a `MenuButton` already exists in the view.
	 */
	protected bool is_item_dupe(MenuButton? button) {
		MenuButton? compare_item = this.application_buttons.lookup(button.app.desktop_id);
		if (compare_item != null && compare_item != button) {
			return true;
		}
		return false;
	}
}
