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

using LibUUID;

namespace Budgie {
	/**
	* The main panel area - i.e. the bit that's rendered
	*/
	public class MainPanel : Gtk.Box {
		private bool updating_constraints = false;
		
		public MainPanel() {
			Object(orientation: Gtk.Orientation.HORIZONTAL);
			get_style_context().add_class("budgie-panel");
			get_style_context().add_class(Gtk.STYLE_CLASS_BACKGROUND);
		}

		public void set_transparent(bool transparent) {
			if (transparent) {
				get_style_context().add_class("transparent");
			} else {
				get_style_context().remove_class("transparent");
			}
		}

		public void set_dock_mode(bool dock_mode) {
			if (dock_mode) {
				get_style_context().add_class("dock-mode");
			} else {
				get_style_context().remove_class("dock-mode");
			}
		}

		public void update_box_constraints(Gtk.Allocation allocation) {
			// Prevent infinite recursion
			if (updating_constraints) {
				return;
			}
			updating_constraints = true;
			
			// Constrain each box to panel size minus other boxes' sizes
			if (get_orientation() == Gtk.Orientation.HORIZONTAL) {
				// Find start, center, and end boxes by their halign
				Gtk.Widget? start_widget = null;
				Gtk.Widget? center_widget = null;
				Gtk.Widget? end_widget = null;
				
				foreach (var child in get_children()) {
					var halign = child.get_halign();
					if (halign == Gtk.Align.START) {
						start_widget = child;
					} else if (halign == Gtk.Align.CENTER) {
						center_widget = child;
					} else if (halign == Gtk.Align.END) {
						end_widget = child;
					}
				}
				
				// Get current allocations
				Gtk.Allocation start_alloc = Gtk.Allocation();
				Gtk.Allocation center_alloc = Gtk.Allocation();
				Gtk.Allocation end_alloc = Gtk.Allocation();
				
				if (start_widget != null) {
					start_widget.get_allocation(out start_alloc);
				}
				if (center_widget != null) {
					center_widget.get_allocation(out center_alloc);
				}
				if (end_widget != null) {
					end_widget.get_allocation(out end_alloc);
				}
				
				// Constrain each box: max = panel_size - sum of other boxes' sizes
				if (start_widget != null) {
					int other_boxes_size = center_alloc.width + end_alloc.width;
					int max_start_width = int.max(0, allocation.width - other_boxes_size);
					if (start_alloc.width > max_start_width) {
						start_alloc.width = max_start_width;
						start_widget.size_allocate(start_alloc);
					}
				}
				
				if (center_widget != null) {
					int other_boxes_size = start_alloc.width + end_alloc.width;
					int max_center_width = int.max(0, allocation.width - other_boxes_size);
					if (center_alloc.width > max_center_width) {
						center_alloc.width = max_center_width;
						center_widget.size_allocate(center_alloc);
					}
				}
				
				if (end_widget != null) {
					int other_boxes_size = start_alloc.width + center_alloc.width;
					int max_end_width = int.max(0, allocation.width - other_boxes_size);
					if (end_alloc.width > max_end_width) {
						end_alloc.width = max_end_width;
						end_widget.size_allocate(end_alloc);
					}
				}
			} else {
				// Vertical layout - same logic but for height
				Gtk.Widget? start_widget = null;
				Gtk.Widget? center_widget = null;
				Gtk.Widget? end_widget = null;
				
				foreach (var child in get_children()) {
					var valign = child.get_valign();
					if (valign == Gtk.Align.START) {
						start_widget = child;
					} else if (valign == Gtk.Align.CENTER) {
						center_widget = child;
					} else if (valign == Gtk.Align.END) {
						end_widget = child;
					}
				}
				
				Gtk.Allocation start_alloc = Gtk.Allocation();
				Gtk.Allocation center_alloc = Gtk.Allocation();
				Gtk.Allocation end_alloc = Gtk.Allocation();
				
				if (start_widget != null) {
					start_widget.get_allocation(out start_alloc);
				}
				if (center_widget != null) {
					center_widget.get_allocation(out center_alloc);
				}
				if (end_widget != null) {
					end_widget.get_allocation(out end_alloc);
				}
				
				if (start_widget != null) {
					int other_boxes_size = center_alloc.height + end_alloc.height;
					int max_start_height = int.max(0, allocation.height - other_boxes_size);
					if (start_alloc.height > max_start_height) {
						start_alloc.height = max_start_height;
						start_widget.size_allocate(start_alloc);
					}
				}
				
				if (center_widget != null) {
					int other_boxes_size = start_alloc.height + end_alloc.height;
					int max_center_height = int.max(0, allocation.height - other_boxes_size);
					if (center_alloc.height > max_center_height) {
						center_alloc.height = max_center_height;
						center_widget.size_allocate(center_alloc);
					}
				}
				
				if (end_widget != null) {
					int other_boxes_size = start_alloc.height + center_alloc.height;
					int max_end_height = int.max(0, allocation.height - other_boxes_size);
					if (end_alloc.height > max_end_height) {
						end_alloc.height = max_end_height;
						end_widget.size_allocate(end_alloc);
					}
				}
			}
			updating_constraints = false;
		}
	}

	/**
	* This is used to track panel animations, i.e. within the toplevel
	* itself to provide dock like behavior
	*/
	public enum PanelAnimation {
		NONE = 0,
		SHOW,
		HIDE
	}

	public GtkLayerShell.Edge panel_position_to_layer_shell_edge(Budgie.PanelPosition position) {
		switch (position) {
			case PanelPosition.TOP:
				return GtkLayerShell.Edge.TOP;
			case PanelPosition.LEFT:
				return GtkLayerShell.Edge.LEFT;
			case PanelPosition.RIGHT:
				return GtkLayerShell.Edge.RIGHT;
			case PanelPosition.BOTTOM:
			case PanelPosition.NONE: // Note: NONE will never actually be hit because of checks where we are calling this function
				return GtkLayerShell.Edge.BOTTOM;
		}
		return GtkLayerShell.Edge.BOTTOM;
	}

	/**
	* The toplevel window for a panel
	*/
	public class Panel : Budgie.Toplevel {
		MainPanel layout;
		Gtk.Box main_layout;
		Gdk.Rectangle orig_scr;

