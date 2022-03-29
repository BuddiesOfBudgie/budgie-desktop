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
 * Widget to display applications in a list.
 *
 * This shows a list of categories on the left, and all applications
 * on the right.
 */
public class ApplicationListView : ApplicationView {
	private Gtk.Box categories;
	private Gtk.ListBox applications;
	private Gtk.ScrolledWindow categories_scroll;
	private Gtk.ScrolledWindow content_scroll;
	private CategoryButton all_categories;

	public Settings settings { get; construct; default = null; }

	// The current group
	private Category? current_category = null;
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
		this.set_size_request(300, 510);
		this.icon_size = settings.get_int("menu-icons-size");

		this.categories = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
			margin_top = 3,
			margin_bottom = 3
		};

		this.categories_scroll = new Gtk.ScrolledWindow(null, null) {
			overlay_scrolling = false,
			shadow_type = Gtk.ShadowType.NONE, // Don't have an outline
			hscrollbar_policy = Gtk.PolicyType.NEVER,
			vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
			min_content_height = 510,
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
			this.update_category(this.all_categories);
		});
		this.categories.pack_start(this.all_categories, false, false, 0);

		var right_layout = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
		this.pack_start(right_layout, true, true, 0);

		// holds all the applications
		this.applications = new Gtk.ListBox() {
			selection_mode = Gtk.SelectionMode.NONE,
			valign = Gtk.Align.START
		};
		this.applications.row_activated.connect(this.on_row_activate);

		this.content_scroll = new Gtk.ScrolledWindow(null, null) {
			overlay_scrolling = true,
			hscrollbar_policy = Gtk.PolicyType.NEVER,
			vscrollbar_policy = Gtk.PolicyType.AUTOMATIC
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
	}

	/**
	 * Refreshes the category and application lists.
	 */
	public override void refresh(Tracker app_tracker) {
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
		foreach (var child in this.categories.get_children()) {
			child.destroy();
		}

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
	private void load_menus(Tracker app_tracker) {
		// "All" button"
		this.all_categories = new CategoryButton(null);
		this.all_categories.enter_notify_event.connect(this.on_mouse_enter);
		this.all_categories.toggled.connect(()=> {
			this.update_category(this.all_categories);
		});
		this.categories.pack_start(this.all_categories, false, false, 0);

		foreach (var category in app_tracker.categories) {
			// Skip empty categories
			if (category.apps.is_empty) {
				continue;
			}

			// Create a new button for this category
			var btn = new CategoryButton(category);
			btn.join_group(all_categories);
			btn.enter_notify_event.connect(this.on_mouse_enter);

			// Ensures we find the correct button
			btn.toggled.connect(() => {
				this.update_category(btn);
			});

			btn.show_all();
			this.categories.pack_start(btn, false, false, 0); // Add the button

			// Create a button for each app in this category
			foreach (var app in category.apps) {
				if (app.desktop_id == "budgie-control-center.desktop") {
					// Check if this is a control center panel
					var control_center = "budgie-control-center";
					bool is_control_center_panel = (
						control_center in app.exec &&
						app.exec.length != control_center.length
					);

					if (is_control_center_panel) {

					}
				}
				var app_btn = new MenuButton(app, category, icon_size);

				app_btn.clicked.connect(() => {
					hide();
					app.launch();
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

		string term = this.search_term.strip();
		if (term.length > 0) {
			// "disable" categories while searching
			this.categories.sensitive = false;
			// Items must be unique across the search
			if (this.is_item_dupe(child)) {
				return false;
			}

			return info_matches_term(child.app, term);
		}

		// "enable" categories if not searching
		this.categories.sensitive = true;

		// No more filtering, show all
		if (this.current_category == null) {
			// Filter out control center panels if not set to show
			if (child.is_control_center_panel()) {
				if (!this.show_control_center_panels) {
					return false;
				}
			}

			if (this.headers_visible) { // If we are going to be showing headers
				return true;
			} else { // Not showing headers
				return !this.is_item_dupe(child);
			}
		}

		// If the Category isn't the same as the current filter, hide it
		if (child.category != this.current_category) {
			return false;
		}

		// Filter out control center panels if not set to show
		if (child.is_control_center_panel()) {
			if (!this.show_control_center_panels) {
				return false;
			}
		}

		return true;
	}

	private int do_sort_list(Gtk.ListBoxRow row1, Gtk.ListBoxRow row2) {
		MenuButton child1 = row1.get_child() as MenuButton;
		MenuButton child2 = row2.get_child() as MenuButton;

		string term = this.search_term.strip();

		if (term.length > 0) {
			int sc1 = child1.get_score(term);
			int sc2 = child2.get_score(term);
			/* Vala can't do this: return (sc1 > sc2) - (sc1 - sc2); */
			if (sc1 < sc2) {
				return 1;
			} else if (sc1 > sc2) {
				return -1;
			}
			return 0;
		}

		// Only perform category grouping if headers are visible
		string parentA = searchable_string(child1.category.name);
		string parentB = searchable_string(child2.category.name);
		if (child1.category != child2.category && this.headers_visible) {
			return parentA.collate(parentB);
		}

		string nameA = searchable_string(child1.app.name);
		string nameB = searchable_string(child2.app.name);
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
	public override void show() {
		this.current_category = null;
		this.all_categories.set_active(true);
		this.applications.select_row(null);
		this.content_scroll.get_vadjustment().set_value(0);
		this.categories_scroll.get_vadjustment().set_value(0);
		this.categories.sensitive = true;

		base.show();
		if (!this.compact_mode) {
			this.categories_scroll.show_all();
		} else {
			this.categories_scroll.hide();
		}
	}
}
