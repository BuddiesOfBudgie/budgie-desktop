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

#include <glib-object.h>

G_BEGIN_DECLS

GType trash_sort_mode_get_type(void);
#define TRASH_TYPE_SORT_MODE (trash_sort_mode_get_type())

G_END_DECLS