		public Settings settings { construct set ; public get; }
		private unowned Budgie.PanelManager? manager;
		private unowned Budgie.PanelPluginManager? plugin_manager;

		PopoverManager? popover_manager;

		Budgie.ShadowBlock shadow;

		HashTable<string,HashTable<string,string>> pending = null;
		HashTable<string,HashTable<string,string>> creating = null;
		HashTable<string,Budgie.AppletInfo?> applets = null;

		HashTable<string,Budgie.AppletInfo?> initial_config = null;

		List<string?> expected_uuids;

		construct {
			position = PanelPosition.NONE;
		}

		/* Multiplier for strut operations on hi-dpi */
		int scale = 1;

		/* Box for the start of the panel */
		ConstrainedBox? start_box;
		/* Box for the center of the panel */
		ConstrainedBox? center_box;
		/* Box for the end of the panel */
		ConstrainedBox? end_box;

		int[] icon_sizes = {
			16, 24, 32, 48, 96, 128, 256
		};

		int current_icon_size;
		int current_small_icon_size;

		/* Track initial load */
		private bool is_fully_loaded = false;
		private bool need_migratory = false;

		public signal void panel_loaded();

		/* Animation tracking */
		private double render_scale = 0.0;
		private PanelAnimation animation = PanelAnimation.SHOW;
		private bool allow_animation = false;
		private bool screen_occluded = false;

		public double nscale {
			public set {
				render_scale = value;
				queue_draw();
			}
			public get {
				return render_scale;
			}
		}

		public bool activate_action(int remote_action) {
			unowned string? uuid = null;
			unowned Budgie.AppletInfo? info = null;

			Budgie.PanelAction action = (Budgie.PanelAction)remote_action;

			var iter = HashTableIter<string?,Budgie.AppletInfo?>(applets);
			while (iter.next(out uuid, out info)) {
				if ((info.applet.supported_actions & action) != 0) {
					this.present();
					set_occluded(false);
					this.set_above_other_surfaces(); // Ensure the surface is above others before we invoke the action

					Idle.add(() => {
						info.applet.invoke_action(action);
						return false;
					});
					return true;
				}
			}
			return false;
		}

		/**
		* Force update the geometry
		*/
		public void update_geometry(Gdk.Rectangle screen, PanelPosition position, int size = 0) {
			this.orig_scr = screen;
			string old_class = Budgie.position_class_name(this.position);

			if (old_class != "") {
				this.get_style_context().remove_class(old_class);
			}

			if (size == 0) {
				size = intended_size;
			}

			this.settings.set_int(Budgie.PANEL_KEY_SIZE, size);
			this.intended_size = size;
			this.get_style_context().add_class(Budgie.position_class_name(position));

			// Check if the position has been altered and notify our applets
			if (position != this.position) {
				this.position = position;
				this.set_position_setting(position);
				this.update_positions();
			}

			this.shadow.position = position;
			this.update_layer_shell_props();
			this.layout.queue_resize();
			queue_resize();
			queue_draw();
			placement();
			update_sizes();
		}

		public void set_position_setting(PanelPosition position) {
			this.settings.set_enum(Budgie.PANEL_KEY_POSITION, position);
		}

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

		public void set_transparent(bool transparent) {
			layout.set_transparent(transparent);
		}

		public void update_shadow(bool visible) {
			this.shadow_visible = visible;

			this.settings.set_boolean(Budgie.PANEL_KEY_SHADOW, visible);
		}

		/**
		* Specific for docks, regardless of transparency, and determines
		* how our "screen blocked by thingy" policy works.
		*/
		public void set_occluded(bool occluded) {
			this.screen_occluded = occluded;
			if (this.autohide == AutohidePolicy.NONE) {
				return;
			}
			this.update_exclusive_zone();
		}

		public override List<AppletInfo?> get_applets() {
			List<Budgie.AppletInfo?> ret = new List<Budgie.AppletInfo?>();
			unowned string? key = null;
			unowned Budgie.AppletInfo? appl_info = null;

			var iter = HashTableIter<string,Budgie.AppletInfo?>(applets);
			while (iter.next(out key, out appl_info)) {
				ret.append(appl_info);
			}
			return ret;
		}

		/**
		* Loop the applets, performing a reparent or reposition
		*/
		private void initial_applet_placement(bool repar = false, bool repos = false) {
			if (!repar && !repos) {
				return;
			}
			unowned string? uuid = null;
			unowned Budgie.AppletInfo? info = null;

			var iter = HashTableIter<string?,Budgie.AppletInfo?>(applets);

			while (iter.next(out uuid, out info)) {
				if (repar) {
					applet_reparent(info);
				}
				if (repos) {
					applet_reposition(info);
				}
			}
		}

		/* Handle being "fully" loaded */
		private void on_fully_loaded() {
			if (applets.size() < 1) {
				if (!initial_anim) {
					Idle.add(initial_animation);
				}
				return;
			}

			/* All applets loaded and positioned, now re-sort them */
			initial_applet_placement(true, false);
			initial_applet_placement(false, true);

			/* Let everyone else know we're in business */
			applets_changed();
			if (!initial_anim) {
				Idle.add(initial_animation);
			}
			lock (need_migratory) {
				if (!need_migratory) {
					return;
				}
			}
			/* In half a second, add_migratory so the user sees them added */
			Timeout.add(500, add_migratory);
		}

