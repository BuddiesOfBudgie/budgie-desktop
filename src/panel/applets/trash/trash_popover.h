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

#include "trash_button_bar.h"
#include "trash_info.h"
#include "trash_item_row.h"
#include "trash_manager.h"
#include "trash_settings.h"
#include <gtk/gtk.h>

G_BEGIN_DECLS

#define TRASH_TYPE_POPOVER (trash_popover_get_type())

G_DECLARE_FINAL_TYPE(TrashPopover, trash_popover, TRASH, POPOVER, GtkBox)

TrashPopover *trash_popover_new(GSettings *settings);

G_END_DECLS
