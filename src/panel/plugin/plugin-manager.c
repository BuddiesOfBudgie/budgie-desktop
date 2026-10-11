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

#include "plugin-manager.h"

#include <girepository/girepository.h>
#include <libpeas-2/libpeas.h>

#include "applet.h"
#include "budgie-config.h"
#include "plugin.h"

/**
 * BudgiePanelPluginManagerError:
 * @BUDGIE_PANEL_PLUGIN_MANAGER_ERROR_INVALID: a plugin's info is invalid.
 * @BUDGIE_PANEL_PLUGIN_MANAGER_ERROR_LOAD_FAILED: a plugin is unable to be loaded.
 * @BUDGIE_PANEL_PLUGIN_MANAGER_ERROR_NOT_FOUND: the extension for a plugin could not be found.
 * @BUDGIE_PANEL_PLUGIN_MANAGER_ERROR_NOT_LOADED: a plugin is not yet loaded.
 *
 * Possible errors of panel plugin manager related functions.
 */

/**
 * BUDGIE_PANEL_PLUGIN_MANAGER_ERROR:
 *
 * The error domain of the Budgie panel plugin manager.
 */
G_DEFINE_QUARK(budgie_panel_plugin_manager_error, budgie_panel_plugin_manager_error)

enum {
	EXTENSION_LOADED,
	LAST_SIGNAL
};

static guint signals[LAST_SIGNAL];

struct _BudgiePanelPluginManager {
	GObject parent_instance;

	GSettings* settings;
	PeasEngine* engine;
	PeasExtensionSet* extensions;

	GHashTable* plugins;
	GHashTable* plugin_names;
};

static const gchar* panel_plugin_manager_get_plugin_name(BudgiePanelPluginManager* self, PeasPluginInfo* info);

G_DEFINE_FINAL_TYPE(BudgiePanelPluginManager, budgie_panel_plugin_manager, G_TYPE_OBJECT)

/******************************************************************************
 * Callbacks
 *****************************************************************************/

static void panel_plugin_manager_extension_added_cb(PeasExtensionSet* set, PeasPluginInfo* info, GObject* extension, gpointer data) {
	BudgiePanelPluginManager* self = data;
	const gchar* module_name = NULL;

	g_return_if_fail(PEAS_IS_PLUGIN_INFO(info));
	g_return_if_fail(extension != NULL);

	module_name = peas_plugin_info_get_module_name(info); // module names are unique and never translated

	if G_UNLIKELY (g_hash_table_contains(self->plugins, module_name)) {
		return;
	}

	g_hash_table_insert(self->plugins, g_strdup(module_name), g_object_ref(info));

	g_signal_emit(self, signals[EXTENSION_LOADED], 0, panel_plugin_manager_get_plugin_name(self, info));
}

/******************************************************************************
 * Helpers
 *****************************************************************************/

/**
 * panel_plugin_manager_create_applet_path:
 * @uuid: A plugin's UUID.
 *
 * Concatenates the object path for an applet.
 *
 * Returns: (not nullable) (transfer full): The applet path.
 */
static gchar* panel_plugin_manager_create_applet_path(const gchar* uuid) {
	return g_strdup_printf("%s/{%s}/", BUDGIE_APPLET_PREFIX, uuid);
}

/**
 * panel_plugin_manager_read_plugin_name:
 * @info: A #PeasPluginInfo.
 *
 * Reads the untranslated Name key from the .plugin file that @info was
 * created from, falling back to the localized name if the file can't be read.
 *
 * Returns: (transfer full): The untranslated plugin name.
 */
