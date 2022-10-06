/*
 * This file is part of budgie-desktop
 *
 * Copyright © 2015-2022 Budgie Desktop Developers
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 */

namespace Budgie {
	public class RavenPluginManager {
		Peas.Engine engine;
		Peas.ExtensionSet plugin_set;

		HashTable<string, Peas.PluginInfo?> plugins;

		/**
		* Initialise the plugin engine, paths, loaders, etc.
		*/
		public void setup_plugins() {
			engine = new Peas.Engine();
			engine.enable_loader("python3");

			/* Ensure libpeas doesn't freak the hell out for Python plugins */
			try {
				var repo = GI.Repository.get_default();
				repo.require("Peas", "1.0", 0);
				repo.require("PeasGtk", "1.0", 0);
				repo.require("Budgie", "1.0", 0);
			} catch (Error e) {
				message("Error loading typelibs: %s", e.message);
			}

			/* System path */
			var dir = Environment.get_user_data_dir();
			engine.add_search_path(Budgie.RAVEN_PLUGIN_LIBDIR, Budgie.RAVEN_PLUGIN_DATADIR);

			/* User path */
			var user_mod = Path.build_path(Path.DIR_SEPARATOR_S, dir, "budgie-desktop", "raven-plugins");
			var hdata = Path.build_path(Path.DIR_SEPARATOR_S, dir, "budgie-desktop", "raven-data");
			engine.add_search_path(user_mod, hdata);

			engine.rescan_plugins();

			plugin_set = new Peas.ExtensionSet(engine, typeof(Budgie.RavenPlugin));

			plugin_set.extension_added.connect(on_plugin_added);
			engine.load_plugin.connect_after((i) => {
				Peas.Extension? e = plugin_set.get_extension(i);
				if (e == null) {
					critical("Failed to find plugin for: %s", i.get_name());
					return;
				}
				on_plugin_added(i, e);
			});
		}

		/**
		* Indicate that a plugin that was being waited for, is now available
		*/
		public signal void plugin_loaded(string module_name);

		/**
		* Handle plugin loading
		*/
		void on_plugin_added(Peas.PluginInfo? info, Object p) {
			if (plugins.contains(info.get_module_name())) {
				return;
			}
			plugins.insert(info.get_module_name(), info);
			plugin_loaded(info.get_module_name());
		}

		public bool is_plugin_loaded(string module_name) {
			return plugins.contains(module_name);
		}

		/**
		* Determine if the plugin is known to be valid
		*/
		public bool is_plugin_valid(string module_name) {
			return get_plugin_info(module_name) != null;
		}

		public List<Peas.PluginInfo?> get_raven_plugins() {
			List<Peas.PluginInfo?> ret = new List<Peas.PluginInfo?>();
			foreach (unowned Peas.PluginInfo? info in this.engine.get_plugin_list()) {
				ret.append(info);
			}
			return ret;
		}

		/**
		* PeasEngine.get_plugin_info == completely broken
		*/
		private unowned Peas.PluginInfo? get_plugin_info(string module_name) {
			foreach (unowned Peas.PluginInfo? info in engine.get_plugin_list()) {
				if (info.get_module_name() == module_name) {
					return info;
				}
			}
			return null;
		}

		public void modprobe(string module_name) {
			Peas.PluginInfo? i = get_plugin_info(module_name);
			if (i == null) {
				warning("budgie_panel_modprobe called for non existent module: %s", module_name);
				return;
			}
			this.engine.try_load_plugin(i);
		}
	}
}
