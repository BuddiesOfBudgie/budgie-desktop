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

		private HashTable<string,HashTable<string,string>> pending; // uuids per plugin name waiting for the plugin to load; these already exist in settings
		private HashTable<string,HashTable<string,string>> creating; // same, for applets being created new
		private HashTable<string,Budgie.AppletInfo?> applets; // every applet on the panel, by uuid
		private HashTable<string,Budgie.AppletInfo?> initial_config; // slot requested for an applet whose plugin has not produced its AppletInfo yet
		private List<string?> expected_uuids; // uuids from settings still to appear; the panel counts as loaded once this empties
		private bool is_fully_loaded = false; // every stored applet has been placed; later arrivals are user additions
		private bool need_migratory = false; // a migration asked for applets to be added once loading finishes

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

			pending = new HashTable<string,HashTable<string,string>>(str_hash, str_equal);
			creating = new HashTable<string,HashTable<string,string>>(str_hash, str_equal);
			applets = new HashTable<string,Budgie.AppletInfo?>(str_hash, str_equal);
			initial_config = new HashTable<string,Budgie.AppletInfo>(str_hash, str_equal);
			expected_uuids = new List<string?>();

			plugin_manager.extension_loaded.connect_after(on_extension_loaded); // after, so the plugin manager has registered the plugin before we ask it for instances
		}

		/**
		* A new list of every applet on the panel, in hash order
		*/
		public List<Budgie.AppletInfo?> get_applets() {
			List<Budgie.AppletInfo?> result = new List<Budgie.AppletInfo?>();
			unowned string? key;
			unowned Budgie.AppletInfo? info;

			var iter = HashTableIter<string,Budgie.AppletInfo?>(applets);
			while (iter.next(out key, out info)) {
				result.append(info);
			}
			return result;
		}

		/**
		* First applet that advertises the action, or null
		*/
		public unowned Budgie.AppletInfo? find_supporting(Budgie.PanelAction action) {
			unowned string? uuid;
			unowned Budgie.AppletInfo? info;

			var iter = HashTableIter<string?,Budgie.AppletInfo?>(applets);
			while (iter.next(out uuid, out info)) {
				if (action in info.applet.supported_actions) {
					return info;
				}
			}
			return null;
		}

		/**
		* Picks the icon sizes for the panel's current thickness and tells
		* every applet. Also run on an empty panel so the sizes are ready for
		* the first applet.
		*/
		public void update_sizes() {
			int size = icon_sizes[0];
			int small_size = icon_sizes[0];

			unowned string? key;
			unowned Budgie.AppletInfo? info;

			for (int i = 1; i < icon_sizes.length; i++) { // walk up until the next size would no longer fit
				if (icon_sizes[i] > panel.intended_size) {
					break;
				}
				size = icon_sizes[i];
				small_size = icon_sizes[i-1];
			}

			current_icon_size = size;
			current_small_icon_size = small_size;

			var iter = HashTableIter<string?,Budgie.AppletInfo?>(applets);
			while (iter.next(out key, out info)) {
				info.applet.panel_size_changed(panel.intended_size, size, small_size);
			}
		}

		/**
		* Tells every applet which edge the panel is on, so it can flip its
		* own layout
		*/
		public void update_positions() {
			unowned string? key;
			unowned Budgie.AppletInfo? info;

			var iter = HashTableIter<string?,Budgie.AppletInfo?>(applets);
			while (iter.next(out key, out info)) {
				info.applet.panel_position_changed(panel.position);
			}
		}

		/**
		* Loads every applet listed in settings, sorted per region by saved
		* position. Applets whose plugin is not loaded yet arrive later through
		* on_extension_loaded().
		*/
		public void load() {
			string[]? uuids = settings.get_strv(Budgie.PANEL_KEY_APPLETS);
			if (uuids == null || uuids.length == 0) { // nothing stored, so the panel is loaded right away
				is_fully_loaded = true;
				on_fully_loaded();
				return;
			}

			lock (expected_uuids) {
				for (int i = 0; i < uuids.length; i++) {
					expected_uuids.append(uuids[i]);
				}

				var start_applets = new List<Budgie.AppletInfo?>();
				var center_applets = new List<Budgie.AppletInfo?>();
				var end_applets = new List<Budgie.AppletInfo?>();

				for (int i = 0; i < uuids.length; i++) {
					string? name = null;
					Budgie.AppletInfo? info;

					try {
						info = plugin_manager.load_applet_instance(uuids[i], null, out name);
					} catch (Error e) {
						if (name == null) { // no plugin name means the stored uuid is garbage; with one the plugin just has not loaded yet
							unowned List<string?> link = expected_uuids.find_custom(uuids[i], strcmp);

							if (link != null) {
								expected_uuids.remove_link(link); // nothing will ever arrive for it, so stop waiting
							}

							debug("Unable to load invalid applet '%s': %s", uuids[i], e.message);
							panel.applet_removed(uuids[i]);

							continue;
						} else {
							info = add_pending(uuids[i], name);

							if (info == null) { // queued for on_extension_loaded(), or dropped as unloadable
								continue;
							}
						}
					}

					if (info.alignment == "start") {
						start_applets.insert_sorted(info, compare_by_position);
					} else if (info.alignment == "center") {
						center_applets.insert_sorted(info, compare_by_position);
					} else {
						end_applets.insert_sorted(info, compare_by_position);
					}
				}

				for (int i = 0; i < start_applets.length(); i++) { // saved positions may have gaps; renumber each region from zero
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

				if (!is_fully_loaded && expected_uuids.is_empty()) { // no stored applet was loadable, so add_applet never emitted it
					is_fully_loaded = true;
					on_fully_loaded();
				}
			}
		}

		/**
		* Adds an applet of the plugin to the region with the fewest applets
		*/
		public void add_new_applet(string plugin_name) {
			add_new_applet_at(plugin_name, null);
		}

		/**
		* Builds the applets from a layout file (panel.ini); only used when no
		* configuration exists yet
		*/
		public void create_default_layout(string name, KeyFile config) {
			int start_index = -1; // next position per region
			int center_index = -1;
			int end_index = -1;
			int index;

			try {
				if (!config.has_key(name, "Children")) {
					warning("Config for panel %s does not specify applets", name);
					return;
				}
				string[] children = config.get_string_list(name, "Children"); // each entry names a group in the file describing one applet
				foreach (string group in children) {
					group = group.strip();
					string alignment = "start"; /* center, end */

					if (!config.has_group(group)) {
						warning("Panel applet %s missing from config", group);
						continue;
					}

					if (!config.has_key(group, "ID")) {
						warning("Applet %s is missing ID", group);
						continue;
					}

					string? uuid = LibUUID.new(UUIDFlags.LOWER_CASE|UUIDFlags.TIME_SAFE_TYPE);

					var id = config.get_string(group, "ID").strip(); // the plugin name
					if (uuid == null || uuid.strip() == "") {
						warning("Could not add new applet %s from config %s", id, name);
						continue;
					}

					AppletInfo? info = new AppletInfo.from_uuid(uuid);
					if (config.has_key(group, "Alignment")) {
						alignment = config.get_string(group, "Alignment").strip();
					}

					switch (alignment) { // positions count up per region in file order
						case "center":
							index = ++center_index;
							break;
						case "end":
							index = ++end_index;
							break;
						default:
							index = ++start_index;
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

		/**
		* Specialist operation, perform a migration after we changed applet configurations
		* See: https://github.com/solus-project/budgie-desktop/issues/555
		*/
		public void perform_migration(int current_migration_level) {
			if (current_migration_level != 0) {
				warning("Unknown migration level: %d", current_migration_level);
				return;
			}
			need_migratory = true;
			if (is_fully_loaded) { // otherwise on_fully_loaded() runs it once loading finishes
				debug("Performing migration to level %d", BUDGIE_MIGRATION_LEVEL);
				add_migratory();
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
			string alignment = info.alignment;
			string uuid = info.uuid;

			tear_down(info);
			toggle_container_visibilities();

			applets.remove(uuid); /* TODO: Add refcounting and unload unused plugins. */
			panel.applet_removed(uuid);

			set_applets();
			close_gap(alignment, position);
		}

		/**
		* Removes every applet and wipes its settings
		*/
		public void destroy_children() {
			unowned string key;
			unowned AppletInfo? info;

			var iter = HashTableIter<string?,AppletInfo?>(applets);
			while (iter.next(out key, out info)) {
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

			string? new_home = get_box_left(info); // at the region's start: become the last applet of the previous region
			if (new_home == null) {
				return;
			}
			string old_home = info.alignment;
			info.position = (int) region_for(new_home).get_children().length(); // read before the alignment change reparents the widget into that region
			info.alignment = new_home;
			close_gap(old_home, 0); // the old region lost its first applet
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

			string? new_home = get_box_right(info); // at the region's end: become the first applet of the next region
			if (new_home == null) {
				return;
			}
			info.alignment = new_home;
			open_gap(new_home); // make room at position 0 for it; this bumps the moved applet too, which the next line corrects
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
		* Loads an existing applet instance, or queues it in `pending` and
		* returns null when its plugin is not loaded yet
		*/
		private Budgie.AppletInfo? add_pending(string uuid, string plugin_name) {
			string? loaded_name;

			if (!plugin_manager.is_plugin_valid(plugin_name)) {
				warning("Not adding invalid plugin: %s %s", plugin_name, uuid);
				stop_expecting(uuid);
				return null;
			}

			if (!plugin_manager.is_plugin_loaded(plugin_name)) {
				queue_for_plugin(pending, plugin_name, uuid);

				if (!plugin_manager.is_plugin_loaded(plugin_name)) { // modprobe is synchronous, so the plugin failed to load
					warning("Not adding applet whose plugin failed to load: %s %s", plugin_name, uuid);
					pending.remove(plugin_name);
					stop_expecting(uuid);
				}
				return null;
			}

			Budgie.AppletInfo? info = null;

			try {
				info = plugin_manager.load_applet_instance(uuid, null, out loaded_name);
			} catch (Error e) {
				critical("Failed to load applet when we know it exists: %s %s: %s", plugin_name, uuid, e.message);
			}

			return info;
		}

		/**
		* Stop waiting on an applet that will never be added, so the
		* panel can still finish loading
		*/
		private void stop_expecting(string uuid) {
			lock (expected_uuids) {
				unowned List<string?> link = expected_uuids.find_custom(uuid, strcmp);
				if (link != null) {
					expected_uuids.remove_link(link);
				}
			}
		}

		/**
		* Creates a new instance of a plugin, queueing the request in
		* `creating` when the plugin is not loaded yet
		*/
		private void add_new(string plugin_name, string? initial_uuid = null) {
			string? uuid;

			if (!plugin_manager.is_plugin_valid(plugin_name)) {
				warning("Not loading invalid plugin: %s", plugin_name);
				return;
			}
			if (initial_uuid == null) {
				uuid = LibUUID.new(UUIDFlags.LOWER_CASE|UUIDFlags.TIME_SAFE_TYPE);
			} else {
				uuid = initial_uuid;
			}

			if (!plugin_manager.is_plugin_loaded(plugin_name)) {
				queue_for_plugin(creating, plugin_name, uuid); // on_extension_loaded() finishes the job
				return;
			}

			try {
				Budgie.AppletInfo? info = plugin_manager.create_applet(plugin_name, uuid);
				add_applet(info);
			} catch (Error e) {
				critical("Failed to load applet when we know it exists: %s %s: %s", plugin_name, uuid, e.message);
				return;
			}
		}

		/**
		* Remembers a uuid for a plugin that is still loading; the first
		* request for a plugin is the one that starts the load
		*/
		private void queue_for_plugin(HashTable<string,HashTable<string,string>> queue, string plugin_name, string uuid) {
			HashTable<string,string>? table = queue.lookup(plugin_name);
			bool first_request = table == null;
			if (first_request) {
				table = new HashTable<string,string>(str_hash, str_equal);
				queue.insert(plugin_name, table);
			}
			table.insert(uuid, uuid); // before modprobe: a plugin that loads synchronously drains the queue from on_extension_loaded() right away
			if (first_request) {
				plugin_manager.modprobe(plugin_name);
			}
		}

		/**
		* A plugin finished loading: create every applet that was queued for
		* it in pending and creating
		*/
		private void on_extension_loaded(string name) {
			unowned HashTable<string,string>? queued = pending.lookup(name);
			if (queued != null) {
				var iter = HashTableIter<string,string>(queued);
				string? uuid;

				while (iter.next(out uuid, null)) {
					string? loaded_name;
					try {
						Budgie.AppletInfo? info = plugin_manager.load_applet_instance(uuid, null, out loaded_name);
						add_applet(info);
					} catch (Error e) {
						critical("Failed to load applet when we know it exists: %s %s: %s", name, uuid, e.message);
					}
				}
				pending.remove(name);
			}

			queued = creating.lookup(name);
			if (queued != null) {
				var iter = HashTableIter<string,string>(queued);
				string? uuid;

				while (iter.next(out uuid, null)) {
					try {
						Budgie.AppletInfo? info = plugin_manager.create_applet(name, uuid);
						add_applet(info);
					} catch (Error e) {
						critical("Failed to load applet when we know it exists: %s %s: %s", name, uuid, e.message);
					}
				}
				creating.remove(name);
			}
		}

		/**
		* The single path every instance takes into the panel, whether loaded
		* from settings, created new, or queued for a plugin
		*/
		private void add_applet(Budgie.AppletInfo? info) {
			Budgie.AppletInfo? initial_info = initial_config.lookup(info.uuid); // a UI-requested applet carries its slot here until the plugin produces the instance
			if (initial_info != null) {
				info.alignment = initial_info.alignment;
				info.position = initial_info.position;
				initial_config.remove(info.uuid);
			}

			if (!is_fully_loaded) { // one of the stored applets arrived; it is no longer expected
				lock (expected_uuids) {
					unowned List<string?> link = expected_uuids.find_custom(info.uuid, strcmp);
					if (link != null) {
						expected_uuids.remove_link(link);
					}
				}
			}

			unowned Gtk.Box pack_target = region_for(info.alignment);

			applets.insert(info.uuid, info);
			set_applets();

			info.applet.update_popovers(popover_manager); // the applet registers its popovers so they get layer-shell setup and visibility tracking
			info.applet.panel_size_changed(panel.intended_size, current_icon_size, current_small_icon_size); // bring the new applet up to the panel's current state
			info.applet.panel_position_changed(panel.position);

			pack_target.pack_start(info.applet, false, false, 0);
			pack_target.child_set(info.applet, "position", info.position);
			toggle_container_visibilities();

			ulong notify_id = info.notify.connect(applet_updated); // alignment and position edits from the settings UI arrive as property changes
			info.set_data("notify_id", notify_id);
			panel.applet_added(info);

			if (is_fully_loaded) {
				return;
			}

			lock (expected_uuids) {
				if (expected_uuids.is_empty()) { // that was the last one we were waiting for
					is_fully_loaded = true;
					on_fully_loaded();
				}
			}
		}

		/**
		* Every stored applet is in: settle the ordering, announce it, and run
		* a pending migration
		*/
		private void on_fully_loaded() {
			if (applets.size() < 1) {
				loaded();
				return;
			}

			initial_applet_placement(true, false); // applets arrived in plugin load order; settle regions first, then positions, now that all are here
			initial_applet_placement(false, true);

			panel.applets_changed();
			loaded();

			lock (need_migratory) {
				if (!need_migratory) {
					return;
				}
			}
			Timeout.add(500, add_migratory); // half a second later, so the user sees them added
		}

		/**
		* Re-homes (reparent) or re-indexes (reposition) every applet according
		* to its stored alignment and position
		*/
		private void initial_applet_placement(bool reparent = false, bool reposition = false) {
			if (!reparent && !reposition) {
				return;
			}
			unowned string? uuid;
			unowned Budgie.AppletInfo? info;

			var iter = HashTableIter<string?,Budgie.AppletInfo?>(applets);

			while (iter.next(out uuid, out info)) {
				if (reparent) {
					applet_reparent(info);
				}
				if (reposition) {
					applet_reposition(info);
				}
			}
		}

		/**
		* Sort order for insert_sorted: ascending stored position
		*/
		private static int compare_by_position(Budgie.AppletInfo? a, Budgie.AppletInfo? b) {
			return (int) (a.position > b.position) - (int) (a.position < b.position);
		}

		/**
		* Adds an applet of the plugin to the end of @target_region, or to the
		* region with the fewest applets when it is null
		*/
		private void add_new_applet_at(string plugin_name, Gtk.Box? target_region) {
			int position = (int) applets.size() + 1; // larger than any region's count, so the first region always wins the comparison below
			unowned Gtk.Box? target = null;
			string? alignment;

			Gtk.Box?[] regions = {
				start_box,
				center_box,
				end_box
			};

			if (target_region != null) { // internal adds such as migration name their region and go to its end
				var children = target_region.get_children();
				position = (int) (children.length());
				target = target_region;
			} else {
				foreach (var region in regions) { // otherwise the first region with the fewest applets wins
					var children = region.get_children();
					var child_count = children.length();
					if (child_count < position) {
						position = (int) child_count;
						target = region;
					}
				}
			}

			if (target == start_box) {
				alignment = "start";
			} else if (target == center_box) {
				alignment = "center";
			} else {
				alignment = "end";
			}

			string? uuid = LibUUID.new(UUIDFlags.LOWER_CASE|UUIDFlags.TIME_SAFE_TYPE);
			AppletInfo? info = new AppletInfo.from_uuid(uuid);
			info.alignment = alignment;

			var children = target.get_children();
			uint child_count = children.length();

			if (position >= child_count) { // safety clamp
				position = (int) child_count;
			}

			if (position < 0) {
				position = 0;
			}

			info.position = position;

			initial_config.insert(uuid, info); // add_applet() applies this slot once the instance exists
			add_new(plugin_name, uuid);
		}

		/**
		* Very simple right now: just add the migration's applets to the end
		* region
		*/
		private bool add_migratory() {
			lock (need_migratory) {
				if (!need_migratory) {
					return false;
				}
				need_migratory = false;
				foreach (var new_applet in MIGRATION_1_APPLETS) {
					debug("Adding migratory applet: %s", new_applet);
					add_new_applet_at(new_applet, end_box);
				}
			}
			return false;
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

			ulong notify_id = info.get_data("notify_id");
			SignalHandler.disconnect(info, notify_id); // stop reacting to property changes on an applet that is going away
			info.applet.get_parent().remove(info.applet);

			manager.reset_dconf_path(info.settings); // the AppletInfo's alignment, position and plugin name
			if (app_settings != null) {
				manager.reset_dconf_path(app_settings); // the applet's own configuration
			}
		}

		/**
		* The box an alignment names; anything but "start" and "end" lands in
		* the center
		*/
		private unowned Gtk.Box region_for(string alignment) {
			switch (alignment) {
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

			if (!is_fully_loaded) { // every applet arriving would otherwise resort the whole panel; on_fully_loaded() settles everything once
				return;
			}

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
			toggle_container_visibilities();

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
			toggle_container_visibilities();
		}

		/**
		* A region box is only shown while it has children, so an empty region
		* takes no space
		*/
		private void toggle_container_visibilities() {
			Gtk.Box?[] regions = { start_box, center_box, end_box };

			for (var i = 0; i < regions.length; i++) {
				Gtk.Box region = regions[i];

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
			string[]? uuids = null;
			unowned string? uuid;
			unowned Budgie.AppletInfo? plugin;

			var iter = HashTableIter<string,Budgie.AppletInfo?>(applets);
			while (iter.next(out uuid, out plugin)) {
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
			unowned string key;
			unowned Budgie.AppletInfo? other;
			unowned Budgie.AppletInfo? conflict = null;
			var iter = HashTableIter<string,Budgie.AppletInfo?>(applets);

			while (iter.next(out key, out other)) {
				if (other.alignment == info.alignment && other.position == info.position && info != other) {
					conflict = other;
					break;
				}
			}

			if (conflict == null) {
				return;
			}

			conflict.position = old_position;
		}

		/**
		* Shifts every position in the region after @after up by one so an
		* applet can be inserted; the default opens position 0
		*/
		private void open_gap(string alignment, int after = -1) {
			unowned string key;
			unowned Budgie.AppletInfo? info;
			var iter = HashTableIter<string,Budgie.AppletInfo?>(applets);

			while (iter.next(out key, out info)) {
				if (info.alignment == alignment) {
					if (info.position > after) {
						info.position++;
					}
				}
			}
			reinforce_positions();
		}

		/**
		* Shifts every position in the region after @after down by one to
		* close the slot an applet left behind
		*/
		private void close_gap(string alignment, int after) {
			unowned string key;
			unowned Budgie.AppletInfo? info;
			var iter = HashTableIter<string,Budgie.AppletInfo?>(applets);

			while (iter.next(out key, out info)) {
				if (info.alignment == alignment) {
					if (info.position > after) {
						info.position--;
					}
				}
			}
			reinforce_positions();
		}

		/**
		* Re-applies every stored position to its box after positions were
		* shifted; the property notifications alone would do it one applet at
		* a time
		*/
		private void reinforce_positions() {
			unowned string key;
			unowned Budgie.AppletInfo? info;
			var iter = HashTableIter<string,Budgie.AppletInfo?>(applets);

			while (iter.next(out key, out info)) {
				applet_reposition(info);
			}

			panel.queue_draw(); // we may have ugly artifacts now
		}
	}
}