static gchar* panel_plugin_manager_read_plugin_name(PeasPluginInfo* info) {
	const gchar* module_dir = peas_plugin_info_get_module_dir(info);
	const gchar* module_name = peas_plugin_info_get_module_name(info);
	g_autoptr(GDir) dir = NULL;
	g_autoptr(GError) error = NULL;
	const gchar* file_name = NULL;

	dir = g_dir_open(module_dir, 0, &error);

	if (dir == NULL) {
		g_debug("Unable to read plugin directory for module '%s': %s", module_name, error->message);
		return g_strdup(peas_plugin_info_get_name(info)); // unreadable dir, use the localized name
	}

	while ((file_name = g_dir_read_name(dir)) != NULL) { // libpeas has no getter for the .plugin path, but it sits in the module dir
		g_autofree gchar* path = NULL;
		g_autoptr(GKeyFile) key_file = NULL;
		g_autoptr(GError) load_error = NULL;
		g_autofree gchar* module = NULL;
		gchar* name = NULL;

		if (!g_str_has_suffix(file_name, ".plugin")) { // skip the module itself and data files
			continue;
		}

		path = g_build_filename(module_dir, file_name, NULL);
		key_file = g_key_file_new();

		if (!g_key_file_load_from_file(key_file, path, G_KEY_FILE_NONE, &load_error)) {
			g_debug("Unable to read plugin file '%s': %s", path, load_error->message);
			continue;
		}

		module = g_key_file_get_string(key_file, "Plugin", "Module", NULL);

		if (g_strcmp0(module, module_name) != 0) { // another plugin sharing this dir
			continue;
		}

		name = g_key_file_get_string(key_file, "Plugin", "Name", NULL); // get_string ignores Name[locale] entries

		if (name != NULL) {
			return name;
		}
	}

	return g_strdup(peas_plugin_info_get_name(info)); // no matching .plugin file, use the localized name
}

/**
 * panel_plugin_manager_get_plugin_name:
 * @self: A #BudgiePanelPluginManager instance.
 * @info: A #PeasPluginInfo.
 *
 * Gets the untranslated name of @info, which identifies the plugin in
 * applet settings and layout files.
 *
 * Returns: (transfer none): The untranslated plugin name.
 */
static const gchar* panel_plugin_manager_get_plugin_name(BudgiePanelPluginManager* self, PeasPluginInfo* info) {
	gchar* name = g_hash_table_lookup(self->plugin_names, info);

	if (name != NULL) { // already read from disk
		return name;
	}

	name = panel_plugin_manager_read_plugin_name(info);
	g_hash_table_insert(self->plugin_names, g_object_ref(info), name); // cache it, lookups run once per plugin per applet

	return name;
}

/**
 * panel_plugin_manager_find_plugin_info:
 * @self: A #BudgiePanelPluginManager instance.
 * @name: A plugin name.
 * @localized: Whether to compare @name against the localized name.
 *
 * Gets the #PeasPluginInfo whose untranslated or localized name is @name,
 * or %NULL if no plugin matches.
 *
 * Returns: (transfer full): The #PeasPluginInfo corresponding to @name.
 */
static PeasPluginInfo* panel_plugin_manager_find_plugin_info(BudgiePanelPluginManager* self, const gchar* name, gboolean localized) {
	guint i = 0;
	PeasPluginInfo* info = NULL;
	const gchar* found_name = NULL;

	while ((info = g_list_model_get_item(G_LIST_MODEL(self->engine), i)) != NULL) {
		i++;

		if (!PEAS_IS_PLUGIN_INFO(info)) {
			g_clear_object(&info);
			continue;
		}

		found_name = localized ? peas_plugin_info_get_name(info) : panel_plugin_manager_get_plugin_name(self, info);

		if (g_str_equal(found_name, name)) { // return this info with its ref
			break;
		}

		g_clear_object(&info);
	}

	return info;
}

/**
 * panel_plugin_manager_get_plugin_info:
 * @self: A #BudgiePanelPluginManager instance.
 * @name: A plugin name.
 *
 * Gets the #PeasPluginInfo corresponding to a plugin with @name,
 * or %NULL if no plugin with @name is found. @name is matched as a
 * module name, then as the untranslated name, then as the localized one.
 *
 * Returns: (transfer full): The #PeasPluginInfo corresponding to @name.
 */
static PeasPluginInfo* panel_plugin_manager_get_plugin_info(BudgiePanelPluginManager* self, const gchar* name) {
	PeasPluginInfo* info = peas_engine_get_plugin_info(self->engine, name);

	if (info != NULL) { // matched the module name, the engine keeps ownership
		return g_object_ref(info);
	}

	info = panel_plugin_manager_find_plugin_info(self, name, FALSE);

	if (info != NULL) { // matched the untranslated name
		return info;
	}

	return panel_plugin_manager_find_plugin_info(self, name, TRUE); // 10.10.3 stored localized names, and the chooser passes them
}

/******************************************************************************
 * GObject
 *****************************************************************************/

static void panel_plugin_manager_finalize(GObject* obj) {
	BudgiePanelPluginManager* self;

	self = BUDGIE_PANEL_PLUGIN_MANAGER(obj);

	g_clear_object(&self->settings);
	g_clear_object(&self->extensions);
	g_clear_object(&self->engine);
	g_clear_pointer(&self->plugins, g_hash_table_unref);
	g_clear_pointer(&self->plugin_names, g_hash_table_unref);

	G_OBJECT_CLASS(budgie_panel_plugin_manager_parent_class)->finalize(obj);
}

