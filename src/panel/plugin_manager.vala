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
	public class PanelPluginManager {
		Settings settings;
		Peas.Engine engine;
		Peas.ExtensionSet extensions;

		HashTable<string,Peas.PluginInfo?> plugins;

		/**
		* Updated when specific names are queried
		*/
		public bool migrate_load_requirements_met = false;

		public PanelPluginManager() {
			plugins = new HashTable<string,Peas.PluginInfo?>(str_hash, str_equal);
			settings = new Settings(Budgie.ROOT_SCHEMA);

			engine = new Peas.Engine();
			engine.enable_loader("python3");

			/* Ensure libpeas doesn't freak the hell out for Python extensions */
			try {
				var repo = GI.Repository.get_default();
				repo.require("Peas", "1.0", 0);
				repo.require("PeasGtk", "1.0", 0);
				repo.require("Budgie", "2.0", 0);
			} catch (Error e) {
				message("Error loading typelibs: %s", e.message);
			}

			/* System path */
			var dir = Environment.get_user_data_dir();
			engine.add_search_path(Budgie.MODULE_DIRECTORY, Budgie.MODULE_DATA_DIRECTORY);
			if (Budgie.HAS_SECONDARY_PLUGIN_DIRS) {
				engine.add_search_path(Budgie.MODULE_DIRECTORY_SECONDARY, Budgie.MODULE_DATA_DIRECTORY_SECONDARY);
			}

			/* User path */
			var user_mod = Path.build_path(Path.DIR_SEPARATOR_S, dir, "budgie-desktop", "plugins");
			var hdata = Path.build_path(Path.DIR_SEPARATOR_S, dir, "budgie-desktop", "data");
			engine.add_search_path(user_mod, hdata);

			/* Legacy path */
			var hmod = Path.build_path(Path.DIR_SEPARATOR_S, dir, "budgie-desktop", "modules");
			if (FileUtils.test(hmod, FileTest.EXISTS)) {
				warning("Using legacy path %s, please migrate to %s", hmod, user_mod);
				message("Legacy %s path will not be supported in next major version", hmod);
				engine.add_search_path(hmod, hdata);
			}
			engine.rescan_plugins();

			extensions = new Peas.ExtensionSet(engine, typeof(Budgie.Plugin));

			extensions.extension_added.connect(on_extension_added);
			engine.load_plugin.connect_after((i) => {
				Peas.Extension? e = extensions.get_extension(i);
				if (e == null) {
					critical("Failed to find extension for: %s", i.get_name());
					return;
				}
				on_extension_added(i, e);
			});
		}

		string create_applet_path(string uuid) {
			return "%s/{%s}/".printf(Budgie.APPLET_PREFIX, uuid);
		}

		/**
		* Indicate that a plugin that was being waited for, is now available
		*/
		public signal void extension_loaded(string name);

		/**
		* Handle extension loading
		*/
		void on_extension_added(Peas.PluginInfo? info, Object p) {
			if (plugins.contains(info.get_name())) {
				return;
			}
			plugins.insert(info.get_name(), info);
			extension_loaded(info.get_name());
		}

		public bool is_extension_loaded(string name) {
			if (name in MIGRATION_1_APPLETS) {
				migrate_load_requirements_met = true;
			}
			return plugins.contains(name);
		}

		/**
		* Determine if the extension is known to be valid
		*/
		public bool is_extension_valid(string name) {
			if (name in MIGRATION_1_APPLETS) {
				migrate_load_requirements_met = true;
			}
			if (this.get_plugin_info(name) == null) {
				return false;
			}
			return true;
		}

		public List<Peas.PluginInfo?> get_all_plugins() {
			List<Peas.PluginInfo?> ret = new List<Peas.PluginInfo?>();
			foreach (unowned Peas.PluginInfo? info in this.engine.get_plugin_list()) {
				ret.append(info);
			}
			return ret;
		}

		public void rescan_plugins() {
			engine.garbage_collect();
			engine.rescan_plugins();
		}

		/**
		* PeasEngine.get_plugin_info == completely broken
		*/
		private unowned Peas.PluginInfo? get_plugin_info(string name) {
			foreach (unowned Peas.PluginInfo? info in this.engine.get_plugin_list()) {
				if (info.get_name() == name) {
					return info;
				}
			}
			return null;
		}

		public void modprobe(string name) {
			Peas.PluginInfo? i = this.get_plugin_info(name);
			if (i == null) {
				warning("budgie_panel_modprobe called for non existent module: %s", name);
				return;
			}
			this.engine.try_load_plugin(i);
		}

		/**
		* Attempt to load plugin, will set the plugin-name on failure
		*/
		public Budgie.AppletInfo? load_applet_instance(string? uuid, out string name, Settings? psettings = null) {
			var path = this.create_applet_path(uuid);
			Settings? settings = null;
			if (psettings == null) {
				settings = new Settings.with_path(Budgie.APPLET_SCHEMA, path);
			} else {
				settings = psettings;
			}
			var pname = settings.get_string(Budgie.APPLET_KEY_NAME);
			Peas.PluginInfo? pinfo = plugins.lookup(pname);

			/* Not yet loaded */
			if (pinfo == null) {
				pinfo = this.get_plugin_info(pname);
				if (pinfo == null) {
					warning("Trying to load invalid plugin: %s %s", pname, uuid);
					name = null;
					return null;
				}
				engine.try_load_plugin(pinfo);
				name = pname;
				return null;
			}
			var extension = extensions.get_extension(pinfo);
			if (extension == null) {
				name = pname;
				return null;
			}
			name = null;
			Budgie.Applet applet = ((Budgie.Plugin) extension).get_panel_widget(uuid);
			return new Budgie.AppletInfo(pinfo, uuid, applet, settings);
		}

		/**
		* Attempt to create a fresh applet instance
		*/
		public Budgie.AppletInfo? create_new_applet(string name, string uuid) {
			if (!plugins.contains(name)) return null;
			string? unused = null;

			var path = this.create_applet_path(uuid);
			var settings = new Settings.with_path(Budgie.APPLET_SCHEMA, path);
			settings.set_string(Budgie.APPLET_KEY_NAME, name);
			return this.load_applet_instance(uuid, out unused, settings);
		}
	}
}
