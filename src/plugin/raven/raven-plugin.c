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

#include "raven-plugin.h"

typedef BudgieRavenPluginIface BudgieRavenPluginInterface;

G_DEFINE_INTERFACE(BudgieRavenPlugin, budgie_raven_plugin, G_TYPE_OBJECT)

static void budgie_raven_plugin_default_init(__attribute__((unused)) BudgieRavenPluginIface* iface) {
}

/**
 * budgie_raven_plugin_new_widget_instance:
 * @self: A #BudgieRavenPlugin
 * @uuid: UUID for this new instance
 * @settings: (nullable): Settings for this new instance
 *
 * Returns: (transfer full): A newly initialized Raven widget
 */
BudgieRavenWidget* budgie_raven_plugin_new_widget_instance(BudgieRavenPlugin* self, gchar* uuid, GSettings* settings) {
    if (!BUDGIE_IS_RAVEN_PLUGIN(self)) {
		return NULL;
	}

	return BUDGIE_RAVEN_PLUGIN_GET_IFACE(self)->new_widget_instance(self, uuid, settings);
}

/**
 * budgie_raven_plugin_supports_settings:
 * @self: A #BudgieRavenPlugin
 *
 * Returns: (transfer full): Whether this plugin supports per-instance settings
 */
gboolean budgie_raven_plugin_supports_settings(BudgieRavenPlugin* self) {
	if (!BUDGIE_IS_RAVEN_PLUGIN(self)) {
		return FALSE;
	}

	return BUDGIE_RAVEN_PLUGIN_GET_IFACE(self)->supports_settings(self);
}