		public Panel(Budgie.PanelManager? manager, Budgie.PanelPluginManager? plugin_manager, string? uuid, Settings? settings) {
			Object(type_hint: Gdk.WindowTypeHint.DOCK, window_position: Gtk.WindowPosition.NONE, settings: settings, uuid: uuid);

			initial_config = new HashTable<string,Budgie.AppletInfo>(str_hash, str_equal);

			intended_size = settings.get_int(Budgie.PANEL_KEY_SIZE);
			intended_spacing = settings.get_int(Budgie.PANEL_KEY_SPACING);
			this.manager = manager;
			this.plugin_manager = plugin_manager;

			skip_taskbar_hint = true;
			skip_pager_hint = true;
			set_decorated(false);

			scale = get_scale_factor();
			nscale = 1.0;

			// Respond to a scale factor change
			notify["scale-factor"].connect(() => {
				this.scale = get_scale_factor();
				this.placement();
			});

			if (Xfw.windowing_get() == Xfw.Windowing.WAYLAND) {
				GtkLayerShell.init_for_window(this);
				set_above_other_surfaces();
				GtkLayerShell.set_keyboard_mode(this, GtkLayerShell.KeyboardMode.ON_DEMAND);
			}

			popover_manager = new PopoverManager();
			pending = new HashTable<string,HashTable<string,string>>(str_hash, str_equal);
			creating = new HashTable<string,HashTable<string,string>>(str_hash, str_equal);
			applets = new HashTable<string,Budgie.AppletInfo?>(str_hash, str_equal);
			expected_uuids = new List<string?>();
			panel_loaded.connect(on_fully_loaded);

			var vis = screen.get_rgba_visual();
			if (vis == null) {
				warning("Compositing not available, things will Look Bad (TM)");
			} else {
				set_visual(vis);
			}
			resizable = false;
			app_paintable = true;
			get_style_context().add_class("budgie-container");

			main_layout = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			add(main_layout);

			layout = new MainPanel();
			layout.valign = Gtk.Align.FILL;
			layout.halign = Gtk.Align.FILL;

			main_layout.pack_start(layout, true, true, 0);
			main_layout.valign = Gtk.Align.START;

			/* Shadow.. */
			shadow = new Budgie.ShadowBlock(this.position);
			shadow.hexpand = false;
			shadow.halign = Gtk.Align.FILL;
			shadow.show_all();
			main_layout.pack_start(shadow, false, false, 0);

			this.settings.bind(Budgie.PANEL_KEY_SHADOW, shadow, "active", SettingsBindFlags.GET);
			this.settings.bind(Budgie.PANEL_KEY_DOCK_MODE, this, "dock-mode", SettingsBindFlags.DEFAULT);

			this.notify["dock-mode"].connect(this.update_dock_mode);
			layout.set_dock_mode(this.dock_mode);

			shadow_visible = this.settings.get_boolean(Budgie.PANEL_KEY_SHADOW);
			this.settings.bind(Budgie.PANEL_KEY_SHADOW, this, "shadow-visible", SettingsBindFlags.DEFAULT);

			/* Assign our applet holder boxes */
			start_box = new ConstrainedBox(Gtk.Orientation.HORIZONTAL, 2);
			start_box.halign = Gtk.Align.START;
			layout.pack_start(start_box, false, false, 0);
			center_box = new ConstrainedBox(Gtk.Orientation.HORIZONTAL, 2);
			layout.set_center_widget(center_box);
			end_box = new ConstrainedBox(Gtk.Orientation.HORIZONTAL, 2);
			layout.pack_end(end_box, false, false, 0);
			end_box.halign = Gtk.Align.END;
			update_spacing();

			this.theme_regions = this.settings.get_boolean(Budgie.PANEL_KEY_REGIONS);
			this.notify["theme-regions"].connect(update_theme_regions);
			this.settings.bind(Budgie.PANEL_KEY_REGIONS, this, "theme-regions", SettingsBindFlags.DEFAULT);
			this.update_theme_regions();

			this.enter_notify_event.connect(on_enter_notify);
			this.leave_notify_event.connect(on_leave_notify);

			get_child().show_all();

			// Immediately hide our inner boxes
			start_box.hide();
			center_box.hide();
			end_box.hide();

			this.plugin_manager.extension_loaded.connect_after(this.on_extension_loaded);

			/* bit of a no-op. */
			update_sizes();
			load_applets();
			update_dock_mode();
		}

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

		void update_layer_shell_props() {
			var default_display = Gdk.Display.get_default();
			if (default_display != null) {
				var monitor = default_display.get_primary_monitor();
				if (monitor != null) GtkLayerShell.set_monitor(this, monitor);
			}

			GtkLayerShell.set_anchor(
				this,
				Budgie.panel_position_to_layer_shell_edge(this.position),
				true
			);

			// Update the exclusive zone based on the autohide policy
			this.update_exclusive_zone();
		}

		void update_exclusive_zone() {
			// If our panel is set to intelligent autohide and the screen is occluded, we want to ensure there is no exclusive zone and the panel goes behind other surfaces
			if (this.autohide == AutohidePolicy.INTELLIGENT && screen_occluded) {
				GtkLayerShell.set_exclusive_zone(this, 0);
				set_below_other_surfaces();
			} else {
				GtkLayerShell.set_exclusive_zone(this, this.intended_size);
				set_above_other_surfaces();
			}
		}

		void update_sizes() {
			int size = icon_sizes[0];
			int small_size = icon_sizes[0];

			unowned string? key = null;
			unowned Budgie.AppletInfo? info = null;

			for (int i = 1; i < icon_sizes.length; i++) {
				if (icon_sizes[i] > intended_size) {
					break;
				}
				size = icon_sizes[i];
				small_size = icon_sizes[i-1];
			}

			this.current_icon_size = size;
			this.current_small_icon_size = small_size;

			var iter = HashTableIter<string?,Budgie.AppletInfo?>(applets);
			while (iter.next(out key, out info)) {
				info.applet.panel_size_changed(intended_size, size, small_size);
			}
		}

		void update_positions() {
			unowned string? key = null;
			unowned Budgie.AppletInfo? info = null;

			var iter = HashTableIter<string?,Budgie.AppletInfo?>(applets);
			while (iter.next(out key, out info)) {
				info.applet.panel_position_changed(this.position);
			}
		}

		public void update_spacing() {
			this.settings.set_int(Budgie.PANEL_KEY_SPACING, this.intended_spacing);

			layout.set_spacing(this.intended_spacing);
			start_box.set_spacing(this.intended_spacing);
			center_box.set_spacing(this.intended_spacing);
			end_box.set_spacing(this.intended_spacing);
		}

		public void destroy_children() {
			unowned string key;
			unowned AppletInfo? info;

			var iter = HashTableIter<string?,AppletInfo?>(applets);
			while (iter.next(out key, out info)) {
				Settings? app_settings = info.applet.get_applet_settings(info.uuid);
				if (app_settings != null) {
					app_settings.ref();
				}

				// Stop it screaming when it dies
				ulong notify_id = info.get_data("notify_id");

				SignalHandler.disconnect(info, notify_id);
				info.applet.get_parent().remove(info.applet);

				// Clean up the settings
				this.manager.reset_dconf_path(info.settings);

				// Nuke it's own settings
				if (app_settings != null) {
					this.manager.reset_dconf_path(app_settings);
				}
			}
		}

