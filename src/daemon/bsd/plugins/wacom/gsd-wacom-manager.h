/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 8 -*-
 *
 * Copyright (C) 2007 William Jon McCann <mccann@jhu.edu>
 * Copyright (C) 2010 Red Hat, Inc.
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

#ifndef __GSD_WACOM_MANAGER_H
#define __GSD_WACOM_MANAGER_H

#include <gio/gio.h>

G_BEGIN_DECLS

#define GSD_TYPE_WACOM_MANAGER         (gsd_wacom_manager_get_type ())

G_DECLARE_FINAL_TYPE (GsdWacomManager, gsd_wacom_manager, GSD, WACOM_MANAGER, GApplication)

G_END_DECLS

#endif /* __GSD_WACOM_MANAGER_H */
