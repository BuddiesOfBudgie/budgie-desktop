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

#ifndef _PLUGIN_MANAGER_H
#define _PLUGIN_MANAGER_H

#include <glib-object.h>
#include <libpeas-2/libpeas.h>

#include "applet-info.h"

G_BEGIN_DECLS

/**
 * BUDGIE_APPLET_PREFIX:
 * Prefix for all relocatable applet settings
 */
#define BUDGIE_APPLET_PREFIX "/com/solus-project/budgie-panel/applets"

/**
 * BUDGIE_APPLET_SCHEMA:
 * Relocatable schema ID for applets
 */
#define BUDGIE_APPLET_SCHEMA "com.solus-project.budgie-panel.applet"

#define BUDGIE_PANEL_PLUGIN_MANAGER_ERROR budgie_panel_plugin_manager_error_quark()
GQuark budgie_panel_plugin_manager_error_quark(void);

typedef enum {
	BUDGIE_PANEL_PLUGIN_MANAGER_ERROR_INVALID, /* Invalid plugin info */
	BUDGIE_PANEL_PLUGIN_MANAGER_ERROR_LOAD_FAILED, /* Unable to load plugin */
	BUDGIE_PANEL_PLUGIN_MANAGER_ERROR_NOT_FOUND, /* Extension for plugin not found */
	BUDGIE_PANEL_PLUGIN_MANAGER_ERROR_NOT_LOADED, /* Plugin is not loaded */
} BudgiePanelPluginManagerError;

#define BUDGIE_TYPE_PANEL_PLUGIN_MANAGER (budgie_panel_plugin_manager_get_type())

G_DECLARE_FINAL_TYPE(BudgiePanelPluginManager, budgie_panel_plugin_manager, BUDGIE, PANEL_PLUGIN_MANAGER, GObject)

BudgiePanelPluginManager *budgie_panel_plugin_manager_new();

gboolean budgie_panel_plugin_manager_is_plugin_loaded(BudgiePanelPluginManager *self, const gchar *name);

gboolean budgie_panel_plugin_manager_is_plugin_valid(BudgiePanelPluginManager *self, const gchar *name);

GList *budgie_panel_plugin_manager_get_all_plugins(BudgiePanelPluginManager *self);

void budgie_panel_plugin_manager_rescan_plugins(BudgiePanelPluginManager *self);

void budgie_panel_plugin_manager_modprobe(BudgiePanelPluginManager *self, const gchar *name);

BudgieAppletInfo *budgie_panel_plugin_manager_load_applet_instance(BudgiePanelPluginManager *self, const gchar *uuid, GSettings *settings, gchar **name, GError **err);

BudgieAppletInfo *budgie_panel_plugin_manager_create_applet(BudgiePanelPluginManager *self, const gchar *name, const gchar *uuid, GError **err);

G_END_DECLS

#endif
