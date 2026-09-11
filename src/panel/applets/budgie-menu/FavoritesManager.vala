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
 * Tracks which applications the user has favorited.
 */
public class FavoritesManager : Object {
	public Settings settings { get; construct; }

	/**
	 * Emitted when the set of favorited applications changes.
	 */
	public signal void changed();

	private string[] favorites;

	public FavoritesManager(Settings settings) {
		Object(settings: settings);
	}

	construct {
		this.settings.changed["favorites"].connect(this.on_settings_changed);
		this.reload();
	}

	public bool is_favorite(string desktop_id) {
		return desktop_id in this.favorites;
	}

	public bool is_empty() {
		return this.favorites.length == 0;
	}

	/**
	 * Add the application to the favorites, or take it back out if it
	 * is already there.
	 */
	public void toggle(string desktop_id) {
		string[] updated;

		// If it is currently in the favorites, meaning we need to remove it
		if (this.is_favorite(desktop_id)) {
			updated = {}; // Create the new array

			foreach (unowned var id in this.favorites) {
				if (id != desktop_id) { // For every desktop id that isn't the one we are removing
					updated += id; // Add it to the new array
				}
			}
		} else { // If we are adding it to the favorites, just copy and push
			updated = this.favorites.copy();
			updated += desktop_id;
		}

		// on_settings_changed reloads our copy
		this.settings.set_strv("favorites", updated);
	}

	private void on_settings_changed(string key) {
		this.reload();
		this.changed();
	}

	private void reload() {
		this.favorites = this.settings.get_strv("favorites");
	}
}