		void on_extension_loaded(string name) {
			unowned HashTable<string,string>? todo = null;
			todo = pending.lookup(name);
			if (todo != null) {
				var iter = HashTableIter<string,string>(todo);
				string? uuid = null;

				while (iter.next(out uuid, null)) {
					Budgie.AppletInfo? info = null;
					string? uname = null;
					try {
						info = this.plugin_manager.load_applet_instance(uuid, null, out uname);
						add_applet(info);
					} catch (Error e) {
						critical("Failed to load applet when we know it exists: %s", uname);
					}
				}
				pending.remove(name);
			}

			todo = null;

			todo = creating.lookup(name);
			if (todo != null) {
				var iter = HashTableIter<string,string>(todo);
				string? uuid = null;

				while (iter.next(out uuid, null)) {
					Budgie.AppletInfo? info = null;

					try {
						info = this.plugin_manager.create_applet(name, uuid);
						this.add_applet(info);
						/* this.configure_applet(info); */
					} catch (Error e) {
						critical("Failed to load applet when we know it exists");
					}
				}
				creating.remove(name);
			}
		}

		/**
		* Load all pre-configured applets
		*/
		void load_applets() {
			string[]? applets = settings.get_strv(Budgie.PANEL_KEY_APPLETS);
			if (applets == null || applets.length == 0) {
				this.panel_loaded();
				this.is_fully_loaded = true;
				return;
			}

			CompareFunc<Budgie.AppletInfo?> infocmp = (a, b) => {
				return (int) (a.position > b.position) - (int) (a.position < b.position);
			};

			lock (expected_uuids) {
				for (int i = 0; i < applets.length; i++) {
					this.expected_uuids.append(applets[i]);
				}

				var start_applets = new List<Budgie.AppletInfo?>();
				var center_applets = new List<Budgie.AppletInfo?>();
				var end_applets = new List<Budgie.AppletInfo?>();

				for (int i = 0; i < applets.length; i++) {
					string? name = null;
					Budgie.AppletInfo? info = null;

					try {
						info = this.plugin_manager.load_applet_instance(applets[i], null, out name);
					} catch (Error e) {
						if (name == null) {
							unowned List<string?> g = expected_uuids.find_custom(applets[i], strcmp);

							if (g != null) {
								expected_uuids.remove_link(g);
							}

							message("Unable to load invalid applet '%s': %s", applets[i], e.message);
							applet_removed(applets[i]);

							continue;
						} else {
							info = this.add_pending(applets[i], name);

							if (info == null) {
								continue;
							}
						}
					}

					if (info.alignment == "start") {
						start_applets.insert_sorted(info, infocmp);
					} else if (info.alignment == "center") {
						center_applets.insert_sorted(info, infocmp);
					} else {
						end_applets.insert_sorted(info, infocmp);
					}
				}

				for (int i = 0; i < start_applets.length(); i++) {
					start_applets.nth_data(i).position = i;
					add_applet(start_applets.nth_data(i));
				}
				for (int i = 0; i < center_applets.length(); i++) {
					center_applets.nth_data(i).position = i;
					add_applet(center_applets.nth_data(i));
				}
				for (int i = 0; i < end_applets.length(); i++) {
					end_applets.nth_data(i).position = i;
					add_applet(end_applets.nth_data(i));
				}
			}
		}

		/**
		* Add a new applet to the panel (Raven UI)
		*
		* Explanation: Try to find the most underpopulated region first,
		* and add the applet there. Determine a suitable position,
		* set the alignment+position, stuff an initial config in,
		* and hope for the best when we initiate add_new
		*
		* If the @target_region is set, we'll use that instead
		*/
		private void add_new_applet_at(string id, Gtk.Box? target_region) {
			/* First, determine a panel to place this guy */
			int position = (int) applets.size() + 1;
			unowned Gtk.Box? target = null;
			string? align = null;
			AppletInfo? info = null;
			string? uuid = null;

			Gtk.Box?[] regions = {
				start_box,
				center_box,
				end_box
			};

			/* Use the requested target_region for internal migration adds */
			if (target_region != null) {
				var kids = target_region.get_children();
				position = (int) (kids.length());
				target = target_region;
			} else {
				/* No region specified, find the first available slot */
				foreach (var region in regions) {
					var kids = region.get_children();
					var len = kids.length();
					if (len < position) {
						position = (int)len;
						target = region;
					}
				}
			}

			if (target == start_box) {
				align = "start";
			} else if (target == center_box) {
				align = "center";
			} else {
				align = "end";
			}

			uuid = LibUUID.new(UUIDFlags.LOWER_CASE|UUIDFlags.TIME_SAFE_TYPE);
			info = new AppletInfo.from_uuid(uuid);
			info.alignment = align;

			/* Safety clamp */
			var kids = target.get_children();
			uint nkids = kids.length();

			if (position >= nkids) {
				position = (int) nkids;
			}

			if (position < 0) {
				position = 0;
			}

			info.position = position;

			initial_config.insert(uuid, info);
			add_new(id, uuid);
		}

		/**
		* Add a new applet to the panel (Raven UI)
		*/
		public override void add_new_applet(string id) {
			add_new_applet_at(id, null);
		}

		public void create_default_layout(string name, KeyFile config) {
			int s_index = -1;
			int c_index = -1;
			int e_index = -1;
			int index = 0;

			try {
				if (!config.has_key(name, "Children")) {
					warning("Config for panel %s does not specify applets", name);
					return;
				}
				string[] applets = config.get_string_list(name, "Children");
				foreach (string appl in applets) {
					AppletInfo? info = null;
					string? uuid = null;
					appl = appl.strip();
					string alignment = "start"; /* center, end */

					if (!config.has_group(appl)) {
						warning("Panel applet %s missing from config", appl);
						continue;
					}

					if (!config.has_key(appl, "ID")) {
						warning("Applet %s is missing ID", appl);
						continue;
					}

					uuid = LibUUID.new(UUIDFlags.LOWER_CASE|UUIDFlags.TIME_SAFE_TYPE);

					var id = config.get_string(appl, "ID").strip();
					if (uuid == null || uuid.strip() == "") {
						warning("Could not add new applet %s from config %s", id, name);
						continue;
					}

					info = new AppletInfo.from_uuid(uuid);
					if (config.has_key(appl, "Alignment")) {
						alignment = config.get_string(appl, "Alignment").strip();
					}

					switch (alignment) {
						case "center":
							index = ++c_index;
							break;
						case "end":
							index = ++e_index;
							break;
						default:
							index = ++s_index;
							break;
					}
					info.alignment = alignment;
					info.position = index;

					initial_config.insert(uuid, info);
					add_new(id, uuid);
				}
			} catch (Error e) {
				warning("Error loading default config: %s", e.message);
			}
		}