static void budgie_panel_plugin_manager_class_init(BudgiePanelPluginManagerClass* klazz) {
	GObjectClass* class = G_OBJECT_CLASS(klazz);

	class->finalize = panel_plugin_manager_finalize;

	/**
	 * BudgiePanelPluginManager::extension-loaded:
	 * @self: A #BudgiePanelPluginManager instance.
	 * @plugin_name: The name of the loaded extension.
	 *
	 * Emitted when an extension has been added to
	 * the #PeasEngine.
	 */
	signals[EXTENSION_LOADED] = g_signal_new("extension-loaded",
		G_TYPE_FROM_CLASS(klazz),
		G_SIGNAL_RUN_LAST,
		0,
		NULL, NULL, NULL,
		G_TYPE_NONE,
		1,
		G_TYPE_STRING);
}

static void budgie_panel_plugin_manager_init(BudgiePanelPluginManager* self) {
	const gchar* user_data_dir;
	g_autofree gchar* user_mod_dir = NULL;
	g_autofree gchar* hdata_dir = NULL;
	g_autofree gchar* hmod_dir = NULL;
	g_autoptr(GError) error = NULL;

	self->plugins = g_hash_table_new(g_str_hash, g_str_equal);
	self->plugin_names = g_hash_table_new_full(g_direct_hash, g_direct_equal, g_object_unref, g_free);
	self->settings = g_settings_new("com.solus-project.budgie-panel");
	self->engine = peas_engine_new();

	peas_engine_enable_loader(self->engine, "python");

	/* Ensure libpeas doesn't freak the hell out for Python extensions */

	static GIRepository* repository;

#if GLIB_CHECK_VERSION(2, 85, 0)
	repository = gi_repository_dup_default();
#else
	repository = gi_repository_new();
#endif

	gi_repository_require(repository, "Peas", "2", 0, &error);

	if G_UNLIKELY (error) {
		g_warning("Error loading typelibs: %s", error->message);
		g_clear_error(error);
	}

	gi_repository_require(repository, "Budgie", "3.0", 0, &error);

	if G_UNLIKELY (error) {
		g_warning("Error loading typelibs: %s", error->message);
		g_clear_error(error);
	}

	/* System path */
	peas_engine_add_search_path(self->engine, BUDGIE_MODULE_DIRECTORY, BUDGIE_MODULE_DATA_DIRECTORY);

	if (BUDGIE_HAS_SECONDARY_PLUGIN_DIRS) {
		peas_engine_add_search_path(self->engine, BUDGIE_MODULE_DIRECTORY_SECONDARY, BUDGIE_MODULE_DATA_DIRECTORY_SECONDARY);
	}

	/* User path */
	user_data_dir = g_get_user_data_dir();
	user_mod_dir = g_build_path(G_DIR_SEPARATOR_S, user_data_dir, "budgie-desktop", "plugins", NULL);
	hdata_dir = g_build_path(G_DIR_SEPARATOR_S, user_data_dir, "budgie-desktop", "data", NULL);

	peas_engine_add_search_path(self->engine, user_mod_dir, hdata_dir);

	/* Scan and collect our plugins */
	peas_engine_rescan_plugins(self->engine);

	self->extensions = peas_extension_set_new(self->engine, BUDGIE_TYPE_PLUGIN, NULL);

	peas_extension_set_foreach(self->extensions, (PeasExtensionSetForeachFunc) panel_plugin_manager_extension_added_cb, self);
	g_signal_connect(self->extensions, "extension-added", G_CALLBACK(panel_plugin_manager_extension_added_cb), self);
}

/******************************************************************************
 * Public API
 *****************************************************************************/

/**
 * budgie_panel_plugin_manager_new:
 *
 * Creates a new #BudgiePanelPluginManager object.
 *
 * During creation, a new #PeasEngine instance will be created. We
 * add a few directories for the engine to search for plugins:
 *
 * 1) The main configured %BUDGIE_MODULE_DIRECTORY
 * 2) A secondary configured $BUDGIE_MODULE_DIRECTORY_SECONDARY, if set
 * 3) XDG_DATA_HOME/budgie-desktop/plugins
 * 4) XDG_DATA_HOME/budgie-desktop/modules (legacy)
 *
 * The engine then scans for plugins.
 *
 * Returns: (transfer full): A new #BudgiePanelPluginManager object.
 */
