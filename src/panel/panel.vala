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

namespace Budgie {
	/**
	* The toplevel window for a panel. Placement, visibility and the applets
	* are handled by PanelPlacement, PanelVisibility and PanelApplets
	*/
	public class Panel : Budgie.Toplevel {
		MainPanel layout; // the styled panel box holding the regions
		Gtk.Box main_layout; // the window's only child: panel box plus shadow

		public Settings settings { construct set ; public get; } // this panel's GSettings, at a path derived from its uuid
		private unowned Budgie.PanelManager? manager; // for check_windows() and dconf resets
		private unowned Budgie.PanelPluginManager? plugin_manager; // loads plugins and creates applets

		PopoverManager? popover_manager; // every applet on this panel registers its popovers here

		Budgie.ShadowBlock shadow; // drop shadow on the panel's screen-facing side

		construct {
			position = PanelPosition.NONE; // the manager assigns the real edge through update_geometry()
		}

		ConstrainedBox? start_box; // region at the start of the edge
		ConstrainedBox? center_box; // region in the middle
		ConstrainedBox? end_box; // region at the end

		private PanelPlacement placement; // where the window sits and how big it is
		private PanelVisibility visibility; // shown, hidden, or sliding between the two
		private PanelApplets applets; // what is on the panel
		private Budgie.PanelAction pending_action; // set by activate_action, run from idle by invoke_pending_action

		public signal void usage_changed(); // in_use() may have changed; the manager ends a summon once no panel is in use

		/**
		* Builds the widget tree, then the helpers in dependency order, then
		* loads the applets. The window maps once they are in.
		*/
		public Panel(Budgie.PanelManager? manager, Budgie.PanelPluginManager? plugin_manager, string? uuid, Settings? settings) {
			Object(type_hint: Gdk.WindowTypeHint.DOCK, window_position: Gtk.WindowPosition.NONE, settings: settings, uuid: uuid);

			intended_size = settings.get_int(Budgie.PANEL_KEY_SIZE);
			intended_spacing = settings.get_int(Budgie.PANEL_KEY_SPACING);
			reserved_size = intended_size; // until the panel box is allocated and PanelPlacement learns the real thickness
			this.manager = manager;
			this.plugin_manager = plugin_manager;

			skip_taskbar_hint = true;
			skip_pager_hint = true;
			set_decorated(false);

			GtkLayerShell.init_for_window(this); // has to precede realization
			GtkLayerShell.set_layer(this, GtkLayerShell.Layer.TOP); // above normal windows, below fullscreen ones
			GtkLayerShell.set_keyboard_mode(this, GtkLayerShell.KeyboardMode.ON_DEMAND); // keyboard focus only while an applet asks for it

			popover_manager = new PopoverManager();
			visibility = new PanelVisibility(this, manager, popover_manager);
			visibility.usage_changed.connect(on_usage_changed);

			var vis = screen.get_rgba_visual(); // the panel draws with transparency
			if (vis == null) {
				warning("Compositing not available, things will Look Bad (TM)");
			} else {
				set_visual(vis);
			}
			resizable = false;
			app_paintable = true; // the background is ours to draw, including nothing at all while hidden
			get_style_context().add_class("budgie-container");

			main_layout = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			add(main_layout);

			layout = new MainPanel();
			layout.valign = Gtk.Align.FILL;
			layout.halign = Gtk.Align.FILL;

			main_layout.pack_start(layout, true, true, 0);
			main_layout.valign = Gtk.Align.START;

			shadow = new Budgie.ShadowBlock(this.position);
			shadow.hexpand = false;
			shadow.halign = Gtk.Align.FILL;
			shadow.show_all();
			main_layout.pack_start(shadow, false, false, 0); // PanelPlacement moves it to the screen-facing side

			this.settings.bind(Budgie.PANEL_KEY_SHADOW, shadow, "active", SettingsBindFlags.GET);
			this.settings.bind(Budgie.PANEL_KEY_DOCK_MODE, this, "dock-mode", SettingsBindFlags.DEFAULT);

			this.notify["dock-mode"].connect(this.update_dock_mode);
			layout.set_dock_mode(this.dock_mode);

			shadow_visible = this.settings.get_boolean(Budgie.PANEL_KEY_SHADOW);
			this.settings.bind(Budgie.PANEL_KEY_SHADOW, this, "shadow-visible", SettingsBindFlags.DEFAULT);

			start_box = new ConstrainedBox(Gtk.Orientation.HORIZONTAL, 2); // the regions; PanelPlacement re-orients and re-aligns them per edge
			start_box.halign = Gtk.Align.START;
			layout.pack_start(start_box, false, false, 0);

			center_box = new ConstrainedBox(Gtk.Orientation.HORIZONTAL, 2);
			layout.set_center_widget(center_box);

			end_box = new ConstrainedBox(Gtk.Orientation.HORIZONTAL, 2);
			layout.pack_end(end_box, false, false, 0);
			end_box.halign = Gtk.Align.END;

			placement = new PanelPlacement(this, main_layout, layout, shadow, start_box, center_box, end_box);
			notify["scale-factor"].connect(placement.apply);
			notify["targeted-size"].connect(placement.apply); // intended size or shadow visibility changed

			applets = new PanelApplets(this, manager, plugin_manager, settings, popover_manager, layout, start_box, center_box, end_box);
			applets.loaded.connect(on_applets_loaded);

			update_spacing();

			this.theme_regions = this.settings.get_boolean(Budgie.PANEL_KEY_REGIONS);
			this.notify["theme-regions"].connect(update_theme_regions);
			this.settings.bind(Budgie.PANEL_KEY_REGIONS, this, "theme-regions", SettingsBindFlags.DEFAULT);
			this.update_theme_regions();

			get_child().show_all();

			start_box.hide(); // regions stay hidden until an applet lands in them
			center_box.hide();
			end_box.hide();

			applets.load();
			update_dock_mode(); // first placement
		}

