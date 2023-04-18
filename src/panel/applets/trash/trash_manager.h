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

#include "trash_info.h"
#include <gio/gio.h>

G_BEGIN_DECLS

/**
 * All of the file attributes that we need to query for to build a
 * TrashInfo struct.
 */
#define TRASH_FILE_ATTRIBUTES G_FILE_ATTRIBUTE_STANDARD_NAME "," G_FILE_ATTRIBUTE_STANDARD_DISPLAY_NAME "," G_FILE_ATTRIBUTE_STANDARD_TARGET_URI "," G_FILE_ATTRIBUTE_STANDARD_ICON "," G_FILE_ATTRIBUTE_STANDARD_SIZE "," G_FILE_ATTRIBUTE_STANDARD_TYPE "," G_FILE_ATTRIBUTE_TRASH_DELETION_DATE "," G_FILE_ATTRIBUTE_TRASH_ORIG_PATH

#define TRASH_TYPE_MANAGER (trash_manager_get_type())

G_DECLARE_FINAL_TYPE(TrashManager, trash_manager, TRASH, MANAGER, GObject)

TrashManager *trash_manager_new(void);

void trash_manager_scan_items(TrashManager *self);

gint trash_manager_get_item_count(TrashManager *self);

G_END_DECLS