BudgiePanelPluginManager* budgie_panel_plugin_manager_new() {
	return g_object_new(BUDGIE_TYPE_PANEL_PLUGIN_MANAGER, NULL);
}

/**
 * budgie_panel_plugin_manager_get_all_plugins:
 * @self: A #BudgiePanelPluginManager
 *
 * Gets all of the loaded plugins, or %NULL if no plugins have been
 * loaded by the Peas engine.
 *
 * Returns: (transfer full): A #GList of #PeasPluginInfo of all loaded
 *   plugins.
 */
GList* budgie_panel_plugin_manager_get_all_plugins(BudgiePanelPluginManager* self) {
	GList* plugins = NULL;
	gint i = 0;
	PeasPluginInfo* info = NULL;

	g_return_val_if_fail(BUDGIE_IS_PANEL_PLUGIN_MANAGER(self), NULL);

	while ((info = g_list_model_get_item(G_LIST_MODEL(self->engine), i)) != NULL) {
		i++;

		if (!PEAS_IS_PLUGIN_INFO(info)) {
			g_clear_object(&info);
			continue;
		}

		plugins = g_list_prepend(plugins, g_object_ref(info));

		g_clear_object(&info);
	}

	plugins = g_list_reverse(plugins);

	return plugins;
}

/**
 * budgie_panel_plugin_manager_is_plugin_loaded:
 * @self: A #BudgiePanelPluginManager instance.
 * @name: The name of a plugin.
 *
 * Checks if the plugin with the name @name is loaded.
 *
 * Returns: %TRUE if the plugin is loaded, %FALSE otherwise.
 */
gboolean budgie_panel_plugin_manager_is_plugin_loaded(BudgiePanelPluginManager* self, const gchar* name) {
	g_autoptr(PeasPluginInfo) info = NULL;

	g_return_val_if_fail(BUDGIE_IS_PANEL_PLUGIN_MANAGER(self), FALSE);
	g_return_val_if_fail(name != NULL, FALSE);

	info = panel_plugin_manager_get_plugin_info(self, name); // resolve a localized name to its plugin

	if (!PEAS_IS_PLUGIN_INFO(info)) {
		return FALSE;
	}

	return g_hash_table_contains(self->plugins, peas_plugin_info_get_module_name(info));
}

/**
 * budgie_panel_plugin_manager_is_plugin_valid:
 * @self: A #BudgiePanelPluginManager instance.
 * @name: The name of a plugin.
 *
 * Checks if the plugin with name @name is valid. We do this
 * by trying to get the #PeasPluginInfo with @name, and returning
 * %TRUE if it is found.
 *
 * Returns: %TRUE if the plugin is valid, %FALSE otherwise.
 */
gboolean budgie_panel_plugin_manager_is_plugin_valid(BudgiePanelPluginManager* self, const gchar* name) {
	g_autoptr(PeasPluginInfo) info = NULL;

	g_return_val_if_fail(BUDGIE_IS_PANEL_PLUGIN_MANAGER(self), FALSE);
	g_return_val_if_fail(name != NULL, FALSE);

	info = panel_plugin_manager_get_plugin_info(self, name);

	return PEAS_IS_PLUGIN_INFO(info);
}

/**
 * budgie_panel_plugin_manager_rescan_plugins:
 * @self: A #BudgiePanelPluginManager instance.
 *
 * Triggers a re-scan by the #PeasEngine for plugins.
 */
void budgie_panel_plugin_manager_rescan_plugins(BudgiePanelPluginManager* self) {
	g_return_if_fail(BUDGIE_IS_PANEL_PLUGIN_MANAGER(self));

	peas_engine_garbage_collect(self->engine);
	peas_engine_rescan_plugins(self->engine);
}

/**
 * budgie_panel_plugin_manager_modprobe:
 * @self: A #BudgiePanelPluginManager instance.
 * @name: The name of a plugin.
 *
 * Tells the #PeasEngine to load the plugin with the name @name.
 */
void budgie_panel_plugin_manager_modprobe(BudgiePanelPluginManager* self, const gchar* name) {
	g_autoptr(PeasPluginInfo) info = NULL;

	g_return_if_fail(BUDGIE_IS_PANEL_PLUGIN_MANAGER(self));
	g_return_if_fail(name != NULL);

	info = panel_plugin_manager_get_plugin_info(self, name);

	if G_UNLIKELY (!PEAS_IS_PLUGIN_INFO(info)) {
		g_warning("modprobe called for non existent module: %s", name);
		return;
	}

	if (!peas_engine_load_plugin(self->engine, info)) {
		g_warning("Failed to load plugin with name '%s'", name);
	}
}

