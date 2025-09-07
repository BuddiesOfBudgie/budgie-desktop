/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 8 -*-
 *
 * Copyright (C) 2015 Red Hat
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	 See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *
 * Author: Carlos Garnacho <carlosg@gnome.org>
 */

#ifndef __GSD_SETTINGS_MIGRATE_H__
#define __GSD_SETTINGS_MIGRATE_H__

typedef struct _GsdSettingsMigrateEntry GsdSettingsMigrateEntry;

typedef GVariant * (* GsdSettingsMigrateFunc) (GVariant *variant, GVariant *old_default, GVariant *new_default);

struct _GsdSettingsMigrateEntry
{
        const gchar *origin_key;
        const gchar *dest_key;
        GsdSettingsMigrateFunc func;
};

void gsd_settings_migrate_check (const gchar             *origin_schema,
                                 const gchar             *origin_path,
                                 const gchar             *dest_schema,
                                 const gchar             *dest_path,
                                 GsdSettingsMigrateEntry  entries[],
                                 guint                    n_entries);

#endif /* __GSD_SETTINGS_MIGRATE_H__ */