		/**
		* Places the window once it is realized
		*/
		public override void map() {
			base.map();
			placement.apply();
		}

		/**
		* GTK sizing comes from the placement so the widget tree agrees with
		* the layer-shell request
		*/
		public override void get_preferred_width(out int minimum_width, out int natural_width) {
			int width, height;
			placement.get_target_extents(out width, out height);

			minimum_width = width;
			natural_width = width;
		}

		/**
		* The other axis of get_preferred_width
		*/
		public override void get_preferred_height(out int minimum_height, out int natural_height) {
			int width, height;
			placement.get_target_extents(out width, out height);

			minimum_height = height;
			natural_height = height;
		}

		/**
		* The hidden and sliding states are painted by the visibility
		* controller; otherwise the widget tree draws as usual
		*/
		public override bool draw(Cairo.Context cr) {
			if (visibility.draw(cr)) {
				return Gdk.EVENT_STOP;
			}
			return base.draw(cr);
		}

		/**
		* The manager calls this on creation and whenever monitors change,
		* with the monitor's logical geometry at 0,0. Also persists size and
		* position.
		*/
		public void update_geometry(Gdk.Rectangle screen, PanelPosition position, int monitor_index = -1) {
			string old_class = Budgie.position_class_name(this.position);

			if (old_class != "") { // the theme styles each edge through a class named after it
				this.get_style_context().remove_class(old_class);
			}

			this.settings.set_int(Budgie.PANEL_KEY_SIZE, intended_size);
			this.get_style_context().add_class(Budgie.position_class_name(position));

			if (position != this.position) { // the applets flip their layout for a new edge
				this.position = position;
				this.set_position_setting(position);
				applets.update_positions();
			}

			this.shadow.position = position;
			placement.set_screen(screen, monitor_index);
			placement.apply();
			this.layout.queue_resize();
			queue_resize();
			queue_draw();
			applets.update_sizes();
		}

		/**
		* Persists the edge; the manager also calls this directly when it
		* moves a panel
		*/
		public void set_position_setting(PanelPosition position) {
			this.settings.set_enum(Budgie.PANEL_KEY_POSITION, position);
		}

		/**
		* dock-mode changed: restyle the panel box and re-place the window
		*/
		void update_dock_mode() {
			layout.set_dock_mode(this.dock_mode);
			placement.apply();
		}

		/**
		* Persists and applies the gap between applets, and between the regions
		*/
		public void update_spacing() {
			this.settings.set_int(Budgie.PANEL_KEY_SPACING, this.intended_spacing);

			layout.set_spacing(this.intended_spacing);
			start_box.set_spacing(this.intended_spacing);
			center_box.set_spacing(this.intended_spacing);
			end_box.set_spacing(this.intended_spacing);
		}

		/**
		* Optional classes so a theme can style the three regions separately
		*/
		void update_theme_regions() {
			if (this.theme_regions) {
				start_box.get_style_context().add_class("start-region");
				center_box.get_style_context().add_class("center-region");
				end_box.get_style_context().add_class("end-region");
			} else {
				start_box.get_style_context().remove_class("start-region");
				center_box.get_style_context().remove_class("center-region");
				end_box.get_style_context().remove_class("end-region");
			}
			this.queue_draw();
		}

		/**
		* ALWAYS and NONE apply directly; DYNAMIC asks the manager to look at
		* the windows, which calls set_transparent() back
		*/
		public void update_transparency(PanelTransparency transparency) {
			this.transparency = transparency;

			switch (transparency) {
				case PanelTransparency.ALWAYS:
					set_transparent(true);
					break;
				case PanelTransparency.DYNAMIC:
					manager.check_windows();
					break;
				default:
					set_transparent(false);
					break;
			}

			this.settings.set_enum(Budgie.PANEL_KEY_TRANSPARENCY, transparency);
		}