/**
 * budgie_panel_plugin_manager_load_applet_instance:
 * @self: A #BudgiePanelPluginManager instance.
 * @uuid: A plugin's UUID.
 * @settings: (optional): The plugin's #GSettings instance.
 * @name: (out callee-allocates): (optional): A return location for a plugin's name.
 * @err: (out callee-allocates): (optional): A return location for a #GError.
 *
 * Attempt to load an instance of a Budgie plugin, loading the plugin
 * itself first if needed. If the plugin could not be loaded, %NULL will
 * be returned, and @err will be set.
 *
 * Returns: (transfer full): The plugin's #BudgieAppletInfo if loaded, or %NULL.
 */
BudgieAppletInfo* budgie_panel_plugin_manager_load_applet_instance(BudgiePanelPluginManager* self, const gchar* uuid, GSettings* plugin_settings, gchar** name, GError** err) {
	g_autofree gchar* path = NULL;
	g_autoptr(GSettings) settings = NULL;
	g_autofree gchar* plugin_name = NULL;
	g_autofree gchar* module_name = NULL;
	const gchar* stored_name = NULL;
	const gchar* stored_module = NULL;
	g_autoptr(PeasPluginInfo) info = NULL;
	GObject* extension = NULL;
	BudgieApplet* applet = NULL;

	g_return_val_if_fail(BUDGIE_IS_PANEL_PLUGIN_MANAGER(self), NULL);
	g_return_val_if_fail(uuid != NULL, NULL);
	g_return_val_if_fail(name == NULL || *name == NULL, NULL);
	g_return_val_if_fail(err == NULL || *err == NULL, NULL);

	// Make sure we have a valid settings instance for the plugin
	path = panel_plugin_manager_create_applet_path(uuid);

	if (plugin_settings == NULL) {
		settings = g_settings_new_with_path(BUDGIE_APPLET_SCHEMA, path);
	} else {
		settings = g_object_ref(plugin_settings);
	}

	plugin_name = g_settings_get_string(settings, BUDGIE_APPLET_KEY_NAME);
	module_name = g_settings_get_string(settings, BUDGIE_APPLET_KEY_MODULE);

	if (*module_name != '\0') { // prefer the module, it never changes with the locale
		info = panel_plugin_manager_get_plugin_info(self, module_name);
	}

	if (!PEAS_IS_PLUGIN_INFO(info)) { // no module stored yet, or the plugin renamed its module
		info = panel_plugin_manager_get_plugin_info(self, plugin_name);
	}

	if (!PEAS_IS_PLUGIN_INFO(info)) {
		g_set_error(err,
			BUDGIE_PANEL_PLUGIN_MANAGER_ERROR,
			BUDGIE_PANEL_PLUGIN_MANAGER_ERROR_INVALID,
			"Tried to load invalid plugin '%s' with UUID %s", plugin_name, uuid);
		*name = g_strdup(plugin_name);
		return NULL;
	}

	stored_module = peas_plugin_info_get_module_name(info);

	stored_name = panel_plugin_manager_get_plugin_name(self, info);

	if (!g_str_equal(module_name, stored_module)) { // add the module to applets saved before the key existed
		if (g_settings_set_string(settings, BUDGIE_APPLET_KEY_MODULE, stored_module)) {
			g_message("Migrated applet '%s' with UUID %s to module '%s'", stored_name, uuid, stored_module);
		} else {
			g_warning("Unable to migrate applet '%s' with UUID %s to module '%s': settings are not writable", stored_name, uuid, stored_module);
		}
	}

	if (!g_str_equal(plugin_name, stored_name)) { // replace a localized name saved by 10.10.3
		if (g_settings_set_string(settings, BUDGIE_APPLET_KEY_NAME, stored_name)) {
			g_message("Migrated applet with UUID %s from localized name '%s' to '%s'", uuid, plugin_name, stored_name);
		} else {
			g_warning("Unable to migrate applet with UUID %s from localized name '%s' to '%s': settings are not writable", uuid, plugin_name, stored_name);
		}

		g_free(plugin_name); // load with the untranslated name even if the write failed
		plugin_name = g_strdup(stored_name);
	}

	if (!g_hash_table_contains(self->plugins, stored_module)) { // load the plugin on first use
		// Synchronous: the extension-added handler has registered the plugin by the time this returns
		if (!peas_engine_load_plugin(self->engine, info)) {
			g_set_error(err,
				BUDGIE_PANEL_PLUGIN_MANAGER_ERROR,
				BUDGIE_PANEL_PLUGIN_MANAGER_ERROR_LOAD_FAILED,
				"Unable to load plugin '%s' with UUID %s", plugin_name, uuid);
			*name = g_strdup(plugin_name);
			return NULL;
		}

		// Loaded, but it provides no Budgie applet extension
		if (!g_hash_table_contains(self->plugins, stored_module)) {
			g_set_error(err,
				BUDGIE_PANEL_PLUGIN_MANAGER_ERROR,
				BUDGIE_PANEL_PLUGIN_MANAGER_ERROR_NOT_FOUND,
				"Plugin '%s' with UUID %s loaded but provides no applet", plugin_name, uuid);
			*name = g_strdup(plugin_name);
			return NULL;
		}
	}

	extension = peas_extension_set_get_extension(self->extensions, info);

	if (!extension) {
		g_set_error(err,
			BUDGIE_PANEL_PLUGIN_MANAGER_ERROR,
			BUDGIE_PANEL_PLUGIN_MANAGER_ERROR_NOT_FOUND,
			"Could not find extension for plugin '%s' with UUID %s", plugin_name, uuid);
		*name = g_strdup(plugin_name);
		return NULL;
	}

	applet = budgie_plugin_get_panel_widget(BUDGIE_PLUGIN(extension), uuid);

	return budgie_applet_info_new(info, uuid, applet, settings);
}

