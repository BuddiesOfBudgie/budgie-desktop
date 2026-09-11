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

	private GenericSet<string> favorites;

	public FavoritesManager(Settings settings) {
		Object(settings: settings);
	}

	construct {
		this.favorites = new GenericSet<string>(str_hash, str_equal);
		this.reload();

		this.settings.changed["favorites"].connect(this.on_settings_changed);
	}

	public bool is_favorite(string desktop_id) {
		return this.favorites.contains(desktop_id);
	}

	public bool is_empty() {
		return this.favorites.length == 0;
	}

	/**
	 * Add the application to the favorites, or take it back out if it
	 * is already there.
	 */
	public void toggle(string desktop_id) {
		string[] updated = {};

		if (this.favorites.contains(desktop_id)) {
			foreach (unowned var id in this.settings.get_strv("favorites")) {
				if (id != desktop_id) {
					updated += id;
				}
			}
		} else {
			updated = this.settings.get_strv("favorites");
			updated += desktop_id;
		}

		// on_settings_changed reloads the set
		this.settings.set_strv("favorites", updated);
	}

	private void on_settings_changed(string key) {
		this.reload();
		this.changed();
	}

	private void reload() {
		this.favorites.remove_all();

		foreach (unowned var id in this.settings.get_strv("favorites")) {
			this.favorites.add(id);
		}
	}
}
