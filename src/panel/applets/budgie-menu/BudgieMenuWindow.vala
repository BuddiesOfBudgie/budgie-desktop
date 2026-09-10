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

public class BudgieMenuWindow : Gtk.Window {
	protected Gtk.Box main_layout;
	protected Gtk.SearchEntry search_entry;
	protected ApplicationView view;

	private Gtk.Overlay outer_layout;
	private MenuArrow arrow;

	private Gtk.Overlay overlay;
	private UserButton user_indicator;
	private Gtk.Button budgie_desktop_prefs_button;
	private Gtk.Button system_settings_button;
	private Gtk.Button power_button;
	private OverlayMenus overlay_menu;

	private PowerDialogRemote? power_dialog = null;

	// The launcher button the menu is aligned against
	private unowned Gtk.Widget? launcher;

	// True once we have had keyboard focus since show(), so the unfocused
	// state right after showing isn't mistaken for losing it
	private bool focus_granted = false;

	// Losing focus while the pointer is over the menu isn't a click outside
	private bool pointer_inside = false;

	public BudgieMenuWindow(Settings? settings, Gtk.Widget? leparent) {
		Object(type: Gtk.WindowType.TOPLEVEL);
		this.launcher = leparent;
		this.get_style_context().add_class("budgie-menu-window");
		this.decorated = false;
		this.resizable = false;
		this.add_events(Gdk.EventMask.ENTER_NOTIFY_MASK | Gdk.EventMask.LEAVE_NOTIFY_MASK);

		// A popover only gets keyboard input while the panel is focused, and a
		// keybinding can't focus the panel. So the menu is its own layer surface.
		if (GtkLayerShell.is_supported()) {
			GtkLayerShell.init_for_window(this);
			GtkLayerShell.set_namespace(this, "budgie-menu");
			GtkLayerShell.set_layer(this, GtkLayerShell.Layer.TOP);
			GtkLayerShell.set_keyboard_mode(this, GtkLayerShell.KeyboardMode.ON_DEMAND);
		}

		// Transparent window so the arrow can stick out past the body
		this.app_paintable = true;
		Gdk.Visual? visual = this.get_screen().get_rgba_visual();
		if (visual != null) {
			this.set_visual(visual);
		}

		this.main_layout = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
		this.main_layout.get_style_context().add_class("budgie-menu");

		this.arrow = new MenuArrow();

		// The arrow reaches back over the body's border, so it can't be a sibling in a box.
		// The body carries a margin on the panel-facing side for the arrow to sit in.
		this.outer_layout = new Gtk.Overlay();
		this.outer_layout.add(this.main_layout);
		this.outer_layout.add_overlay(this.arrow);
		this.outer_layout.set_overlay_pass_through(this.arrow, true);
		this.add(this.outer_layout);

		// Header items at the top with search input
		var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
		header.get_style_context().add_class("budgie-menu-header");

		this.search_entry = new Gtk.SearchEntry();
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

		Bus.get_proxy.begin<PowerDialogRemote>(
			BusType.SESSION,
			"org.buddiesofbudgie.PowerDialog",
			"/org/buddiesofbudgie/PowerDialog",
			DBusProxyFlags.NONE,
			null,
			on_power_dialog_get
		);

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
			this.open_desktop_entry("org.buddiesofbudgie.ControlCenter.desktop");
			this.hide();
		});

		this.budgie_desktop_prefs_button.clicked.connect(() => {
			this.open_desktop_entry("org.buddiesofbudgie.BudgieDesktopSettings.desktop");
			this.hide();
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

		// Show the Power Dialog when the user indicator is clicked
		this.power_button.clicked.connect(() => {
			if (power_dialog == null) {
				return;
			}

			this.hide();

			try {
				power_dialog.Toggle();
			} catch (Error e) {
				warning("Error trying to show PowerDialog: %s", e.message);
			}
		});

		// We should go away when a user menu button is clicked
		this.overlay_menu.item_clicked.connect(this.hide);

		// We should go away when an app is launched from the menu
		this.view.app_launched.connect(this.hide);

		this.map.connect(on_map);
		this.notify["is-active"].connect(on_active_changed);
		this.enter_notify_event.connect(on_enter_notify);
		this.leave_notify_event.connect(on_leave_notify);

		// Respects no_show_all, so compact mode keeps its hidden children
		this.outer_layout.show_all();
	}

	private void on_power_dialog_get(Object? obj, AsyncResult? res) {
		try {
			power_dialog = Bus.get_proxy.end(res);
		} catch (Error e) {
			critical("Unable to get PowerDialog DBus remote: %s", e.message);
		}
	}

	// The entry can only take focus once the surface is up
	private void on_map() {
		Idle.add(focus_search_entry);
	}

	private bool focus_search_entry() {
		this.search_entry.grab_focus();
		return Source.REMOVE;
	}

	// Losing keyboard focus is the layer-surface version of a click outside,
	// unless the pointer is still over the menu
	private void on_active_changed(Object sender, ParamSpec pspec) {
		if (this.is_active) {
			this.focus_granted = true;
		} else if (this.focus_granted && this.visible && !this.pointer_inside) {
			this.hide();
		}
	}

	// INFERIOR crossings are into our own children, not out of the window
	private bool on_enter_notify(Gdk.EventCrossing event) {
		if (event.detail != Gdk.NotifyType.INFERIOR) {
			this.pointer_inside = true;
		}
		return Gdk.EVENT_PROPAGATE;
	}

	private bool on_leave_notify(Gdk.EventCrossing event) {
		if (event.detail != Gdk.NotifyType.INFERIOR) {
			this.pointer_inside = false;
		}
		return Gdk.EVENT_PROPAGATE;
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
	 * Reset the menu UI to the base state.
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

	/**
	 * Align the menu with the launcher on the panel's edge, then show it.
	 */
	public void present_menu(Budgie.PanelPosition position) {
		this.set_geometry(position);
		this.focus_granted = false;
		this.pointer_inside = false;
		this.reset(true);
		this.show();
	}

	/**
	 * Layer-shell surfaces can only be placed against output edges, so the menu
	 * is anchored to the panel's edge and pushed along it by a margin that
	 * centers it on the launcher.
	 */
	private void set_geometry(Budgie.PanelPosition position) {
		if (!GtkLayerShell.is_supported()) {
			return;
		}

		Gtk.Window? panel = this.launcher != null ? this.launcher.get_toplevel() as Gtk.Window : null;

		// Get the monitor that the panel is on
		Gdk.Monitor? monitor = null;
		if (panel != null && GtkLayerShell.is_layer_window(panel)) {
			monitor = GtkLayerShell.get_monitor(panel);
			if (monitor != null) { // Set the window (this) to be on the same monitor as the panel
				GtkLayerShell.set_monitor(this, monitor);
			}
		}

		// Clear stale anchors; the panel may have moved since the last show
		GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.TOP, false);
		GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.BOTTOM, false);
		GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.LEFT, false);
		GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.RIGHT, false);

		bool vertical = (position == Budgie.PanelPosition.LEFT || position == Budgie.PanelPosition.RIGHT);

		int monitor_extent = 0;
		if (monitor != null) {
			Gdk.Rectangle geometry = monitor.get_geometry();
			monitor_extent = vertical ? geometry.height : geometry.width;
		}

		// Where the launcher sits along the panel and how big it is. The panel
		// starts at the monitor edge, so panel coordinates are monitor coordinates.
		int launcher_offset = 0;
		int launcher_extent = 0;
		if (this.launcher != null) {
			int lx = 0;
			int ly = 0;
			if (panel != null && this.launcher.translate_coordinates(panel, 0, 0, out lx, out ly)) {
				launcher_offset = vertical ? ly : lx;
			}

			Gtk.Allocation launcher_alloc;
			this.launcher.get_allocation(out launcher_alloc);
			launcher_extent = vertical ? launcher_alloc.height : launcher_alloc.width;
		}

		// A dock-mode panel is shorter than the monitor and centered on it by the
		// compositor, so it doesn't start at the monitor edge. Zero for a full panel.
		if (panel != null && monitor_extent > 0) {
			int panel_extent = vertical ? panel.get_allocated_height() : panel.get_allocated_width();
			int panel_start = (monitor_extent - panel_extent) / 2;
			if (panel_start > 0) {
				launcher_offset += panel_start;
			}
		}

		int menu_min = 0;
		int menu_nat = 0;
		if (vertical) {
			this.main_layout.get_preferred_height(out menu_min, out menu_nat);
		} else {
			this.main_layout.get_preferred_width(out menu_min, out menu_nat);
		}
		// Fallback if the body has no size yet
		if (menu_nat <= 0) {
			menu_nat = launcher_extent;
		}

		// Keep the menu on the monitor; the arrow slides to stay on the launcher
		int margin = launcher_offset + (launcher_extent - menu_nat) / 2;
		if (monitor_extent > 0) {
			int max_margin = monitor_extent - menu_nat;
			if (max_margin < 0) max_margin = 0;
			if (margin > max_margin) margin = max_margin;
		}
		if (margin < 0) margin = 0;

		this.arrange_arrow(position, vertical, launcher_offset + launcher_extent / 2 - margin, menu_nat);

		switch (position) {
			case Budgie.PanelPosition.TOP:
				GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.TOP, true);
				GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.LEFT, true);
				GtkLayerShell.set_margin(this, GtkLayerShell.Edge.LEFT, margin);
				break;
			case Budgie.PanelPosition.LEFT:
				GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.LEFT, true);
				GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.TOP, true);
				GtkLayerShell.set_margin(this, GtkLayerShell.Edge.TOP, margin);
				break;
			case Budgie.PanelPosition.RIGHT:
				GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.RIGHT, true);
				GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.TOP, true);
				GtkLayerShell.set_margin(this, GtkLayerShell.Edge.TOP, margin);
				break;
			case Budgie.PanelPosition.BOTTOM:
			default:
				GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.BOTTOM, true);
				GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.LEFT, true);
				GtkLayerShell.set_margin(this, GtkLayerShell.Edge.LEFT, margin);
				break;
		}
	}

	/**
	 * Put the arrow on the panel-facing side of the body, pointing at the launcher.
	 */
	private void arrange_arrow(Budgie.PanelPosition position, bool vertical, int launcher_center, int menu_nat) {
		this.arrow.position = position;

		// Leave room for the arrow on the panel-facing side, and tell it how far
		// back over the body's border it has to reach to cover the join
		Gtk.StyleContext body_style = this.main_layout.get_style_context();
		Gtk.Border body_border = body_style.get_border(body_style.get_state());

		// Clear the room left for a previous panel position
		this.main_layout.margin_top = 0;
		this.main_layout.margin_bottom = 0;
		this.main_layout.margin_start = 0;
		this.main_layout.margin_end = 0;

		switch (position) {
			case Budgie.PanelPosition.TOP:
				this.main_layout.margin_top = MenuArrow.ARROW_DEPTH;
				this.arrow.overlap = body_border.top;
				break;
			case Budgie.PanelPosition.LEFT:
				this.main_layout.margin_start = MenuArrow.ARROW_DEPTH;
				this.arrow.overlap = body_border.left;
				break;
			case Budgie.PanelPosition.RIGHT:
				this.main_layout.margin_end = MenuArrow.ARROW_DEPTH;
				this.arrow.overlap = body_border.right;
				break;
			case Budgie.PanelPosition.BOTTOM:
			default:
				this.main_layout.margin_bottom = MenuArrow.ARROW_DEPTH;
				this.arrow.overlap = body_border.bottom;
				break;
		}

		// The menu may have been shifted to stay on the monitor; keep the arrow
		// within the body
		int offset = launcher_center - MenuArrow.ARROW_BREADTH / 2;
		int max_offset = menu_nat - MenuArrow.ARROW_BREADTH;
		if (max_offset < 0) max_offset = 0;
		if (offset > max_offset) offset = max_offset;
		if (offset < 0) offset = 0;

		// Clear the margin left by a previous panel position
		this.arrow.margin_top = 0;
		this.arrow.margin_start = 0;
		if (vertical) {
			this.arrow.halign = position == Budgie.PanelPosition.LEFT ? Gtk.Align.START : Gtk.Align.END;
			this.arrow.valign = Gtk.Align.START;
			this.arrow.margin_top = offset;
		} else {
			this.arrow.halign = Gtk.Align.START;
			this.arrow.valign = position == Budgie.PanelPosition.TOP ? Gtk.Align.START : Gtk.Align.END;
			this.arrow.margin_start = offset;
		}

		// The arrow's size request depends on position, so it must be renegotiated
		this.arrow.queue_resize();
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