		// toggle_container_visibilities is used to toggle the visibility of a panel container (start, center, end) based on if it has children
		void toggle_container_visibilities() {
			Gtk.Box?[] regions = { start_box, center_box, end_box };

			for (var i = 0; i < regions.length; i++) {
				Gtk.Box region = regions[i];

				if (!region.get_children().is_empty()) { // If this has a child
					if (!region.get_visible()) { // Not already visible
						region.show(); // Ensure we show the panel specifically. Using show_all results in hidden widgets of children being shown, like Budgie Menu label. Only happens in weird cases like reset.
						region.queue_draw(); // Ensure we queue a draw
					}
				} else {
					region.hide(); // Hide this area
				}
			}
		}

		void set_applets() {
			string[]? uuids = null;
			unowned string? uuid = null;
			unowned Budgie.AppletInfo? plugin = null;

			var iter = HashTableIter<string,Budgie.AppletInfo?>(applets);
			while (iter.next(out uuid, out plugin)) {
				uuids += uuid;
			}

			settings.set_strv(Budgie.PANEL_KEY_APPLETS, uuids);
		}

		public override void remove_applet(Budgie.AppletInfo? info) {
			if (info == null) {
				return;
			}

			int position = info.position;
			string alignment = info.alignment;
			string uuid = info.uuid;

			ulong notify_id = info.get_data("notify_id");

			SignalHandler.disconnect(info, notify_id);
			Gtk.Box applet_parent = (Gtk.Box) info.applet.get_parent();
			applet_parent.remove(info.applet);
			toggle_container_visibilities();

			Settings? app_settings = info.applet.get_applet_settings(uuid);
			if (app_settings != null) {
				app_settings.ref();
			}

			this.manager.reset_dconf_path(info.settings);

			/* TODO: Add refcounting and unload unused plugins. */
			applets.remove(uuid);
			applet_removed(uuid);

			if (app_settings != null) {
				this.manager.reset_dconf_path(app_settings);
			}

			set_applets();
			budge_em_left(alignment, position);
		}

		void add_applet(Budgie.AppletInfo? info) {
			unowned Gtk.Box? pack_target = null;
			Budgie.AppletInfo? initial_info = null;

			initial_info = initial_config.lookup(info.uuid);
			if (initial_info != null) {
				info.alignment = initial_info.alignment;
				info.position = initial_info.position;
				initial_config.remove(info.uuid);
			}

			if (!this.is_fully_loaded) {
				lock (expected_uuids) {
					unowned List<string?> exp_fin = expected_uuids.find_custom(info.uuid, strcmp);
					if (exp_fin != null) {
						expected_uuids.remove_link(exp_fin);
					}
				}
			}

			/* figure out the alignment */
			switch (info.alignment) {
				case "start":
					pack_target = start_box;
					break;
				case "end":
					pack_target = end_box;
					break;
				default:
					pack_target = center_box;
					break;
			}

			this.applets.insert(info.uuid, info);
			this.set_applets();

			info.applet.update_popovers(this.popover_manager);
			info.applet.panel_size_changed(intended_size, this.current_icon_size, this.current_small_icon_size);
			info.applet.panel_position_changed(this.position);
			pack_target.pack_start(info.applet, false, false, 0);

			pack_target.child_set(info.applet, "position", info.position);
			toggle_container_visibilities(); // Ensure container is updated

			ulong id = info.notify.connect(applet_updated);
			info.set_data("notify_id", id);
			this.applet_added(info);

			if (this.is_fully_loaded) {
				return;
			}

			lock (expected_uuids) {
				if (expected_uuids.is_empty()) {
					this.is_fully_loaded = true;
					this.panel_loaded();
				}
			}
		}

		void applet_reparent(Budgie.AppletInfo? info) {
			/* Handle being reparented. */
			unowned Gtk.Box? new_parent = null;
			switch (info.alignment) {
				case "start":
					new_parent = this.start_box;
					break;
				case "end":
					new_parent = this.end_box;
					break;
				default:
					new_parent = this.center_box;
					break;
			}
			/* Don't needlessly reparent */
			Gtk.Box current_parent = (Gtk.Box) info.applet.get_parent();
			if (new_parent != current_parent) {
			current_parent.remove(info.applet);
			new_parent.add(info.applet);

			toggle_container_visibilities(); // Update the containers

				info.applet.queue_resize();
				update_sizes();
				update_box_size_constraints();
			}
		}

		void applet_reposition(Budgie.AppletInfo? info) {
			info.applet.get_parent().child_set(info.applet, "position", info.position);
			toggle_container_visibilities(); // Update the containers
		}

		void update_box_size_constraints() {
			// Force boxes to recalculate preferred sizes
			start_box.queue_resize();
			center_box.queue_resize();
			end_box.queue_resize();
			layout.queue_resize();
			
			// Use a timeout to ensure allocations are updated before constraining
			Timeout.add(10, () => {
				Gtk.Allocation layout_alloc;
				layout.get_allocation(out layout_alloc);
				layout.update_box_constraints(layout_alloc);
				return false;
			});
		}

		void applet_updated(Object o, ParamSpec p) {
			unowned AppletInfo? info = o as AppletInfo;

			/* Prevent a massive amount of resorting */
			if (!this.is_fully_loaded) {
				return;
			}

			if (p.name == "alignment") {
				applet_reparent(info);
			} else if (p.name == "position") {
				applet_reposition(info);
			}
			this.applets_changed();
		}

