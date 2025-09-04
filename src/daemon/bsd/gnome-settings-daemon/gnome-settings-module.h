/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 8 -*-
 *
 * Copyright (C) 2005 - Paolo Maggi
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

#ifndef GNOME_SETTINGS_MODULE_H
#define GNOME_SETTINGS_MODULE_H

#include <glib-object.h>

G_BEGIN_DECLS

#define GNOME_TYPE_SETTINGS_MODULE               (gnome_settings_module_get_type ())
#define GNOME_SETTINGS_MODULE(obj)               (G_TYPE_CHECK_INSTANCE_CAST ((obj), GNOME_TYPE_SETTINGS_MODULE, GnomeSettingsModule))
#define GNOME_SETTINGS_MODULE_CLASS(klass)       (G_TYPE_CHECK_CLASS_CAST ((klass), GNOME_TYPE_SETTINGS_MODULE, GnomeSettingsModuleClass))
#define GNOME_IS_SETTINGS_MODULE(obj)            (G_TYPE_CHECK_INSTANCE_TYPE ((obj), GNOME_TYPE_SETTINGS_MODULE))
#define GNOME_IS_SETTINGS_MODULE_CLASS(klass)    (G_TYPE_CHECK_CLASS_TYPE ((obj), GNOME_TYPE_SETTINGS_MODULE))
#define GNOME_SETTINGS_MODULE_GET_CLASS(obj)     (G_TYPE_INSTANCE_GET_CLASS((obj), GNOME_TYPE_SETTINGS_MODULE, GnomeSettingsModuleClass))

typedef struct _GnomeSettingsModule GnomeSettingsModule;

GType                    gnome_settings_module_get_type          (void) G_GNUC_CONST;

GnomeSettingsModule     *gnome_settings_module_new               (const gchar *path);

const char              *gnome_settings_module_get_path          (GnomeSettingsModule *module);

GObject                 *gnome_settings_module_new_object        (GnomeSettingsModule *module);

G_END_DECLS

#endif
