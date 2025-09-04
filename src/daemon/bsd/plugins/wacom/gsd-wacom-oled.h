/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 8 -*-
 *
 * Copyright (C) 2013 Przemo Firszt <przemo@firszt.eu>
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
 *
 */

#include "gsd-wacom-oled-constants.h"

#include <gdk-pixbuf/gdk-pixbuf.h>

#ifndef __GSD_WACOM_OLED_H
#define __GSD_WACOM_OLED_H

G_BEGIN_DECLS

gboolean set_oled (const gchar *device_path, gboolean left_handed, guint button, char *label, GError **error);
char *gsd_wacom_oled_gdkpixbuf_to_base64 (GdkPixbuf *pixbuf);

G_END_DECLS

#endif /* __GSD_WACOM_OLED_H */
