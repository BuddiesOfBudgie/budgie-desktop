/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 8 -*-
 *
 * Copyright (C) 2024 SUSE Software Solutions Germany GmbH
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, see <http://www.gnu.org/licenses/>.
 *
 * Author: Joan Torres <joan.torres@suse.com>
 *
 */

#ifndef __GSD_MAIN_HELPER_H
#define __GSD_MAIN_HELPER_H

#include <glib-object.h>

int                   gsd_main_helper          (GType        manager_type,
                                                int          argc,
                                                char       **argv);

#endif /* __GSD_MAIN_HELPER_H */
