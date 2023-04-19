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

#include <gtk/gtk.h>

#include "trash_info.h"

G_BEGIN_DECLS

#define TRASH_TYPE_ITEM_ROW (trash_item_row_get_type())

G_DECLARE_FINAL_TYPE(TrashItemRow, trash_item_row, TRASH, ITEM_ROW, GtkListBoxRow)

TrashItemRow *trash_item_row_new(TrashInfo *trash_info);

TrashInfo *trash_item_row_get_info(TrashItemRow *self);

void trash_item_row_delete(TrashItemRow *self);

void trash_item_row_restore(TrashItemRow *self);

gint trash_item_row_collate_by_date(TrashItemRow *self, TrashItemRow *other);

gint trash_item_row_collate_by_name(TrashItemRow *self, TrashItemRow *other);

gint trash_item_row_collate_by_type(TrashItemRow *self, TrashItemRow *other);

G_END_DECLS
