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
	* Owns a panel's applets: loading, adding, removing and ordering them
	* within the start, center and end regions
	*/
	public class PanelApplets : GLib.Object {
		private unowned Panel panel; // the window the applets sit in; it outlives us
		private unowned Budgie.PanelManager manager; // for wiping an applet's dconf paths when it is removed
		private unowned Budgie.PanelPluginManager plugin_manager; // loads plugins and creates applet instances
		private unowned Settings settings; // this panel's settings, where the applet uuid list is persisted
		private unowned PopoverManager popover_manager; // every applet registers its popovers here
		private unowned MainPanel layout; // the box holding the three regions
		private unowned ConstrainedBox start_box; // alignment "start"
		private unowned ConstrainedBox center_box; // alignment "center"
		private unowned ConstrainedBox end_box; // alignment "end"

		private HashTable<string,Budgie.AppletInfo?> applets; // every applet on the panel, by uuid

		private int[] icon_sizes = { // the sizes applets are offered; chosen from by panel thickness
			16, 24, 32, 48, 96, 128, 256
		};
		private int current_icon_size; // largest icon_sizes entry that fits the panel
		private int current_small_icon_size; // the step below it

		public signal void loaded(); // every applet from settings is placed, or there were none to load

		public PanelApplets(Panel panel, Budgie.PanelManager manager, Budgie.PanelPluginManager plugin_manager,
							Settings settings, PopoverManager popover_manager, MainPanel layout,
							ConstrainedBox start_box, ConstrainedBox center_box, ConstrainedBox end_box) {
			this.panel = panel;
			this.manager = manager;
			this.plugin_manager = plugin_manager;
			this.settings = settings;
			this.popover_manager = popover_manager;
			this.layout = layout;
			this.start_box = start_box;
			this.center_box = center_box;
			this.end_box = end_box;

			applets = new HashTable<string,Budgie.AppletInfo?>(str_hash, str_equal);
			update_icon_sizes(); // the first applets added by load() need these
		}

		/**
		* Every applet on the panel, in hash order; the applets stay owned by
		* the table
		*/
		public List<unowned Budgie.AppletInfo?> get_applets() {
			return applets.get_values();
		}

		/**
		* First applet that advertises the action, or null
		*/
		public unowned Budgie.AppletInfo? find_supporting(Budgie.PanelAction action) {
			foreach (unowned Budgie.AppletInfo? info in applets.get_values()) {
				if (action in info.applet.supported_actions) {
					return info;
				}
			}
			return null;
		}

		/**
		* Picks the icon sizes for the panel's current thickness and tells
		* every applet
		*/
		public void update_sizes() {
			update_icon_sizes();

			foreach (unowned Budgie.AppletInfo? info in applets.get_values()) {
				info.applet.panel_size_changed(panel.intended_size, current_icon_size, current_small_icon_size);
			}
		}

		/**
		* Picks the largest icon size that fits the panel's thickness, and the
		* size below it
		*/
		private void update_icon_sizes() {
			current_icon_size = icon_sizes[0];
			current_small_icon_size = icon_sizes[0];

			for (int i = 1; i < icon_sizes.length; i++) { // walk up until the next size would no longer fit
				if (icon_sizes[i] > panel.intended_size) {
					break;
				}
				current_icon_size = icon_sizes[i];
				current_small_icon_size = icon_sizes[i-1];
			}
		}

		/**
		* Tells every applet which edge the panel is on, so it can flip its
		* own layout
		*/
		public void update_positions() {
			foreach (unowned Budgie.AppletInfo? info in applets.get_values()) {
				info.applet.panel_position_changed(panel.position);
			}
		}

		/**
		* Loads every applet listed in settings, sorted per region by saved
		* position, then announces the panel as loaded
		*/
		public void load() {
			var start_applets = new List<Budgie.AppletInfo?>();
			var center_applets = new List<Budgie.AppletInfo?>();
			var end_applets = new List<Budgie.AppletInfo?>();

			foreach (string uuid in settings.get_strv(Budgie.PANEL_KEY_APPLETS)) {
				Budgie.AppletInfo? info = load_stored_applet(uuid);
				if (info == null) { // skip loading a missing or broken plugin
					continue;
				}

				if (info.alignment == "start") { // sort by position within each region
					start_applets.insert_sorted(info, compare_by_position);
				} else if (info.alignment == "center") {
					center_applets.insert_sorted(info, compare_by_position);
				} else {
					end_applets.insert_sorted(info, compare_by_position);
				}
			}

			add_in_order(start_applets);
			add_in_order(center_applets);
			add_in_order(end_applets);

			panel.applets_changed();
			loaded(); // emit even when no applet loaded, so the panel still shows
		}

		/**
		* Adds an applet of the plugin to the region with the fewest applets
		*/
		public void add_new_applet(string plugin_name) {
			add_new_applet_at(plugin_name, least_populated_region());
		}

		/**
		* Builds the applets from a layout file (panel.ini); only used when no
		* configuration exists yet
		*/
		public void create_default_layout(string name, KeyFile config) {
			try {
				if (!config.has_key(name, "Children")) {
					warning("Config for panel %s does not specify applets", name);
					return;
				}
				string[] children = config.get_string_list(name, "Children"); // each entry names a group in the file describing one applet
				foreach (string group in children) {
					group = group.strip();

					if (!config.has_group(group)) {
						warning("Panel applet %s missing from config", group);
						continue;
					}

					if (!config.has_key(group, "ID")) {
						warning("Applet %s is missing ID", group);
						continue;
					}

					string region = config.has_key(group, "Alignment") ? config.get_string(group, "Alignment").strip() : "start"; // default to start when Alignment is missing
					add_new_applet_at(config.get_string(group, "ID").strip(), region); // ID is the plugin name
				}
			} catch (Error e) {
				warning("Error loading default config: %s", e.message);
			}
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
			debug("Performing migration to level %d", BUDGIE_MIGRATION_LEVEL);
			foreach (string plugin_name in MIGRATION_1_APPLETS) {
				add_new_applet_at(plugin_name, "end"); // add after the user's existing applets
			}
		}

		/**
		* Takes an applet off the panel for good: widget, settings and the gap
		* it leaves in its region
		*/
		public void remove_applet(Budgie.AppletInfo? info) {
			if (info == null) {
				return;
			}

			int position = info.position;
			string region = info.alignment;
			string uuid = info.uuid;

			tear_down(info);
			update_region_visibility();

			applets.remove(uuid); /* TODO: Add refcounting and unload unused plugins. */
			panel.applet_removed(uuid);

			set_applets();
			shift_positions(region, position, -1); // close the gap it left
		}

		/**
		* Removes every applet and wipes its settings
		*/
		public void destroy_children() {
			foreach (unowned AppletInfo? info in applets.get_values()) { // get_values() is a copy, so tearing down while looping is safe
				tear_down(info);
			}
		}

		/**
		* Anything but the first applet of the start region can move left
		*/
		public bool can_move_applet_left(Budgie.AppletInfo? info) {
			if (!applet_at_start_of_region(info)) {
				return true;
			}
			if (get_box_left(info) != null) {
				return true;
			}
			return false;
		}

		/**
		* Anything but the last applet of the end region can move right
		*/
		public bool can_move_applet_right(Budgie.AppletInfo? info) {
			if (!applet_at_end_of_region(info)) {
				return true;
			}
			if (get_box_right(info) != null) {
				return true;
			}
			return false;
		}

		/**
		* Left and right are in region order (start, center, end), whatever
		* the panel's orientation. Crossing a region boundary reparents the
		* applet to the far end of the neighboring region.
		*/
		public void move_applet_left(Budgie.AppletInfo? info) {
			if (!applet_at_start_of_region(info)) {
				step_within_region(info, -1);
				return;
			}

			string? new_region = get_box_left(info); // at the region's start: become the last applet of the previous region
			if (new_region == null) {
				return;
			}
			string old_region = info.alignment;
			info.position = (int) region_for(new_region).get_children().length(); // read before the alignment change reparents the widget into that region
			info.alignment = new_region;
			shift_positions(old_region, 0, -1); // the old region lost its first applet
			settle_after_move();
		}

		/**
		* Mirror of move_applet_left()
		*/
		public void move_applet_right(Budgie.AppletInfo? info) {
			if (!applet_at_end_of_region(info)) {
				step_within_region(info, 1);
				return;
			}

			string? new_region = get_box_right(info); // at the region's end: become the first applet of the next region
			if (new_region == null) {
				return;
			}
			info.alignment = new_region;
			shift_positions(new_region, -1, 1); // make room at position 0 for it; this bumps the moved applet too, which the next line corrects
			info.position = 0;
			reinforce_positions();
			settle_after_move();
		}

		/**
		* Moves an applet one slot within its region and swaps with whoever
		* held that slot
		*/
		private void step_within_region(Budgie.AppletInfo info, int delta) {
			int old_position = info.position;
			int last = (int) info.applet.get_parent().get_children().length() - 1;
			info.position = (old_position + delta).clamp(0, last);
			conflict_swap(info, old_position);
			settle_after_move();
		}

		/**
		* Loads a saved applet, or returns null when its plugin is missing or
		* fails to load
		*/
		private Budgie.AppletInfo? load_stored_applet(string uuid) {
			string? plugin_name;
			try {
				return plugin_manager.load_applet_instance(uuid, null, out plugin_name);
			} catch (Error e) {
				warning(e.message); // Forward the message from the plugin loader
				return null;
			}
		}

		/**
		* Adds a region's applets in saved order, numbering them from zero
		* since saved positions can have gaps
		*/
		private void add_in_order(List<Budgie.AppletInfo?> region_applets) {
			int position = 0;
			foreach (unowned Budgie.AppletInfo? info in region_applets) {
				info.position = position++; // set before add_applet() connects applet_updated
				add_applet(info);
			}
		}

		/**
		* Sort order for insert_sorted: ascending stored position
		*/
		private static int compare_by_position(Budgie.AppletInfo? a, Budgie.AppletInfo? b) {
			return (int) (a.position > b.position) - (int) (a.position < b.position);
		}

		/**
		* Adds an applet of the plugin to the end of the named region
		*/
		private void add_new_applet_at(string plugin_name, string region) {
			if (!plugin_manager.is_plugin_valid(plugin_name)) {
				warning("Not adding applet from invalid plugin: %s", plugin_name);
				return;
			}
			if (!plugin_manager.is_plugin_loaded(plugin_name)) {
				plugin_manager.modprobe(plugin_name); // loads synchronously
			}

			string uuid = LibUUID.new(UUIDFlags.LOWER_CASE|UUIDFlags.TIME_SAFE_TYPE);
			Budgie.AppletInfo? info;
			try {
				info = plugin_manager.create_applet(plugin_name, uuid);
			} catch (Error e) {
				warning("Not adding applet %s %s: %s", plugin_name, uuid, e.message);
				return;
			}

			info.alignment = region; // set before add_applet() connects applet_updated
			info.position = (int) region_for(region).get_children().length(); // append to the end of the region
			add_applet(info);
		}

		/**
		* The first of start, center and end holding the fewest applets
		*/
		private string least_populated_region() {
			string[] regions = { "start", "center", "end" };
			string result = "start";
			uint fewest = uint.MAX;
			foreach (string region in regions) {
				uint count = region_for(region).get_children().length();
				if (count < fewest) { // ties go to the earlier region
					fewest = count;
					result = region;
				}
			}
			return result;
		}

		/**
		* Stores an applet, packs it into its region at its position, and
		* brings it up to the panel's current state
		*/
		private void add_applet(Budgie.AppletInfo? info) {
			unowned Gtk.Box pack_target = region_for(info.alignment);

			applets.insert(info.uuid, info);
			set_applets(); // update the applets uuid list

			info.applet.update_popovers(popover_manager); // the applet registers its popovers so they get layer-shell setup and visibility tracking
			info.applet.panel_size_changed(panel.intended_size, current_icon_size, current_small_icon_size); // bring the new applet up to the panel's current state
			info.applet.panel_position_changed(panel.position);

			pack_target.pack_start(info.applet, false, false, 0);
			pack_target.child_set(info.applet, "position", info.position);
			update_region_visibility();

			info.notify.connect(applet_updated); // alignment and position edits from the settings UI arrive as property changes
			panel.applet_added(info);
		}

		/**
		* Detaches an applet's widget and wipes both its AppletInfo settings
		* and its own configuration
		*/
		private void tear_down(Budgie.AppletInfo info) {
			Settings? app_settings = info.applet.get_applet_settings(info.uuid);
			if (app_settings != null) {
				app_settings.ref(); // keep the applet's own settings alive past the widget's removal so they can still be reset below
			}

			info.notify.disconnect(applet_updated); // stop reacting to property changes on an applet that is going away
			info.applet.get_parent().remove(info.applet);

			manager.reset_dconf_path(info.settings); // the AppletInfo's alignment, position and plugin name
			if (app_settings != null) {
				manager.reset_dconf_path(app_settings); // the applet's own configuration
			}
		}

		/**
		* The box a region name refers to; anything but "start" and "end"
		* lands in the center
		*/
		private unowned Gtk.Box region_for(string region) {
			switch (region) {
				case "start":
					return start_box;
				case "end":
					return end_box;
				default:
					return center_box;
			}
		}

		/**
		* An AppletInfo property changed, which is how the settings UI edits
		* alignment and position
		*/
		private void applet_updated(Object object, ParamSpec pspec) {
			unowned AppletInfo? info = object as AppletInfo;

			if (pspec.name == "alignment") {
				applet_reparent(info);
			} else if (pspec.name == "position") {
				applet_reposition(info);
			}
			panel.applets_changed();
		}

		/**
		* The applet's alignment changed: move its widget into the region that
		* alignment names
		*/
		private void applet_reparent(Budgie.AppletInfo? info) {
			unowned Gtk.Box new_parent = region_for(info.alignment);

			Gtk.Box current_parent = (Gtk.Box) info.applet.get_parent();
			if (new_parent == current_parent) { // already home
				return;
			}

			current_parent.remove(info.applet);
			new_parent.add(info.applet);
			update_region_visibility();

			info.applet.queue_resize();
			update_sizes();
			update_box_size_constraints();
		}

		/**
		* The applet's position changed: move its widget to that child index
		* within its region
		*/
		private void applet_reposition(Budgie.AppletInfo? info) {
			info.applet.get_parent().child_set(info.applet, "position", info.position);
			update_region_visibility();
		}

		/**
		* A region box is only shown while it has children, so an empty region
		* takes no space
		*/
		private void update_region_visibility() {
			Gtk.Box[] regions = { start_box, center_box, end_box };
			foreach (unowned Gtk.Box region in regions) {
				if (!region.get_children().is_empty()) {
					if (!region.get_visible()) {
						region.show(); // show_all would also reveal children an applet keeps hidden, like the Budgie Menu label
						region.queue_draw();
					}
				} else {
					region.hide();
				}
			}
		}

		/**
		* Lets the regions re-measure after a change, then re-applies their
		* mutual constraints once the allocations have settled
		*/
		private void update_box_size_constraints() {
			start_box.queue_resize();
			center_box.queue_resize();
			end_box.queue_resize();
			layout.queue_resize();

			Timeout.add(10, apply_box_constraints); // the allocations only exist after the resize cycle has run
		}

		/**
		* Re-applies the regions' size constraints for the layout's current
		* allocation
		*/
		private bool apply_box_constraints() {
			Gtk.Allocation allocation;
			layout.get_allocation(out allocation);
			layout.update_box_constraints(allocation);
			return false;
		}

		/**
		* Persists the current set of applet uuids; order does not matter,
		* each AppletInfo stores its own slot
		*/
		private void set_applets() {
			string[] uuids = {};
			foreach (unowned string uuid in applets.get_keys()) {
				uuids += uuid;
			}

			settings.set_strv(Budgie.PANEL_KEY_APPLETS, uuids);
		}

		/**
		* First child of its region
		*/
		private bool applet_at_start_of_region(Budgie.AppletInfo? info) {
			return (info.position == 0);
		}

		/**
		* Last child of its region
		*/
		private bool applet_at_end_of_region(Budgie.AppletInfo? info) {
			return (info.position >= info.applet.get_parent().get_children().length() - 1);
		}

		/**
		* The region before the applet's own in start, center, end order;
		* null when already in start
		*/
		private string? get_box_left(Budgie.AppletInfo? info) {
			unowned Gtk.Widget? parent = info.applet.get_parent();

			if (parent == end_box) {
				return "center";
			} else if (parent == center_box) {
				return "start";
			} else {
				return null;
			}
		}

		/**
		* The region after the applet's own in start, center, end order;
		* null when already in end
		*/
		private string? get_box_right(Budgie.AppletInfo? info) {
			unowned Gtk.Widget? parent = info.applet.get_parent();

			if (parent == start_box) {
				return "center";
			} else if (parent == center_box) {
				return "end";
			} else {
				return null;
			}
		}

		/**
		* What every move needs once positions changed: tell listeners,
		* re-send sizes, re-cap the regions
		*/
		private void settle_after_move() {
			panel.applets_changed();
			update_sizes();
			update_box_size_constraints();
		}

		/**
		* An applet just took a position inside its region; whoever held it
		* gets the vacated one, so the two swap
		*/
		private void conflict_swap(Budgie.AppletInfo? info, int old_position) {
			foreach (unowned Budgie.AppletInfo? other in applets.get_values()) {
				if (other.alignment == info.alignment && other.position == info.position && info != other) {
					other.position = old_position;
					return; // only one applet can hold a position
				}
			}
		}

		/**
		* Moves every applet in the region that sits after @after by @delta
		* slots
		*/
		private void shift_positions(string region, int after, int delta) {
			foreach (unowned Budgie.AppletInfo? info in applets.get_values()) {
				if (info.alignment == region && info.position > after) {
					info.position += delta; // applet_updated moves the widget
				}
			}
			reinforce_positions(); // reapply every position once all have shifted
		}

		/**
		* Re-applies every stored position to its box after positions were
		* shifted; the property notifications alone would do it one applet at
		* a time
		*/
		private void reinforce_positions() {
			foreach (unowned Budgie.AppletInfo? info in applets.get_values()) {
				applet_reposition(info);
			}

			panel.queue_draw(); // we may have ugly artifacts now
		}
	}
}
