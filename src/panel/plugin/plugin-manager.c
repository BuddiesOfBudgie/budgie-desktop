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

#include "budgie-config.h"
#include "applet.h"
#include "plugin.h"

#include <gobject-introspection-1.0/girepository.h>
#include <libpeas-2/libpeas.h>

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

	GSettings *settings;
	PeasEngine *engine;
	PeasExtensionSet *extensions;

	GHashTable *plugins;
};

G_DEFINE_FINAL_TYPE(BudgiePanelPluginManager, budgie_panel_plugin_manager, G_TYPE_OBJECT)

static void panel_plugin_manager_constructed(GObject *obj);
static void panel_plugin_manager_finalize(GObject *obj);
static void extension_added(PeasExtensionSet *set, PeasPluginInfo *info, GObject *extension, gpointer data);
static gboolean is_migration_plugin(BudgiePanelPluginManager *self, const gchar *name);
static PeasPluginInfo *get_plugin_info(BudgiePanelPluginManager *self, const gchar *name);
static gchar *create_applet_path(const gchar* uuid);

static void budgie_panel_plugin_manager_class_init(BudgiePanelPluginManagerClass *klazz) {
	GObjectClass* class = G_OBJECT_CLASS(klazz);

	class->constructed = panel_plugin_manager_constructed;
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

static void budgie_panel_plugin_manager_init(BudgiePanelPluginManager *self) {
	const gchar *user_data_dir;
	g_autofree gchar *user_mod_dir = NULL;
	g_autofree gchar *hdata_dir = NULL;
	g_autofree gchar *hmod_dir = NULL;
	g_autoptr(GError) error = NULL;

	self->plugins = g_hash_table_new(g_str_hash, g_str_equal);
	self->settings = g_settings_new("com.solus-project.budgie-panel");
	self->engine = peas_engine_new();

	peas_engine_enable_loader(self->engine, "python");

	/* Ensure libpeas doesn't freak the hell out for Python extensions */

	g_irepository_require(NULL, "Peas", "2", 0, &error);

	if G_UNLIKELY (error) {
		g_warning("Error loading typelibs: %s", error->message);
		g_clear_error(error);
	}

	g_irepository_require(NULL, "Budgie", "1.0", 0, &error);

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

	peas_extension_set_foreach(self->extensions, (PeasExtensionSetForeachFunc) extension_added, self);
	g_signal_connect(self->extensions, "extension-added", G_CALLBACK(extension_added), self);
}

static void panel_plugin_manager_constructed(GObject *obj) {}

static void panel_plugin_manager_finalize(GObject *obj) {
	BudgiePanelPluginManager *self;

	self = BUDGIE_PANEL_PLUGIN_MANAGER(obj);

	g_object_unref(self->settings);
	g_object_unref(self->extensions);
	g_object_unref(self->engine);

	g_hash_table_unref(self->plugins);

	G_OBJECT_CLASS(budgie_panel_plugin_manager_parent_class)->finalize(obj);
}

static void extension_added(PeasExtensionSet *set, PeasPluginInfo *info, GObject *extension, gpointer data) {
	g_return_if_fail(PEAS_IS_PLUGIN_INFO(info));
	g_return_if_fail(extension != NULL);

	BudgiePanelPluginManager *self = data;
	gchar *plugin_name = NULL;

	plugin_name = peas_plugin_info_get_name(info);

	if G_UNLIKELY (g_hash_table_contains(self->plugins, plugin_name)) {
		return;
	}

	g_hash_table_insert(self->plugins, g_strdup(plugin_name), g_object_ref(info));
	g_signal_emit(self, signals[EXTENSION_LOADED], 0, g_strdup(plugin_name));
}

/**
 * get_plugin_info:
 * @self: A #BudgiePanelPluginManager instance.
 * @name: A plugin name.
 *
 * Gets the #PeasPluginInfo corresponding to a plugin with @name,
 * or %NULL if no plugin with @name is found.
 *
 * Returns: (transfer full): The #PeasPluginInfo corresponding to @name.
 */
static PeasPluginInfo *get_plugin_info(BudgiePanelPluginManager *self, const gchar *name) {
	GListModel *list = (GListModel *)self->engine;
	gint i, n_items = g_list_model_get_n_items(list);

	for (i = 0; i < n_items; i++) {
		PeasPluginInfo *info = (PeasPluginInfo *)g_list_model_get_item(list, i);
		gchar *found_name = peas_plugin_info_get_name(info);

		if (g_strcmp0(found_name, name) == 0) {
			return info;
		}
	}

	return NULL;
}

/**
 * create_applet_path:
 * @uuid: A plugin's UUID.
 *
 * Concatenates the object path for an applet.
 *
 * Returns: (not nullable) (transfer full): The applet path.
 */
static gchar *create_applet_path(const gchar* uuid) {
	return g_strdup_printf("%s/{%s}/", BUDGIE_APPLET_PREFIX, uuid);
}


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
BudgiePanelPluginManager *budgie_panel_plugin_manager_new() {
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
GList *budgie_panel_plugin_manager_get_all_plugins(BudgiePanelPluginManager *self) {
	g_return_val_if_fail(BUDGIE_IS_PANEL_PLUGIN_MANAGER(self), NULL);

	GList *plugins = NULL;
	GListModel *list = (GListModel *)self->engine;
	gint i, n_items = g_list_model_get_n_items(list);

	for (i = 0; i < n_items; i++) {
		PeasPluginInfo *info = (PeasPluginInfo *)g_list_model_get_item(list, i);
		plugins = g_list_append(plugins, info);
	}

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
gboolean budgie_panel_plugin_manager_is_plugin_loaded(BudgiePanelPluginManager *self, const gchar *name) {
	g_return_val_if_fail(BUDGIE_IS_PANEL_PLUGIN_MANAGER(self), FALSE);
	g_return_val_if_fail(name != NULL, FALSE);

	return g_hash_table_contains(self->plugins, name);
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
gboolean budgie_panel_plugin_manager_is_plugin_valid(BudgiePanelPluginManager *self, const gchar *name) {
	g_return_val_if_fail(BUDGIE_IS_PANEL_PLUGIN_MANAGER(self), FALSE);
	g_return_val_if_fail(name != NULL, FALSE);

	g_autoptr(PeasPluginInfo) info = NULL;

	info = get_plugin_info(self, name);

	return PEAS_IS_PLUGIN_INFO(info);
}

/**
 * budgie_panel_plugin_manager_rescan_plugins:
 * @self: A #BudgiePanelPluginManager instance.
 *
 * Triggers a re-scan by the #PeasEngine for plugins.
 */
void budgie_panel_plugin_manager_rescan_plugins(BudgiePanelPluginManager *self) {
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
void budgie_panel_plugin_manager_modprobe(BudgiePanelPluginManager *self, const gchar *name) {
	g_return_if_fail(BUDGIE_IS_PANEL_PLUGIN_MANAGER(self));
	g_return_if_fail(name != NULL);

	g_autoptr(PeasPluginInfo) info = NULL;
	gboolean success = FALSE;

	info = get_plugin_info(self, name);

	if G_UNLIKELY (!PEAS_IS_PLUGIN_INFO(info)) {
		g_warning("modprobe called for non existent module: %s", name);
		return;
	}

	success = peas_engine_load_plugin(self->engine, info);

	if (!success) {
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
 * Attempt to load an instance of a Budgie plugin. If the plugin
 * could not be loaded, %NULL will be returned, and @err will be set.
 *
 * Returns: (transfer full): The plugin's #BudgieAppletInfo if loaded, or %NULL.
 */
BudgieAppletInfo *budgie_panel_plugin_manager_load_applet_instance(BudgiePanelPluginManager *self, const gchar *uuid, GSettings *plugin_settings, gchar **name, GError **err) {
	g_return_val_if_fail(BUDGIE_IS_PANEL_PLUGIN_MANAGER(self), NULL);
	g_return_val_if_fail(uuid != NULL, NULL);
	g_return_val_if_fail(name == NULL || *name == NULL, NULL);
	g_return_val_if_fail(err == NULL || *err == NULL, NULL);

	g_autofree gchar *path = NULL;
	g_autoptr(GSettings) settings = NULL;
	g_autofree gchar *plugin_name = NULL;
	g_autoptr(PeasPluginInfo) info = NULL;
	GObject *extension = NULL;
	BudgieApplet *applet = NULL;

	// Make sure we have a valid settings instance for the plugin
	path = create_applet_path(uuid);

	if (plugin_settings == NULL) {
		settings = g_settings_new_with_path(BUDGIE_APPLET_SCHEMA, g_strdup(path));
	} else {
		settings = g_object_ref(plugin_settings);
	}

	plugin_name = g_settings_get_string(settings, BUDGIE_APPLET_KEY_NAME);
	info = g_hash_table_lookup(self->plugins, plugin_name);

	// Check if the plugin has been loaded
	if (!PEAS_IS_PLUGIN_INFO(info)) {
		info = get_plugin_info(self, plugin_name);

		if (!PEAS_IS_PLUGIN_INFO(info)) {
			g_set_error(err,
					BUDGIE_PANEL_PLUGIN_MANAGER_ERROR,
						BUDGIE_PANEL_PLUGIN_MANAGER_ERROR_INVALID,
					"Tried to load invalid plugin '%s' with UUID %s", g_strdup(plugin_name), uuid);
			*name = g_strdup(plugin_name);
			return NULL;
		}

		// Try to load the plugin
		gboolean success = peas_engine_load_plugin(self->engine, info);

		if (!success) {
			g_set_error(err,
					BUDGIE_PANEL_PLUGIN_MANAGER_ERROR,
						BUDGIE_PANEL_PLUGIN_MANAGER_ERROR_LOAD_FAILED,
					"Unable to load plugin '%s' with UUID %s", g_strdup(plugin_name), uuid);
			*name = g_strdup(plugin_name);
			return NULL;
		}

		// Plugin will be loaded. We bail here because the loading doesn't actually happen
		// until the signal handler has been called.
		g_set_error(err,
				BUDGIE_PANEL_PLUGIN_MANAGER_ERROR,
					BUDGIE_PANEL_PLUGIN_MANAGER_ERROR_NOT_LOADED,
				"Plugin '%s' with UUID %s has not been loaded", g_strdup(plugin_name), uuid);
		*name = g_strdup(plugin_name);
		return NULL;
	}

	extension = peas_extension_set_get_extension(self->extensions, info);

	if (!extension) {
		g_set_error(err,
				BUDGIE_PANEL_PLUGIN_MANAGER_ERROR,
					BUDGIE_PANEL_PLUGIN_MANAGER_ERROR_NOT_FOUND,
				"Could not find extension for plugin '%s' with UUID %s", g_strdup(plugin_name), uuid);
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
BudgieAppletInfo *budgie_panel_plugin_manager_create_applet(BudgiePanelPluginManager *self, const gchar *name, const gchar *uuid, GError **err) {
	g_return_val_if_fail(BUDGIE_IS_PANEL_PLUGIN_MANAGER(self), NULL);
	g_return_val_if_fail(name != NULL, NULL);
	g_return_val_if_fail(uuid != NULL, NULL);
	g_return_val_if_fail(err == NULL || *err == NULL, NULL);

	g_autofree gchar *path = NULL;
	g_autoptr(GSettings) settings = NULL;
	BudgieAppletInfo *info = NULL;
	GError *temp_err = NULL;

	if G_UNLIKELY (!g_hash_table_contains(self->plugins, name)) {
		g_set_error(err,
		    BUDGIE_PANEL_PLUGIN_MANAGER_ERROR,
		      BUDGIE_PANEL_PLUGIN_MANAGER_ERROR_NOT_LOADED,
		    "Attempted to create a plugin that isn't loaded: %s", name);
		return NULL;
	}

	path = create_applet_path(uuid);
	settings = g_settings_new_with_path(BUDGIE_APPLET_SCHEMA, g_strdup(path));

	g_settings_set_string(settings, BUDGIE_APPLET_KEY_NAME, g_strdup(name));

	info = budgie_panel_plugin_manager_load_applet_instance(self, uuid, settings, NULL, &temp_err);

	if (!BUDGIE_IS_APPLET_INFO(info)) {
		g_propagate_error(err, temp_err);
		return NULL;
	}

	return info;
}
