/*
 * This file is part of budgie-desktop
 *
 * Copyright © Budgie Desktop Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#pragma once

#include "trash_applet.h"
#include "../../../plugin/panel/plugin.h"
#include <gtk/gtk.h>

G_BEGIN_DECLS

#define TRASH_TYPE_PLUGIN (trash_plugin_get_type())

G_DECLARE_FINAL_TYPE(TrashPlugin, trash_plugin, TRASH, PLUGIN, GObject)

struct _TrashPlugin {
	GObject parent;
};

GType trash_plugin_get_type(void);

G_END_DECLS
