/*
 * Copyright 2013 Canonical Ltd.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Author: Lars Uebernickel <lars.uebernickel@canonical.com>
 */

#ifndef __BUS_WATCH_NAMESPACE_H__
#define __BUS_WATCH_NAMESPACE_H__

#include <gio/gio.h>

guint       bus_watch_namespace         (GBusType                  bus_type,
                                         const gchar              *name_space,
                                         GBusNameAppearedCallback  appeared_handler,
                                         GBusNameVanishedCallback  vanished_handler,
                                         gpointer                  user_data,
                                         GDestroyNotify            user_data_destroy);

void        bus_unwatch_namespace       (guint id);

#endif
