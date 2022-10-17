/*
 * This file is part of budgie-desktop.
 *
 * Copyright © 2015-2022 Budgie Desktop Developers
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 */

#pragma once

#include <budgie-raven-enums.h>
#include <raven-widget.h>

G_BEGIN_DECLS

typedef struct _BudgieRavenPlugin BudgieRavenPlugin;
typedef struct _BudgieRavenPluginIface BudgieRavenPluginIface;

#define BUDGIE_TYPE_RAVEN_PLUGIN (budgie_raven_plugin_get_type())
#define BUDGIE_RAVEN_PLUGIN(o) (G_TYPE_CHECK_INSTANCE_CAST((o), BUDGIE_TYPE_RAVEN_PLUGIN, BudgieRavenPlugin))
#define BUDGIE_IS_RAVEN_PLUGIN(o) (G_TYPE_CHECK_INSTANCE_TYPE((o), BUDGIE_TYPE_RAVEN_PLUGIN))
#define BUDGIE_RAVEN_PLUGIN_IFACE(o) (G_TYPE_CHECK_INTERFACE_CAST((o), BUDGIE_TYPE_RAVEN_PLUGIN, BudgieRavenPluginIface))
#define BUDGIE_IS_RAVEN_PLUGIN_IFACE(o) (G_TYPE_CHECK_INTERFACE_TYPE((o), BUDGIE_TYPE_RAVEN_PLUGIN))
#define BUDGIE_RAVEN_PLUGIN_GET_IFACE(o) (G_TYPE_INSTANCE_GET_INTERFACE((o), BUDGIE_TYPE_RAVEN_PLUGIN, BudgieRavenPluginIface))

/**
 * BudgiePluginIface
 */
struct _BudgieRavenPluginIface {
	GTypeInterface parent_iface;

    BudgieRavenWidget* (*new_widget_instance)(BudgieRavenPlugin* self, const char* uuid, GSettings* settings);
};

GType budgie_raven_plugin_get_type(void);

BudgieRavenWidget* budgie_raven_plugin_new_widget_instance(BudgieRavenPlugin* self, const char* uuid, GSettings* settings);

G_END_DECLS
