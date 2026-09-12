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
 * Widget to display applications in a list.
 *
 * This shows a list of categories on the left, and all applications
 * on the right.
 */
public class ApplicationListView : ApplicationView {
	const int MIN_HEIGHT = 480;
	const int MAX_HEIGHT = 600;
	const int WIDTH = 300;
	const double HEIGHT_RATIO = 0.35;
	private int current_height = MIN_HEIGHT;
	private int current_width = WIDTH;

	private Gtk.Box categories;
	private Gtk.ListBox applications;
	private Gtk.ScrolledWindow categories_scroll;
	private Gtk.ScrolledWindow content_scroll;
	private CategoryButton all_categories;
	private CategoryButton favorites_category;
	private MenuButton? expanded_row = null;

	public Settings settings { get; construct; default = null; }

	private FavoritesManager favorites;

	// The current group
	private Budgie.Category? current_category = null;
	private bool favorites_selected = false;
	private bool compact_mode;
	private bool headers_visible;
	private bool show_control_center_panels;

	/* Whether we allow rollover category switch */
	private bool rollover_menus = true;

	private bool reloading = false;

	public ApplicationListView(Settings settings) {
		Object(
			settings: settings,
			orientation: Gtk.Orientation.HORIZONTAL,
			spacing: 0
		);

	}

	construct {
		this.realize.connect(() => {
			this.update_sizing();
		});

		this.set_size_request(current_width, current_height);
		this.icon_size = settings.get_int("menu-icons-size");

		this.favorites = new FavoritesManager(settings);
		this.favorites.changed.connect(this.on_favorites_changed);

		this.categories = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
			margin_top = 3,
			margin_bottom = 3
		};

		this.categories_scroll = new Gtk.ScrolledWindow(null, null) {
			overlay_scrolling = false,
			shadow_type = Gtk.ShadowType.NONE, // Don't have an outline
			hscrollbar_policy = Gtk.PolicyType.NEVER,
			vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
			min_content_height = current_height,
			propagate_natural_height = true
		};
		this.categories_scroll.get_style_context().add_class("categories");
		this.categories_scroll.get_style_context().add_class("sidebar");
		this.categories_scroll.add(categories);
		this.pack_start(categories_scroll, false, false, 0);

		var right_layout = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
		this.pack_start(right_layout, true, true, 0);

		// holds all the applications
		this.applications = new Gtk.ListBox() {
			selection_mode = Gtk.SelectionMode.SINGLE,
			valign = Gtk.Align.START,
			// Make sure that the box at least covers the whole area. This helps more themes look better
			height_request = current_height
		};
		this.applications.row_activated.connect(this.on_row_activate);

		this.content_scroll = new Gtk.ScrolledWindow(null, null) {
			overlay_scrolling = true,
			hscrollbar_policy = Gtk.PolicyType.NEVER,
			vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
			min_content_height = current_height
		};
		this.content_scroll.set_overlay_scrolling(true);
		this.content_scroll.add(applications);
		right_layout.pack_start(content_scroll, true, true, 0);

		// placeholder in case of no results
		var placeholder = new Gtk.Label("<big>%s</big>".printf(_("Sorry, no items found"))) {
			use_markup = true,
			margin = 6,
		};
		placeholder.get_style_context().add_class("dim-label");
		placeholder.show();
		this.applications.set_placeholder(placeholder);

		this.settings.changed.connect(on_settings_changed);
		this.on_settings_changed("menu-compact");
		this.on_settings_changed("menu-headers");
		this.on_settings_changed("menu-categories-hover");
		this.on_settings_changed("menu-show-control-center-items");

		// management of our listbox
		this.applications.set_filter_func(do_filter_list);
		this.applications.set_sort_func(do_sort_list);

		this.build_static_categories();

