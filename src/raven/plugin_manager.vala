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
	public enum RavenWidgetCreationResult {
		SUCCESS,
		PLUGIN_INFO_MISSING,
		INVALID_MODULE_NAME,
		PLUGIN_LOAD_FAILED,
		SCHEMA_LOAD_FAILED,
		INSTANCE_CREATION_FAILED
	}

	public class RavenPluginManager {
		Peas.Engine engine;
		Peas.ExtensionSet plugin_set;

		HashTable<string, Peas.PluginInfo?> plugins;

		private const string WIDGET_INSTANCE_SETTINGS_PREFIX = "org/buddiesofbudgie/budgie-desktop/raven/widgets/instance-settings";
		private const string WIDGET_INSTANCE_INFO_PREFIX = "org/buddiesofbudgie/budgie-desktop/raven/widgets/instance-info";
		private const string WIDGET_INSTANCE_INFO_SCHEMA = "org.buddiesofbudgie.budgie-desktop.raven.widgets.instance-info";

		public RavenPluginManager() {
			plugins = new HashTable<string, Peas.PluginInfo?>(str_hash, str_equal);
		}

		/**
		* Initialise the plugin engine, paths, loaders, etc.
		*/
		public void setup_plugins() {
			engine = new Peas.Engine();
			engine.enable_loader("python");

			/* Ensure libpeas doesn't freak the hell out for Python plugins */
			try {
				var repo = GI.Repository.get_default();
				repo.require("Peas", "2", 0);
				repo.require("BudgieRaven", "1.0", 0);
			} catch (Error e) {
				message("Error loading typelibs: %s", e.message);
			}

			/* System path */
			var dir = Environment.get_user_data_dir();
			engine.add_search_path(Budgie.RAVEN_PLUGIN_LIBDIR, Budgie.RAVEN_PLUGIN_DATADIR);
			if (Budgie.HAS_SECONDARY_PLUGIN_DIRS) {
				engine.add_search_path(Budgie.RAVEN_PLUGIN_LIBDIR_SECONDARY, Budgie.RAVEN_PLUGIN_DATADIR_SECONDARY);
			}

			/* User path */
			var user_mod = Path.build_path(Path.DIR_SEPARATOR_S, dir, "budgie-desktop", "raven-plugins");
			var hdata = Path.build_path(Path.DIR_SEPARATOR_S, dir, "budgie-desktop", "raven-data");
			engine.add_search_path(user_mod, hdata);

			engine.rescan_plugins();

			plugin_set = new Peas.ExtensionSet.with_properties(engine, typeof(Budgie.RavenPlugin), {}, {});
			plugin_set.extension_added.connect(on_plugin_loaded);
		}

		/**
		* Handle plugin loading
		*/
		private void on_plugin_loaded(Peas.PluginInfo? info) {
			lock(plugins) {
				if (plugins.contains(info.get_module_name())) return;

				plugins.insert(info.get_module_name(), info);
			}
		}

		public bool is_plugin_loaded(string module_name) {
			lock (plugins) {
				return plugins.contains(module_name);
			}
		}

		public GLib.Settings? get_widget_info_from_uuid(string uuid) {
			return new GLib.Settings.with_path(WIDGET_INSTANCE_INFO_SCHEMA, "/%s/%s/".printf(WIDGET_INSTANCE_INFO_PREFIX, uuid));
		}

		public void clear_widget_instance_info(string uuid) {
			reset_dconf_path("/%s/%s/".printf(WIDGET_INSTANCE_INFO_PREFIX, uuid));
		}

		public void clear_widget_instance_settings(string uuid) {
			reset_dconf_path("/%s/%s/".printf(WIDGET_INSTANCE_SETTINGS_PREFIX, uuid));
		}

		public RavenWidgetCreationResult new_widget_instance_for_plugin(string module_name, string? existing_uuid, out RavenWidgetData? widget_data) {
			widget_data = null;

			Peas.PluginInfo? plugin_info = engine.get_plugin_info(module_name);
			if (plugin_info == null) return RavenWidgetCreationResult.PLUGIN_INFO_MISSING;

			var instance_settings_schema_name = module_name_to_schema_name(module_name);
			if (instance_settings_schema_name.split(".").length < 3) return RavenWidgetCreationResult.INVALID_MODULE_NAME;

			if (!is_plugin_loaded(module_name)) {
				engine.load_plugin(plugin_info);
			}
			var extension = plugin_set.get_extension(plugin_info);
			var plugin = extension as Budgie.RavenPlugin;

			var uuid = existing_uuid != null ? existing_uuid : generate_uuid();

			GLib.Settings? instance_settings = null;
			if (plugin.supports_settings()) {
				var instance_settings_path = "/%s/%s/".printf(WIDGET_INSTANCE_SETTINGS_PREFIX, uuid);

				if (!schema_exists(instance_settings_schema_name)) {
					warning(instance_settings_schema_name);
					return RavenWidgetCreationResult.SCHEMA_LOAD_FAILED;
				}

				instance_settings = new GLib.Settings.with_path(instance_settings_schema_name, instance_settings_path);
				instance_settings.ref();
			}

			var instance = plugin.new_widget_instance(uuid, instance_settings);
			if (instance == null) return RavenWidgetCreationResult.INSTANCE_CREATION_FAILED;

			var instance_info = get_widget_info_from_uuid(uuid);
			instance_info.set_string("module", module_name);

			widget_data = new RavenWidgetData(instance, plugin_info, uuid, plugin.supports_settings());
			return RavenWidgetCreationResult.SUCCESS;
		}

		public List<Peas.PluginInfo?> get_all_plugins() {
			List<Peas.PluginInfo?> ret = new List<Peas.PluginInfo?>();

			var list = this.engine.get_n_items();
			for (int i=0; i < list; i++) {
				Peas.PluginInfo? info = (Peas.PluginInfo)this.engine.get_item(i);
				if (info != null) {
					ret.append(info);
				}
			}

			return ret;
		}

		public void rescan_plugins() {
			engine.garbage_collect();
			engine.rescan_plugins();
		}

		public void modprobe(string module_name) {
			Peas.PluginInfo? i = engine.get_plugin_info(module_name);
			if (i == null) {
				warning("budgie_panel_modprobe called for non existent module: %s", module_name);
				return;
			}
			this.engine.load_plugin(i);
		}

		private static string module_name_to_schema_name(string module_name) {
			var schema_name = module_name;
			if (module_name.has_suffix(".so")) {
				schema_name = module_name.slice(0, module_name.last_index_of("."));
			}

			return schema_name.replace("_", ".");
		}

		private static bool schema_exists(string schema_name) {
			return SettingsSchemaSource.get_default().lookup(schema_name, true) != null;
		}

		private static string generate_uuid() {
			uint8 time[16];
			char uuid[37];

			LibUUID.generate(time);
			LibUUID.unparse_lower(time, uuid);

			return (string) uuid;
		}

		private static void reset_dconf_path(string path) {
			Settings.sync();

			string argv[] = { "dconf", "reset", "-f", path};
			message("Resetting dconf path: %s", path);

			try {
				Process.spawn_command_line_sync(string.joinv(" ", argv), null, null, null);
			} catch (Error e) {
				warning("Failed to reset dconf path %s: %s", path, e.message);
			}

			Settings.sync();
		}

		public signal void existing_widgets_loaded(List<RavenWidgetData> widgets);
	}

	public class RavenWidgetData {
		public Gtk.Bin widget_instance { public get; private set; }
		public Peas.PluginInfo plugin_info { public get; private set; }
		public string uuid { public get; private set; }
		public bool supports_settings { public get; private set; }

		public RavenWidgetData(Gtk.Bin widget_instance, Peas.PluginInfo plugin_info, string uuid, bool supports_settings) {
			this.widget_instance = widget_instance;
			this.plugin_info = plugin_info;
			this.uuid = uuid;
			this.supports_settings = supports_settings;
		}
	}
}
