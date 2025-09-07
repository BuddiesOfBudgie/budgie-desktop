/* -*- Mode: C; tab-width: 8; indent-tabs-mode: t; c-basic-offset: 8 -*-
 *
 * Copyright (C) 2010-2011 Richard Hughes <richard@hughsie.com>
 *
 * Licensed under the GNU General Public License Version 2
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
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#ifndef __GNOME_SETTINGS_BUS_H
#define __GNOME_SETTINGS_BUS_H

#include <glib-object.h>
#include "gsd-session-manager-glue.h"
#include "gsd-screen-saver-glue.h"
#include "gsd-shell-glue.h"
#include "gsd-display-config-glue.h"

G_BEGIN_DECLS

GsdSessionManager        *gnome_settings_bus_get_session_proxy       (void);
GsdScreenSaver           *gnome_settings_bus_get_screen_saver_proxy  (void);
GsdShell                 *gnome_settings_bus_get_shell_proxy         (void);
GsdDisplayConfig         *gnome_settings_bus_get_display_config_proxy (void);
gboolean                  gnome_settings_is_wayland                  (void);
char *                    gnome_settings_get_chassis_type            (void);

G_END_DECLS

#endif /* __GNOME_SETTINGS_BUS_H */