/**
 * budgie_panel_plugin_manager_create_applet:
 * @self: A #BudgiePanelPluginManager instance.
 * @name: The name of a plugin.
 * @uuid: The UUID of a plugin.
 * @err: (out callee-allocates): (optional): A return location for a #GError.
 *
 * Attempts to create a new instance of a Budgie panel applet,
 * and returning the resulting #BudgieAppletInfo. If the applet
 * could not be loaded, i.e. if it hasn't been loaded by the #PeasEngine,
 * this function returns %NULL.
 *
 * Returns: (transfer full): The #BudgieAppletInfo for this plugin.
 */
BudgieAppletInfo* budgie_panel_plugin_manager_create_applet(BudgiePanelPluginManager* self, const gchar* name, const gchar* uuid, GError** err) {
	g_autofree gchar* path = NULL;
	g_autoptr(GSettings) settings = NULL;
	g_autoptr(PeasPluginInfo) plugin_info = NULL;
	BudgieAppletInfo* info = NULL;
	GError* temp_err = NULL;

	g_return_val_if_fail(BUDGIE_IS_PANEL_PLUGIN_MANAGER(self), NULL);
	g_return_val_if_fail(name != NULL, NULL);
	g_return_val_if_fail(uuid != NULL, NULL);
	g_return_val_if_fail(err == NULL || *err == NULL, NULL);

	plugin_info = panel_plugin_manager_get_plugin_info(self, name); // the chooser passes the localized name

	if G_UNLIKELY (!PEAS_IS_PLUGIN_INFO(plugin_info)) {
		g_set_error(err,
			BUDGIE_PANEL_PLUGIN_MANAGER_ERROR,
			BUDGIE_PANEL_PLUGIN_MANAGER_ERROR_INVALID,
			"Attempted to create an invalid plugin: %s", name);
		return NULL;
	}

	if G_UNLIKELY (!g_hash_table_contains(self->plugins, peas_plugin_info_get_module_name(plugin_info))) {
		g_set_error(err,
			BUDGIE_PANEL_PLUGIN_MANAGER_ERROR,
			BUDGIE_PANEL_PLUGIN_MANAGER_ERROR_NOT_LOADED,
			"Attempted to create a plugin that isn't loaded: %s", name);
		return NULL;
	}

	path = panel_plugin_manager_create_applet_path(uuid);
	settings = g_settings_new_with_path(BUDGIE_APPLET_SCHEMA, path);

	g_settings_set_string(settings, BUDGIE_APPLET_KEY_MODULE, peas_plugin_info_get_module_name(plugin_info));
	g_settings_set_string(settings, BUDGIE_APPLET_KEY_NAME, panel_plugin_manager_get_plugin_name(self, plugin_info)); // untranslated, for versions that only read name

	info = budgie_panel_plugin_manager_load_applet_instance(self, uuid, settings, NULL, &temp_err);

	if (!BUDGIE_IS_APPLET_INFO(info)) {
		g_propagate_error(err, temp_err);
		return NULL;
	}

	return info;
}
