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
	const int HEIGHT = 510;
	const int WIDTH = 300;
	private int SCALED_HEIGHT = HEIGHT;
	private int SCALED_WIDTH = WIDTH;

	private Gtk.Box categories;
	private Gtk.ListBox applications;
	private Gtk.ScrolledWindow categories_scroll;
	private Gtk.ScrolledWindow content_scroll;
	private CategoryButton all_categories;

	public Settings settings { get; construct; default = null; }

	// The current group
	private Budgie.Category? current_category = null;
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

		SCALED_HEIGHT = HEIGHT / this.scale_factor;
		SCALED_WIDTH = WIDTH / this.scale_factor;
	}

	construct {
		this.set_size_request(SCALED_WIDTH, SCALED_HEIGHT);
		this.icon_size = settings.get_int("menu-icons-size");

		this.categories = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
			margin_top = 3,
			margin_bottom = 3
		};

		notify["scale-factor"].connect(() => {
			this.set_scaled_sizing();
		});

		this.categories_scroll = new Gtk.ScrolledWindow(null, null) {
			overlay_scrolling = false,
			shadow_type = Gtk.ShadowType.NONE, // Don't have an outline
			hscrollbar_policy = Gtk.PolicyType.NEVER,
			vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
			min_content_height = SCALED_HEIGHT,
			propagate_natural_height = true
		};
		this.categories_scroll.get_style_context().add_class("categories");
		this.categories_scroll.get_style_context().add_class("sidebar");
		this.categories_scroll.add(categories);
		this.pack_start(categories_scroll, false, false, 0);

		// "All" button"
		this.all_categories = new CategoryButton(null);
		this.all_categories.enter_notify_event.connect(this.on_mouse_enter);
		this.all_categories.toggled.connect(()=> {
			this.update_category(all_categories);
		});
		this.categories.pack_start(all_categories, false);

		var right_layout = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
		this.pack_start(right_layout, true, true, 0);

		// holds all the applications
		this.applications = new Gtk.ListBox() {
			selection_mode = Gtk.SelectionMode.SINGLE,
			valign = Gtk.Align.START,
			// Make sure that the box at least covers the whole area. This helps more themes look better
			height_request = SCALED_HEIGHT
		};
		this.applications.row_activated.connect(this.on_row_activate);

		this.content_scroll = new Gtk.ScrolledWindow(null, null) {
			overlay_scrolling = true,
			hscrollbar_policy = Gtk.PolicyType.NEVER,
			vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
			min_content_height = SCALED_HEIGHT
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

		this.set_scaled_sizing();
	}

	/**
	* Sets various widgets to use sizing based on current scale and our default HEIGHT
	*/
	private void set_scaled_sizing() {
		SCALED_HEIGHT = HEIGHT / this.scale_factor;
		SCALED_WIDTH = WIDTH / this.scale_factor;
		this.set_size_request(SCALED_WIDTH, SCALED_HEIGHT);

		this.categories_scroll.min_content_height = SCALED_HEIGHT;
		this.content_scroll.min_content_height = SCALED_HEIGHT;
		this.applications.height_request = SCALED_HEIGHT;
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
	 * Build the category and application lists.
	 */
	private void load_menus(Budgie.AppIndex app_tracker) {
		// "All" button"
		this.all_categories = new CategoryButton(null);
		this.all_categories.enter_notify_event.connect(this.on_mouse_enter);
		this.all_categories.toggled.connect(()=> {
			this.update_category(all_categories);
		});
		all_categories.show_all();
		this.categories.pack_start(all_categories, false);

		foreach (var category in app_tracker.get_categories()) {
			// Skip empty categories
			if (category.apps.is_empty) {
				continue;
			}

			// Create a new button for this category
			var btn = new CategoryButton(category);
			btn.join_group(all_categories);
			btn.enter_notify_event.connect(this.on_mouse_enter);
			btn.toggled.connect(() => {
				update_category(btn);
			});

			btn.show_all();
			this.categories.pack_start(btn, false); // Add the button

			// Create a button for each app in this category
			foreach (var app in category.apps) {
				var app_btn = new MenuButton(app, category, icon_size);

				app_btn.clicked.connect(() => {
					app.launch();
					this.app_launched();
				});

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
	 * Invalidate the application headers, filters, and sorting.
	 */
	public override void invalidate() {
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
				this.invalidate();
				break;
			case "menu-headers":
				var hed = this.settings.get_boolean(key);
				this.headers_visible = hed;
				if (hed) {
					this.applications.set_header_func(this.do_list_header);
				} else {
					this.applications.set_header_func(null);
				}
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
	 * Provide category headers in the "All" category
	 */
	private void do_list_header(Gtk.ListBoxRow? before, Gtk.ListBoxRow? after) {
		MenuButton? child = null;
		string? prev = null;
		string? next = null;

		// In a category listing, kill headers
		if (this.current_category != null) {
			if (before != null) {
				before.set_header(null);
			}
			if (after != null) {
				after.set_header(null);
			}
			return;
		}

		// Just retrieve the category names
		if (before != null) {
			child = before.get_child() as MenuButton;
			prev = child.category.name;
		}

		if (after != null) {
			child = after.get_child() as MenuButton;
			next = child.category.name;
		}

		// Only add one if we need one!
		if (before == null || after == null || prev != next) {
			var label = new Gtk.Label(Markup.printf_escaped("<big>%s</big>", prev));
			label.get_style_context().add_class("dim-label");
			label.halign = Gtk.Align.START;
			label.use_markup = true;
			before.set_header(label);
			label.margin = 6;
		} else {
			before.set_header(null);
		}
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

		// We are currently in the "All" category, so show this item
		if (this.current_category == null) {
			// Don't show this item if it's a control center panel and
			// we're set to not show them
			if (child.is_control_center_panel()) {
				if (!this.show_control_center_panels) {
					return false;
				}
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

		// Only perform category grouping if headers are visible
		string parentA = Budgie.RelevancyService.searchable_string(child1.category.name);
		string parentB = Budgie.RelevancyService.searchable_string(child2.category.name);
		if (child1.category != child2.category && this.headers_visible) {
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
			this.current_category = btn.category;
			this.invalidate();
		}
	}

	/**
	 * We need to make some changes to our display before we go showing ourselves
	 * again! :)
	 */
	public override void on_show() {
		this.all_categories.set_active(true);
		this.update_category(all_categories);

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