		void add_new(string plugin_name, string? initial_uuid = null) {
			string? uuid = null;
			unowned HashTable<string,string>? table = null;

			if (!this.plugin_manager.is_plugin_valid(plugin_name)) {
				warning("Not loading invalid plugin: %s", plugin_name);
				return;
			}
			if (initial_uuid == null) {
				uuid = LibUUID.new(UUIDFlags.LOWER_CASE|UUIDFlags.TIME_SAFE_TYPE);
			} else {
				uuid = initial_uuid;
			}

			if (!this.plugin_manager.is_plugin_loaded(plugin_name)) {
				/* Request a load of the new guy */
				table = creating.lookup(plugin_name);
				if (table != null) {
					if (!table.contains(uuid)) {
						table.insert(uuid, uuid);
					}
					return;
				}
				/* Looks insane but avoids copies */
				creating.insert(plugin_name, new HashTable<string,string>(str_hash, str_equal));
				table = creating.lookup(plugin_name);
				table.insert(uuid, uuid);
				this.plugin_manager.modprobe(plugin_name);
				return;
			}
			/* Already exists */
			try {
				Budgie.AppletInfo? info = this.plugin_manager.create_applet(plugin_name, uuid);
				this.add_applet(info);
			} catch (Error e) {
				critical("Failed to load applet when we know it exists");
				return;
			}
		}

		Budgie.AppletInfo? add_pending(string uuid, string plugin_name) {
			string? rname = null;
			unowned HashTable<string,string>? table = null;

			if (!this.plugin_manager.is_plugin_valid(plugin_name)) {
				warning("Not adding invalid plugin: %s %s", plugin_name, uuid);
				return null;
			}

			if (!this.plugin_manager.is_plugin_loaded(plugin_name)) {
				/* Request a load of the new guy */
				table = pending.lookup(plugin_name);
				if (table != null) {
					if (!table.contains(uuid)) {
						table.insert(uuid, uuid);
					}
					return null;
				}
				/* Looks insane but avoids copies */
				pending.insert(plugin_name, new HashTable<string,string>(str_hash, str_equal));
				table = pending.lookup(plugin_name);
				table.insert(uuid, uuid);
				this.plugin_manager.modprobe(plugin_name);
				return null;
			}

			/* Already exists */
			Budgie.AppletInfo? info = null;

			try {
				info = this.plugin_manager.load_applet_instance(uuid, null, out rname);
			} catch (Error e) {
				critical("Failed to load applet when we know it exists");
			}

			return info;
		}

		public override void map() {
			base.map();
			placement();
		}

		public void set_autohide_policy(AutohidePolicy policy) {
			if (policy != this.autohide) {
				this.settings.set_enum(Budgie.PANEL_KEY_AUTOHIDE, policy);
				this.autohide = policy;
				this.update_layer_shell_props();
			}
		}

		/**
		* Update the internal representation of the panel based on whether
		* we're in dock mode or not
		*/
		void update_dock_mode() {
			layout.set_dock_mode(this.dock_mode);
			this.placement();
		}

		void placement() {
			this.update_layer_shell_props();
			bool horizontal = false;
			Gtk.Allocation alloc;
			main_layout.get_allocation(out alloc);

			int width = 0, height = 0;
			int x = 0, y = 0;
			int shadow_position = 0;

			// Get monitor geometry to constrain panel size
			Gdk.Rectangle monitor_geom = orig_scr;
			var screen = get_screen();
			if (screen != null) {
				var display = screen.get_display();
				if (display != null) {
					var monitor = display.get_primary_monitor();
					if (monitor != null) {
						monitor_geom = monitor.get_geometry();
					}
				}
			}

			// Constrain orig_scr to monitor dimensions
			int max_width = monitor_geom.width;
			int max_height = monitor_geom.height;
			
			switch (position) {
				case Budgie.PanelPosition.TOP:
					x = orig_scr.x;
					y = orig_scr.y;
					width = int.min(orig_scr.width, max_width);
					height = intended_size;
					shadow_position = 1;
					horizontal = true;
					break;
				case Budgie.PanelPosition.LEFT:
					x = orig_scr.x;
					y = orig_scr.y;
					width = intended_size;
					height = int.min(orig_scr.height, max_height);
					shadow_position = 1;
					break;
				case Budgie.PanelPosition.RIGHT:
					x = (orig_scr.x + orig_scr.width) - alloc.width;
					y = orig_scr.y;
					width = intended_size;
					height = int.min(orig_scr.height, max_height);
					shadow_position = 0;
					break;
				case Budgie.PanelPosition.BOTTOM:
				default:
					x = orig_scr.x;
					y = orig_scr.y + (orig_scr.height - alloc.height);
					width = int.min(orig_scr.width, max_width);
					height = intended_size;
					shadow_position = 0;
					horizontal = true;
					break;
			}

			// Special considerations for dock mode
			if (this.dock_mode) {
				if (horizontal) {
					if (alloc.width > max_width) {
						width = max_width;
					} else {
						width = 100;
					}
				} else {
					if (alloc.height > max_height) {
						height = max_height;
					} else {
						height = 100;
					}
				}
			}

			// Ensure width and height don't exceed monitor dimensions
			width = int.min(width, max_width);
			height = int.min(height, max_height);

			main_layout.child_set(shadow, "position", shadow_position);

			if (horizontal) {
				start_box.halign = Gtk.Align.START;
				center_box.halign = Gtk.Align.CENTER;
				end_box.halign = Gtk.Align.END;

				start_box.valign = Gtk.Align.FILL;
				center_box.valign = Gtk.Align.FILL;
				end_box.valign = Gtk.Align.FILL;

				start_box.set_orientation(Gtk.Orientation.HORIZONTAL);
				center_box.set_orientation(Gtk.Orientation.HORIZONTAL);
				end_box.set_orientation(Gtk.Orientation.HORIZONTAL);
				layout.set_orientation(Gtk.Orientation.HORIZONTAL);

				main_layout.set_orientation(Gtk.Orientation.VERTICAL);
				main_layout.valign = Gtk.Align.FILL;
				if (this.dock_mode) {
					main_layout.halign = Gtk.Align.CENTER;
				} else {
					main_layout.halign = Gtk.Align.FILL;
				}
				main_layout.hexpand = false;
				layout.valign = Gtk.Align.FILL;
			} else {
				start_box.halign = Gtk.Align.FILL;
				center_box.halign = Gtk.Align.FILL;
				end_box.halign = Gtk.Align.FILL;

				start_box.valign = Gtk.Align.START;
				center_box.valign = Gtk.Align.CENTER;
				end_box.valign = Gtk.Align.END;

				start_box.set_orientation(Gtk.Orientation.VERTICAL);
				center_box.set_orientation(Gtk.Orientation.VERTICAL);
				end_box.set_orientation(Gtk.Orientation.VERTICAL);
				layout.set_orientation(Gtk.Orientation.VERTICAL);

				main_layout.set_orientation(Gtk.Orientation.HORIZONTAL);
				if (this.dock_mode) {
					main_layout.valign = Gtk.Align.CENTER;
				} else {
					main_layout.valign = Gtk.Align.FILL;
				}
				main_layout.halign = Gtk.Align.FILL;
				main_layout.hexpand = true;
			}

			layout.set_size_request(width, height);
			set_size_request(width, height);
		}

