/* -*- mode: c; style: linux -*-
 * 
 * Copyright (C) 2017 Red Hat, Inc.
 *
 * Written by: Benjamin Berg <bberg@redhat.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, see <http://www.gnu.org/licenses/>.
 */

#ifndef _GSD_BACKLIGHT_H
#define _GSD_BACKLIGHT_H

#include <glib.h>
#include <gio/gio.h>

G_BEGIN_DECLS

#define GSD_TYPE_BACKLIGHT gsd_backlight_get_type ()
G_DECLARE_FINAL_TYPE (GsdBacklight, gsd_backlight, GSD, BACKLIGHT, GObject);

gint gsd_backlight_get_brightness        (GsdBacklight         *backlight,
                                          gint                 *target);

void gsd_backlight_set_brightness_async  (GsdBacklight         *backlight,
                                          gint                  percentage,
                                          GCancellable         *cancellable,
                                          GAsyncReadyCallback   callback,
                                          gpointer              user_data);
void gsd_backlight_step_up_async         (GsdBacklight         *backlight,
                                          GCancellable         *cancellable,
                                          GAsyncReadyCallback   callback,
                                          gpointer              user_data);
void gsd_backlight_step_down_async       (GsdBacklight         *backlight,
                                          GCancellable         *cancellable,
                                          GAsyncReadyCallback   callback,
                                          gpointer              user_data);
void gsd_backlight_cycle_up_async        (GsdBacklight         *backlight,
                                          GCancellable         *cancellable,
                                          GAsyncReadyCallback   callback,
                                          gpointer              user_data);

gint gsd_backlight_set_brightness_finish (GsdBacklight         *backlight,
                                          GAsyncResult         *res,
                                          GError              **error);

gint gsd_backlight_step_up_finish        (GsdBacklight         *backlight,
                                          GAsyncResult         *res,
                                          GError              **error);

gint gsd_backlight_step_down_finish      (GsdBacklight         *backlight,
                                          GAsyncResult         *res,
                                          GError              **error);

gint gsd_backlight_cycle_up_finish       (GsdBacklight         *backlight,
                                          GAsyncResult         *res,
                                          GError              **error);

const char*  gsd_backlight_get_connector (GsdBacklight         *backlight);

GsdBacklight* gsd_backlight_new          (GError              **error);


G_END_DECLS

#endif /* _GSD_BACKLIGHT_H */