		/**
		* Toggles the theme's transparent styling on the panel box
		*/
		public void set_transparent(bool transparent) {
			layout.set_transparent(transparent);
		}

		/**
		* Persists the shadow toggle; the binding on shadow_visible resizes
		* the window
		*/
		public void update_shadow(bool visible) {
			this.shadow_visible = visible;

			this.settings.set_boolean(Budgie.PANEL_KEY_SHADOW, visible);
		}

		/**
		* Never reserves screen space again, Automatic and Intelligent release
		* it; the visibility controller then shows or hides to match
		*/
		public void set_autohide_policy(AutohidePolicy policy) {
			if (policy == autohide) {
				return;
			}
			settings.set_enum(Budgie.PANEL_KEY_AUTOHIDE, policy);
			autohide = policy;
			placement.update_layer_shell_properties();
			visibility.update();
		}

		/**
		* The manager's verdict on whether a window covers this panel's
		* monitor; it drives autohide
		*/
		public void set_occluded(bool occluded) {
			visibility.set_occluded(occluded);
		}

		/**
		* Brings the panel up for a keyboard-triggered action until dismiss()
		*/
		public void summon() {
			visibility.summon();
		}

		/**
		* Ends a summon and lets autohide decide again
		*/
		public void dismiss() {
			visibility.dismiss();
		}

		/**
		* Whether one of the panel's popovers is open or the pointer is on it
		*/
		public bool in_use() {
			return visibility.in_use;
		}

		/**
		* Whether autohide has slid the panel out
		*/
		public bool is_hidden() {
			return visibility.hidden;
		}

		/**
		* Re-emits PanelVisibility.usage_changed for the manager
		*/
		private void on_usage_changed() {
			usage_changed();
		}

		/**
		* Nothing animates or hides until the applets are in place
		*/
		private void on_applets_loaded() {
			visibility.start();
		}

		/**
		* Runs a panel keybinding action on the applet that supports it.
		* The manager summons the panels first, so the applet's popover does
		* not open under a hidden panel.
		*/
		public bool activate_action(int remote_action) {
			Budgie.PanelAction action = (Budgie.PanelAction)remote_action;
			unowned Budgie.AppletInfo? info = applets.find_supporting(action);
			if (info == null) {
				return false;
			}

			this.present();

			pending_action = action;
			Idle.add(invoke_pending_action); // let the show land before the applet grabs focus for its popover
			return true;
		}

		/**
		* Invokes the action queued by activate_action on the applet that
		* supports it
		*/
		private bool invoke_pending_action() {
			unowned Budgie.AppletInfo? info = applets.find_supporting(pending_action);
			if (info != null) {
				info.applet.invoke_action(pending_action);
			}
			return false;
		}

		/**
		* The Toplevel applet API forwards to PanelApplets; the settings UI
		* only sees Toplevel
		*/
		public override List<AppletInfo?> get_applets() {
			return applets.get_applets();
		}

		/**
		* Toplevel override, forwarded to PanelApplets
		*/
		public override void add_new_applet(string id) {
			applets.add_new_applet(id);
		}

		/**
		* Toplevel override, forwarded to PanelApplets
		*/
		public override void remove_applet(Budgie.AppletInfo? info) {
			applets.remove_applet(info);
		}

		/**
		* Toplevel override, forwarded to PanelApplets
		*/
		public override bool can_move_applet_left(Budgie.AppletInfo? info) {
			return applets.can_move_applet_left(info);
		}

		/**
		* Toplevel override, forwarded to PanelApplets
		*/
		public override bool can_move_applet_right(Budgie.AppletInfo? info) {
			return applets.can_move_applet_right(info);
		}

		/**
		* Toplevel override, forwarded to PanelApplets
		*/
		public override void move_applet_left(Budgie.AppletInfo? info) {
			applets.move_applet_left(info);
		}

		/**
		* Toplevel override, forwarded to PanelApplets
		*/
		public override void move_applet_right(Budgie.AppletInfo? info) {
			applets.move_applet_right(info);
		}

		/**
		* Manager, when no panel configuration exists yet
		*/
		public void create_default_layout(string name, KeyFile config) {
			applets.create_default_layout(name, config);
		}

		/**
		* Manager, when this panel is being deleted
		*/
		public void destroy_children() {
			applets.destroy_children();
		}

		/**
		* Manager, after the stored migration level turned out to be behind
		*/
		public void perform_migration(int current_migration_level) {
			applets.perform_migration(current_migration_level);
		}
	}
}