		public override void get_preferred_width(out int minimum_width, out int natural_width) {
			// Get monitor geometry to constrain panel size
			Gdk.Rectangle monitor_geom = orig_scr;
			var screen = get_screen();
			if (screen != null) {
				var display = screen.get_display();
				if (display != null) {
					var monitor = display.get_primary_monitor();
					if (monitor != null) {
						monitor_geom = monitor.get_geometry();
					}
				}
			}

			int max_width = monitor_geom.width;
			bool horizontal = (position == Budgie.PanelPosition.TOP || position == Budgie.PanelPosition.BOTTOM);

			if (horizontal) {
				// For horizontal panels, constrain width to monitor width
				minimum_width = int.min(orig_scr.width, max_width);
				natural_width = int.min(orig_scr.width, max_width);
			} else {
				// For vertical panels, width is the intended_size
				minimum_width = intended_size;
				natural_width = intended_size;
			}
		}

		public override void get_preferred_height(out int minimum_height, out int natural_height) {
			// Get monitor geometry to constrain panel size
			Gdk.Rectangle monitor_geom = orig_scr;
			var screen = get_screen();
			if (screen != null) {
				var display = screen.get_display();
				if (display != null) {
					var monitor = display.get_primary_monitor();
					if (monitor != null) {
						monitor_geom = monitor.get_geometry();
					}
				}
			}

			int max_height = monitor_geom.height;
			bool horizontal = (position == Budgie.PanelPosition.TOP || position == Budgie.PanelPosition.BOTTOM);

			if (horizontal) {
				// For horizontal panels, height is the intended_size
				minimum_height = intended_size;
				natural_height = intended_size;
			} else {
				// For vertical panels, constrain height to monitor height
				minimum_height = int.min(orig_scr.height, max_height);
				natural_height = int.min(orig_scr.height, max_height);
			}
		}

		private bool applet_at_start_of_region(Budgie.AppletInfo? info) {
			return (info.position == 0);
		}

		private bool applet_at_end_of_region(Budgie.AppletInfo? info) {
			return (info.position >= info.applet.get_parent().get_children().length() - 1);
		}

		private string? get_box_left(Budgie.AppletInfo? info) {
			unowned Gtk.Widget? parent = null;

			if ((parent = info.applet.get_parent()) == end_box) {
				return "center";
			} else if (parent == center_box) {
				return "start";
			} else {
				return null;
			}
		}

		private string? get_box_right(Budgie.AppletInfo? info) {
			unowned Gtk.Widget? parent = null;

			if ((parent = info.applet.get_parent()) == start_box) {
				return "center";
			} else if (parent == center_box) {
				return "end";
			} else {
				return null;
			}
		}

		public override bool can_move_applet_left(Budgie.AppletInfo? info) {
			if (!applet_at_start_of_region(info)) {
				return true;
			}
			if (get_box_left(info) != null) {
				return true;
			}
			return false;
		}

		public override bool can_move_applet_right(Budgie.AppletInfo? info) {
			if (!applet_at_end_of_region(info)) {
				return true;
			}
			if (get_box_right(info) != null) {
				return true;
			}
			return false;
		}

		void conflict_swap(Budgie.AppletInfo? info, int old_position) {
			unowned string key;
			unowned Budgie.AppletInfo? val;
			unowned Budgie.AppletInfo? conflict = null;
			var iter = HashTableIter<string,Budgie.AppletInfo?>(applets);

			while (iter.next(out key, out val)) {
				if (val.alignment == info.alignment && val.position == info.position && info != val) {
					conflict = val;
					break;
				}
			}

			if (conflict == null) {
				return;
			}

			conflict.position = old_position;
		}

		void budge_em_right(string alignment, int after = -1) {
			unowned string key;
			unowned Budgie.AppletInfo? val;
			var iter = HashTableIter<string,Budgie.AppletInfo?>(applets);

			while (iter.next(out key, out val)) {
				if (val.alignment == alignment) {
					if (val.position > after) {
						val.position++;
					}
				}
			}
			this.reinforce_positions();
		}

		void budge_em_left(string alignment, int after) {
			unowned string key;
			unowned Budgie.AppletInfo? val;
			var iter = HashTableIter<string,Budgie.AppletInfo?>(applets);

			while (iter.next(out key, out val)) {
				if (val.alignment == alignment) {
					if (val.position > after) {
						val.position--;
					}
				}
			}
			this.reinforce_positions();
		}

		private void reinforce_positions() {
			unowned string key;
			unowned Budgie.AppletInfo? val;
			var iter = HashTableIter<string,Budgie.AppletInfo?>(applets);

			while (iter.next(out key, out val)) {
				applet_reposition(val);
			}

			/* We may have ugly artifacts now */
			this.queue_draw();
		}

		public override void move_applet_left(Budgie.AppletInfo? info) {
			string? new_home = null;
			int new_position = info.position;
			int old_position = info.position;

			if (!applet_at_start_of_region(info)) {
				new_position--;
				if (new_position < 0) {
					new_position = 0;
				}
				info.position = new_position;
				conflict_swap(info, old_position);
				applets_changed();
				update_sizes();
				update_box_size_constraints();
				return;
			}
			if ((new_home = get_box_left(info)) != null) {
				unowned Gtk.Box? new_parent = null;
				switch (info.alignment) {
					case "end":
						new_parent = center_box;
						break;
					case "center":
						new_parent = start_box;
						break;
					default:
						new_parent = end_box;
						break;
				}

				string old_home = info.alignment;
				uint len = new_parent.get_children().length();
				info.alignment = new_home;
				info.position = (int)len;
				budge_em_left(old_home, 0);
				applets_changed();
				update_sizes();
				update_box_size_constraints();
			}
		}

