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

#include "plugin.h"

typedef BudgieRavenPluginIface BudgieRavenPluginInterface;

G_DEFINE_INTERFACE(BudgieRavenPlugin, budgie_raven_plugin, G_TYPE_OBJECT)

static void budgie_raven_plugin_default_init(__attribute__((unused)) BudgieRavenPluginIface* iface) {
}
