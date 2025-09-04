/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 8 -*-
 *
 * Copyright (C) 2008 Red Hat, Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, see <http://www.gnu.org/licenses/>.
 */

#ifndef __GNOME_SETTINGS_PLUGIN_INFO_H__
#define __GNOME_SETTINGS_PLUGIN_INFO_H__

#include <glib-object.h>
#include <gmodule.h>

G_BEGIN_DECLS
#define GNOME_TYPE_SETTINGS_PLUGIN_INFO              (gnome_settings_plugin_info_get_type())
#define GNOME_SETTINGS_PLUGIN_INFO(obj)              (G_TYPE_CHECK_INSTANCE_CAST((obj), GNOME_TYPE_SETTINGS_PLUGIN_INFO, GnomeSettingsPluginInfo))
#define GNOME_SETTINGS_PLUGIN_INFO_CLASS(klass)      (G_TYPE_CHECK_CLASS_CAST((klass),  GNOME_TYPE_SETTINGS_PLUGIN_INFO, GnomeSettingsPluginInfoClass))
#define GNOME_IS_SETTINGS_PLUGIN_INFO(obj)           (G_TYPE_CHECK_INSTANCE_TYPE((obj), GNOME_TYPE_SETTINGS_PLUGIN_INFO))
#define GNOME_IS_SETTINGS_PLUGIN_INFO_CLASS(klass)   (G_TYPE_CHECK_CLASS_TYPE ((klass), GNOME_TYPE_SETTINGS_PLUGIN_INFO))
#define GNOME_SETTINGS_PLUGIN_INFO_GET_CLASS(obj)    (G_TYPE_INSTANCE_GET_CLASS((obj),  GNOME_TYPE_SETTINGS_PLUGIN_INFO, GnomeSettingsPluginInfoClass))

typedef struct GnomeSettingsPluginInfoPrivate GnomeSettingsPluginInfoPrivate;

typedef struct
{
        GObject                         parent;
        GnomeSettingsPluginInfoPrivate *priv;
} GnomeSettingsPluginInfo;

typedef struct
{
        GObjectClass parent_class;

        void          (* activated)         (GnomeSettingsPluginInfo *info);
        void          (* deactivated)       (GnomeSettingsPluginInfo *info);
} GnomeSettingsPluginInfoClass;

GType            gnome_settings_plugin_info_get_type           (void) G_GNUC_CONST;

GnomeSettingsPluginInfo *gnome_settings_plugin_info_new_from_file (const char *filename);

gboolean         gnome_settings_plugin_info_activate        (GnomeSettingsPluginInfo *info);
gboolean         gnome_settings_plugin_info_deactivate      (GnomeSettingsPluginInfo *info);

gboolean         gnome_settings_plugin_info_is_active       (GnomeSettingsPluginInfo *info);
gboolean         gnome_settings_plugin_info_is_available    (GnomeSettingsPluginInfo *info);

const char      *gnome_settings_plugin_info_get_name        (GnomeSettingsPluginInfo *info);
const char      *gnome_settings_plugin_info_get_description (GnomeSettingsPluginInfo *info);
const char     **gnome_settings_plugin_info_get_authors     (GnomeSettingsPluginInfo *info);
const char      *gnome_settings_plugin_info_get_website     (GnomeSettingsPluginInfo *info);
const char      *gnome_settings_plugin_info_get_copyright   (GnomeSettingsPluginInfo *info);
const char      *gnome_settings_plugin_info_get_location    (GnomeSettingsPluginInfo *info);
int              gnome_settings_plugin_info_get_priority    (GnomeSettingsPluginInfo *info);

G_END_DECLS

#endif  /* __GNOME_SETTINGS_PLUGIN_INFO_H__ */