		public override void move_applet_right(Budgie.AppletInfo? info) {
			string? new_home = null;
			int new_position = info.position;
			int old_position = info.position;
			uint len;

			if (!applet_at_end_of_region(info)) {
				new_position++;
				len = info.applet.get_parent().get_children().length() - 1;
				if (new_position > len) {
					new_position = (int) len;
				}
				info.position = new_position;
				conflict_swap(info, old_position);
				applets_changed();
				update_sizes();
				update_box_size_constraints();
				return;
			}
			if ((new_home = get_box_right(info)) != null) {
				info.alignment = new_home;
				budge_em_right(new_home);
				info.position = 0;
				this.reinforce_positions();
				applets_changed();
				update_sizes();
				update_box_size_constraints();
			}
		}

		private bool initial_anim = false;
		private Budgie.Animation? dock_animation = null;

		private bool initial_animation() {
			this.allow_animation = true;
			this.initial_anim = true;

			this.show_panel();
			return false;
		}

		/**
		* In an autohidden mode, if we're not visible, and get peeked, say
		* hello
		*/
		private bool on_enter_notify(Gdk.EventCrossing cr) {
			//  if (this.render_panel) {
			//  	return Gdk.EVENT_PROPAGATE;
			//  }
			if (this.autohide == AutohidePolicy.NONE) {
				return Gdk.EVENT_PROPAGATE;
			}
			if (cr.detail == Gdk.NotifyType.INFERIOR) {
				return Gdk.EVENT_PROPAGATE;
			}

			if (show_panel_id > 0) {
				Source.remove(show_panel_id);
			}
			show_panel_id = Timeout.add(150, this.show_panel);
			return Gdk.EVENT_STOP;
		}

		private bool on_leave_notify(Gdk.EventCrossing cr) {
			if (this.autohide == AutohidePolicy.NONE) {
				return Gdk.EVENT_PROPAGATE;
			}
			if (cr.detail == Gdk.NotifyType.INFERIOR) {
				return Gdk.EVENT_PROPAGATE;
			}

			if (show_panel_id > 0) {
				Source.remove(show_panel_id);
				show_panel_id = 0;
			}

			return Gdk.EVENT_STOP;
		}

		uint show_panel_id = 0;

		/**
		* Show the panel through a small animation
		*/
		private bool show_panel() {
			show_panel_id = 0;

			if (!this.allow_animation) {
				return false;
			}
			this.animation = PanelAnimation.SHOW;
			//  render_panel = true;

			this.queue_draw();
			this.show();

			if (!this.get_settings().gtk_enable_animations) {
				this.nscale = 1.0;
				this.animation = PanelAnimation.NONE;
				this.queue_draw();
				return false;
			}

			dock_animation = new Budgie.Animation();
			dock_animation.widget = this;
			dock_animation.length = 360 * Budgie.MSECOND;
			dock_animation.tween = Budgie.expo_ease_out;
			dock_animation.changes = new Budgie.PropChange[] {
				Budgie.PropChange() {
					property = "nscale",
					old = this.nscale,
					@new = 1.0
				}
			};

			dock_animation.start((a) => {
				this.animation = PanelAnimation.NONE;
			});

			set_above_other_surfaces();
			return false;
		}

		public override bool draw(Cairo.Context cr) {
			//  if (!render_panel) {
			//  	/* Don't need to render */
			//  	return Gdk.EVENT_STOP;
			//  }

			if (animation == PanelAnimation.NONE) {
				return base.draw(cr);
			}

			var window = this.get_window();
			if (window == null) {
				return Gdk.EVENT_STOP;
			}

			Gtk.Allocation alloc;
			get_allocation(out alloc);
			/* Create a compatible buffer for the current scaling factor */
			var buffer = window.create_similar_image_surface(Cairo.Format.ARGB32,
															alloc.width * this.scale_factor,
															alloc.height * this.scale_factor,
															this.scale_factor);
			var cr2 = new Cairo.Context(buffer);

			propagate_draw(get_child(), cr2);
			var y = ((double)alloc.height) * render_scale;
			var x = ((double)alloc.width) * render_scale;

			switch (position) {
				case Budgie.PanelPosition.TOP:
					// Slide down into view
					cr.set_source_surface(buffer, 0, y - alloc.height);
					break;
				case Budgie.PanelPosition.LEFT:
					// Slide into view from left
					cr.set_source_surface(buffer, x - alloc.width, 0);
					break;
				case Budgie.PanelPosition.RIGHT:
					// Slide back into view from right
					cr.set_source_surface(buffer, alloc.width - x, 0);
					break;
				case Budgie.PanelPosition.BOTTOM:
				default:
					// Slide up into view
					cr.set_source_surface(buffer, 0, alloc.height - y);
					break;
			}

			cr.paint();

			return Gdk.EVENT_STOP;
		}

		/**
		* Specialist operation, perform a migration after we changed applet configurations
		* See: https://github.com/solus-project/budgie-desktop/issues/555
		*/
		public void perform_migration(int current_migration_level) {
			if (current_migration_level != 0) {
				warning("Unknown migration level: %d", current_migration_level);
				return;
			}
			this.need_migratory = true;
			if (this.is_fully_loaded) {
				message("Performing migration to level %d", BUDGIE_MIGRATION_LEVEL);
				this.add_migratory();
			}
		}

		/**
		* Very simple right now. Just add the applets to the end of the panel
		*/
		private bool add_migratory() {
			lock (need_migratory) {
				if (!need_migratory) {
					return false;
				}
				need_migratory = false;
				foreach (var new_applet in MIGRATION_1_APPLETS) {
					message("Adding migratory applet: %s", new_applet);
					add_new_applet_at(new_applet, end_box);
				}
			}
			return false;
		}

		private void set_above_other_surfaces() {
			GtkLayerShell.set_layer(this, GtkLayerShell.Layer.TOP); // Ensure it is above other surfaces
			GtkLayerShell.set_exclusive_zone(this, this.intended_size);
		}

		private void set_below_other_surfaces() {
			GtkLayerShell.set_layer(this, GtkLayerShell.Layer.BOTTOM); // Ensure it is below other surfaces
		}
	}
}
