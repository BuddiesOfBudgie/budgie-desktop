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

#include <gio/gio.h>

G_BEGIN_DECLS

#define TRASH_TYPE_INFO (trash_info_get_type())

G_DECLARE_FINAL_TYPE(TrashInfo, trash_info, TRASH, INFO, GObject)

TrashInfo *trash_info_new(GFileInfo *info, const char *uri);

/* Property getters */

const gchar *trash_info_get_name(TrashInfo *self);

const gchar *trash_info_get_display_name(TrashInfo *self);

const gchar *trash_info_get_uri(TrashInfo *self);

const gchar *trash_info_get_restore_path(TrashInfo *self);

GIcon *trash_info_get_icon(TrashInfo *self);

goffset trash_info_get_size(TrashInfo *self);

gboolean trash_info_is_directory(TrashInfo *self);

GDateTime *trash_info_get_deletion_time(TrashInfo *self);

G_END_DECLS