		this.update_sizing();
	}

	/**
	 * Computes the menu height from the monitor workarea.
	 * Returns at least MIN_HEIGHT.
	 */
	private int compute_base_height() {
		var toplevel = this.get_toplevel();
		if (toplevel == null) {
			return MIN_HEIGHT;
		}

		var gdk_window = toplevel.get_window();
		if (gdk_window == null) {
			return MIN_HEIGHT;
		}

		var display = toplevel.get_display();
		var monitor = display.get_monitor_at_window(gdk_window);
		var workarea = monitor.get_workarea();

		int computed = (int) (workarea.height * HEIGHT_RATIO);
		return computed.clamp(MIN_HEIGHT, MAX_HEIGHT);
	}

	/**
	 * Updates widget sizing based on the monitor workarea.
	 */
	private void update_sizing() {
		current_height = compute_base_height();
		this.set_size_request(current_width, current_height);

		this.categories_scroll.min_content_height = current_height;
		this.content_scroll.min_content_height = current_height;
		this.applications.height_request = current_height;
	}

	/**
	 * Refreshes the category and application lists.
	 */
	public override void refresh(Budgie.AppIndex app_tracker) {
		lock (this.reloading) {
			if (this.reloading) {
				return;
			}
			this.reloading = true;
		}

		// Destroy all application items
		foreach (var child in this.applications.get_children()) {
			child.destroy();
		}
		this.application_buttons.remove_all();
		this.control_center_buttons.clear();
		this.expanded_row = null;

		// Destroy all category items
		this.categories.get_children().foreach((child) => {
			child.destroy();
		});

		// Load all of the new content in the background
		Idle.add(() => {
			this.load_menus(app_tracker);
			this.invalidate();
			return false;
		});

		lock (this.reloading) {
			this.reloading = false;
		}
	}

	/**
	 * Build the category buttons that aren't backed by the application index.
	 *
	 * These are packed ahead of the indexed categories, and are rebuilt along
	 * with them whenever the view refreshes.
	 */
	private void build_static_categories() {
		this.favorites_category = new CategoryButton.for_favorites() {
			no_show_all = true // Only appears once something has been favorited
		};
		this.favorites_category.enter_notify_event.connect(this.on_mouse_enter);
		this.favorites_category.toggled.connect(this.on_category_toggled);
		this.categories.pack_start(favorites_category, false);

		this.all_categories = new CategoryButton(null);
		this.all_categories.enter_notify_event.connect(this.on_mouse_enter);
		this.all_categories.toggled.connect(this.on_category_toggled);
		this.all_categories.show_all();
		this.categories.pack_start(all_categories, false);

		this.favorites_category.join_group(all_categories);

		// These buttons are new, and a new group comes up on "All"
		this.favorites_selected = false;
		this.current_category = null;

		this.update_favorites_visibility();
	}

	/**
	 * Build the category and application lists.
	 */
	private void load_menus(Budgie.AppIndex app_tracker) {
		this.build_static_categories();

		// Nothing to separate if every category is empty
		foreach (var category in app_tracker.get_categories()) {
			if (category.apps.is_empty) {
				continue;
			}

			var separator = new Gtk.Separator(Gtk.Orientation.HORIZONTAL);
			separator.show();
			this.categories.pack_start(separator, false, false, 0);
			break;
		}

		foreach (var category in app_tracker.get_categories()) {
			// Skip empty categories
			if (category.apps.is_empty) {
				continue;
			}

			// Create a new button for this category
			var btn = new CategoryButton(category);
			btn.join_group(all_categories);
			btn.enter_notify_event.connect(this.on_mouse_enter);
			btn.toggled.connect(this.on_category_toggled);

			btn.show_all();
			this.categories.pack_start(btn, false); // Add the button

			// Create a button for each app in this category
			foreach (var app in category.apps) {
				var app_btn = new MenuButton(app, category, icon_size, favorites);

				app_btn.clicked.connect(this.on_app_clicked);
				app_btn.action_launched.connect(this.on_app_action_launched);
				app_btn.expanded.connect(this.on_row_expanded);

				this.application_buttons.insert(app.desktop_id, app_btn);
				app_btn.show_all();
				this.applications.add(app_btn);

				if (app_btn.is_control_center_panel()) {
					this.control_center_buttons.add(app_btn);
				}
			}
		}
	}

	/**
	 * Launch the application for a menu item.
	 */
	private void on_app_clicked(MenuButton btn) {
		btn.app.launch();
		this.app_launched();
	}

	private void on_app_action_launched() {
		this.app_launched();
	}

	private void on_category_toggled(Gtk.ToggleButton button) {
		this.update_category(button as CategoryButton);
	}

	/**
	 * Only one menu item shows its actions at a time.
	 */
	private void on_row_expanded(MenuButton btn) {
		if (this.expanded_row != null && this.expanded_row != btn) {
			this.expanded_row.set_revealed(false);
		}

		this.expanded_row = btn;
	}

	private void collapse_expanded_row() {
		if (this.expanded_row == null) {
			return;
		}

		this.expanded_row.set_revealed(false);
		this.expanded_row = null;
	}

	/**
	 * Update everything that depends on which applications are favorited.
	 */
	private void on_favorites_changed() {
		this.update_favorites_visibility();

		// Favorites changed and is now empty (so we unfavorited our last item)
		if (this.favorites_selected && this.favorites.is_empty()) {
			this.all_categories.set_active(true); // Change to "All" category
			return;
		}

		this.invalidate();
	}

	private void update_favorites_visibility() {
		this.favorites_category.set_visible(!this.favorites.is_empty());
	}

	/**
	 * Invalidate the application headers, filters, and sorting.
	 */
	public override void invalidate() {
		this.collapse_expanded_row();
		this.applications.invalidate_headers();
		this.applications.invalidate_filter();
		this.applications.invalidate_sort();
	}

	/**
	 * Launches the application selected by the current search result.
	 */
	public override void on_search_entry_activated() {
		Gtk.ListBoxRow? selected = null;

		var rows = this.applications.get_selected_rows();
		if (rows != null) {
			selected = rows.data;
		} else {
			foreach (var child in this.applications.get_children()) {
				if (child.get_visible() && child.get_child_visible()) {
					selected = child as Gtk.ListBoxRow;
					break;
				}
			}
		}
		if (selected == null) {
			return;
		}

		MenuButton btn = selected.get_child() as MenuButton;
		btn.app.launch();
		this.app_launched();
	}

	/**
	 * Permits "rolling" over categories.
	 */
	private bool on_mouse_enter(Gtk.Widget source_widget, Gdk.EventCrossing e) {
		if (!this.rollover_menus) {
			return Gdk.EVENT_PROPAGATE;
		}

		// If it's not valid, don't use it.
		Gtk.ToggleButton? b = source_widget as Gtk.ToggleButton;
		if (!b.get_sensitive() || !b.get_visible()) {
			return Gdk.EVENT_PROPAGATE;
		}

		// Activate the source_widget category
		b.set_active(true);
		return Gdk.EVENT_PROPAGATE;
	}

	/**
	 * Handles changes to our applet settings.
	 */
	private void on_settings_changed(string key) {
		switch (key) {
			case "menu-compact":
				var vis = settings.get_boolean(key);
				this.categories_scroll.no_show_all = vis;
				this.categories_scroll.set_visible(vis);
				this.compact_mode = vis;
				this.update_header_func();
				this.invalidate();
				break;
			case "menu-headers":
				this.headers_visible = this.settings.get_boolean(key);
				this.update_header_func();
				this.invalidate();
				break;
			case "menu-categories-hover":
				// Category hover
				this.rollover_menus = this.settings.get_boolean(key);
				break;
			case "menu-show-control-center-items":
				this.show_control_center_panels = this.settings.get_boolean(key);
				this.invalidate();
				break;
			default:
				// not interested
				break;
		}
	}

	/**
	 * Launches the application in the given row.
	 */
	private void on_row_activate(Gtk.ListBoxRow? row) {
		if (row == null) {
			return;
		}
		// Launch this item, i.e. keyboard access
		MenuButton btn = row.get_child() as MenuButton;
		btn.app.launch();
		this.app_launched();
	}

	/**
	 * The header function only runs when there is something for it to draw:
	 * category headers, or the break below the compact list's favorites.
	 */
	private void update_header_func() {
		if (this.headers_visible || this.compact_mode) {
			this.applications.set_header_func(this.do_list_header);
		} else {
			this.applications.set_header_func(null);
		}
	}

	private bool is_favorite_row(Gtk.ListBoxRow row) {
		var btn = row.get_child() as MenuButton;
		return this.favorites.is_favorite(btn.app.desktop_id);
	}

	/**
	 * Provide category headers in the "All" category
	 */
	private void do_list_header(Gtk.ListBoxRow? row, Gtk.ListBoxRow? before) {
		MenuButton? child = null;
		string? group = null;
		string? previous_group = null;

		// In a category listing, kill headers
		if (this.current_category != null || this.favorites_selected) {
			if (row != null) {
				row.set_header(null);
			}
			if (before != null) {
				before.set_header(null);
			}
			return;
		}

		// Just retrieve the group names
		if (row != null) {
			child = row.get_child() as MenuButton;
			group = this.group_name_for(child);
		}

		if (before != null) {
			child = before.get_child() as MenuButton;
			previous_group = this.group_name_for(child);
		}

		// Compact mode sorts favorites to the top. With headers off there is
		// no label to mark where they end, so use a separator
		if (!this.headers_visible) {
			// The separator belongs on the first non-favorite row that has a
			// favorite above it. before is null for the list's first row,
			// which has nothing above it to be separated from
			if (this.compact_mode && before != null && this.is_favorite_row(before) && !this.is_favorite_row(row)) {
				row.set_header(new Gtk.Separator(Gtk.Orientation.HORIZONTAL));
			} else {
				row.set_header(null);
			}
			return;
		}

		// Only add one if we need one!
		if (row == null || before == null || group != previous_group) {
			var label = new Gtk.Label(Markup.printf_escaped("<big>%s</big>", group));
			label.get_style_context().add_class("dim-label");
			label.halign = Gtk.Align.START;
			label.use_markup = true;
			row.set_header(label);
			label.margin = 6;
		} else {
			row.set_header(null);
		}
	}

	/**
	 * The heading a menu item belongs under in the "All" listing.
	 *
	 * Compact mode has no category list, so favorites are grouped together
	 * ahead of the categories instead.
	 */
	private string group_name_for(MenuButton btn) {
		if (this.compact_mode && this.favorites.is_favorite(btn.app.desktop_id)) {
			return _("Favorites");
		}

		return btn.category.name;
	}

	/**
	 * Filter out results in the list according to whatever the current filter is,
	 * i.e. group based or search based
	 */
	private bool do_filter_list(Gtk.ListBoxRow row) {
		MenuButton child = row.get_child() as MenuButton;

		// Check if there is a search going on
		string term = this.search_term.strip();
		if (term.length > 0) {
			// "disable" categories while searching
			this.categories.sensitive = false;
			// Items must be unique across the search
			if (this.is_item_dupe(child)) {
				return false;
			}

			// Only show this item if its relevancy to the search term
			// is within an arbitrary threshold
			return this.relevancy_service.is_app_relevant(child.app);
		}

		// "enable" categories if not searching
		this.categories.sensitive = true;

		// If we have our favorites selected, filter out anything that isn't a favorite
		if (this.favorites_selected) {
			if (!this.favorites.is_favorite(child.app.desktop_id)) {
				return false;
			}

			// An app belonging to several categories has an item in each
			return !this.is_item_dupe(child);
		}

		// We are currently in the "All" category, so show this item
		if (this.current_category == null) {
			// Don't show this item if it's a control center panel and
			// we're set to not show them
			if (child.is_control_center_panel()) {
				if (!this.show_control_center_panels) {
					return false;
				}
			}

			// Favorites are grouped together at the top of the compact list,
			// so they appear once rather than once per category
			if (this.compact_mode && this.favorites.is_favorite(child.app.desktop_id)) {
				return !this.is_item_dupe(child);
			}

			if (this.headers_visible) {
				// Show all items if headers are visible
				return true;
			} else {
				// Headers aren't being shown, so only show this item if
				// it's not a duplicate
				return !this.is_item_dupe(child);
			}
		}

		// Hide this item if we're in a different category
		if (child.category != this.current_category) {
			return false;
		}

		// Don't show this item if it's a control panel and we're not set to show them
		if (child.is_control_center_panel()) {
			if (!this.show_control_center_panels) {
				return false;
			}
		}

		// If we got here, then we are in a category that this item belongs to,
		// so show it
		return true;
	}

	/**
	 * Sorts two list items.
	 *
	 * If there is an active search, items will be sorted by how well they match the term.
	 * Otherwise, they will be sorted alphebetically by their name.
	 */
	private int do_sort_list(Gtk.ListBoxRow row1, Gtk.ListBoxRow row2) {
		MenuButton child1 = row1.get_child() as MenuButton;
		MenuButton child2 = row2.get_child() as MenuButton;

		string term = this.search_term.strip();

		// Check for an active search
		if (term.length > 0) {
			// Get the scores relative to the search term
			int sc1 = this.relevancy_service.get_score(child1.app);
			int sc2 = this.relevancy_service.get_score(child2.app);

			// The item with the lower score should be higher in the list
			if (sc1 < sc2) {
				return -1;
			} else if (sc1 > sc2) {
				return 1;
			} else {
				// Scores are equal, so sort by name
				return child1.app.name.collate(child2.app.name);
			}
		}

		// Compact mode has no category list, so favorites go to the top of it
		if (this.compact_mode) {
			bool favorite1 = this.favorites.is_favorite(child1.app.desktop_id);
			bool favorite2 = this.favorites.is_favorite(child2.app.desktop_id);

			if (favorite1 != favorite2) {
				return favorite1 ? -1 : 1;
			}
		}

		// Only perform category grouping if headers are visible
		string parentA = Budgie.RelevancyService.searchable_string(this.group_name_for(child1));
		string parentB = Budgie.RelevancyService.searchable_string(this.group_name_for(child2));
		if (!this.favorites_selected && parentA != parentB && this.headers_visible) {
			return parentA.collate(parentB);
		}

		// Two application items, sort by name
		string nameA = Budgie.RelevancyService.searchable_string(child1.app.name);
		string nameB = Budgie.RelevancyService.searchable_string(child2.app.name);
		return nameA.collate(nameB);
	}

	/**
	 * Change the current group/category
	 */
	private void update_category(CategoryButton btn) {
		if (btn.active) {
			this.favorites_selected = btn.favorites;
			this.current_category = btn.category;
			this.invalidate();
		}
	}

	/**
	 * We need to make some changes to our display before we go showing ourselves
	 * again! :)
	 */
	public override void on_show() {
		this.update_favorites_visibility();

		// Compact mode hides the category list (not to be confused with category headers),
		// so it stays on "All" with the favorites sorted to the top instead
		if (!this.compact_mode && !this.favorites.is_empty()) {
			this.favorites_category.set_active(true);
			this.update_category(favorites_category);
		} else {
			this.all_categories.set_active(true);
			this.update_category(all_categories);
		}

		this.applications.select_row(null);
		this.content_scroll.get_vadjustment().set_value(0);
		this.categories_scroll.get_vadjustment().set_value(0);
		this.categories.sensitive = true;

		if (!this.compact_mode) {
			this.categories_scroll.show_all();
		} else {
			this.categories_scroll.hide();
		}
	}
}
