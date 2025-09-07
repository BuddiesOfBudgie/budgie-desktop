/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 8 -*-
 *
 * Copyright (C) 2008 William Jon McCann <jmccann@redhat.com>
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


#ifndef __GSM_MANAGER_LOGOUT_MODE_H
#define __GSM_MANAGER_LOGOUT_MODE_H

G_BEGIN_DECLS

typedef enum {
        GSM_MANAGER_LOGOUT_MODE_NORMAL = 0,
        GSM_MANAGER_LOGOUT_MODE_NO_CONFIRMATION,
        GSM_MANAGER_LOGOUT_MODE_FORCE
} GsmManagerLogoutMode;

G_END_DECLS

#endif /* __GSM_MANAGER_LOGOUT_MODE_H */
