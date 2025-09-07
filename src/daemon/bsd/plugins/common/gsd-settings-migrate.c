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

#include "config.h"

#include <gio/gio.h>

#include "gsd-settings-migrate.h"

void
gsd_settings_migrate_check (const gchar             *origin_schema,
                            const gchar             *origin_path,
                            const gchar             *dest_schema,
                            const gchar             *dest_path,
                            GsdSettingsMigrateEntry  entries[],
                            guint                    n_entries)
{
        GSettings *origin_settings, *dest_settings;
        guint i;

        origin_settings = g_settings_new_with_path (origin_schema, origin_path);
        dest_settings = g_settings_new_with_path (dest_schema, dest_path);

        for (i = 0; i < n_entries; i++) {
                g_autoptr(GVariant) variant = NULL;

                variant = g_settings_get_user_value (origin_settings, entries[i].origin_key);

                if (!variant)
                        continue;

                g_settings_reset (origin_settings, entries[i].origin_key);

                if (entries[i].dest_key) {
                        if (entries[i].func) {
                                g_autoptr(GVariant) old_default = NULL;
                                g_autoptr(GVariant) new_default = NULL;
                                GVariant *modified;

                                old_default = g_settings_get_default_value (origin_settings, entries[i].origin_key);
                                new_default = g_settings_get_default_value (dest_settings, entries[i].dest_key);

                                modified = entries[i].func (variant, old_default, new_default);
                                g_clear_pointer (&variant, g_variant_unref);
                                if (modified)
                                        variant = g_variant_ref_sink (modified);
                        }

                        if (variant)
                                g_settings_set_value (dest_settings, entries[i].dest_key, variant);
                }
        }

        g_object_unref (origin_settings);
        g_object_unref (dest_settings);
}
