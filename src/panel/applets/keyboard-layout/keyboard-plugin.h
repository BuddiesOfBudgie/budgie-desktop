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

#include "plugin.h"

G_BEGIN_DECLS

#define KEYBOARD_TYPE_PLUGIN (keyboard_plugin_get_type())

G_DECLARE_FINAL_TYPE(KeyboardPlugin, keyboard_plugin, KEYBOARD, PLUGIN, GObject)

struct _KeyboardPlugin {
	GObject parent;
};

GType keyboard_plugin_get_type(void);

G_END_DECLS
