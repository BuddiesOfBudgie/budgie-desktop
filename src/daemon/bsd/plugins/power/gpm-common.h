/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 8 -*-
 *
 * Copyright (C) 2005-2011 Richard Hughes <richard@hughsie.com>
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

#ifndef __GPMCOMMON_H
#define __GPMCOMMON_H

#include <glib.h>
#include <libupower-glib/upower.h>

G_BEGIN_DECLS

/* UPower helpers */
gchar           *gpm_get_timestring                     (guint           time);

/* Power helpers */
gboolean         gsd_power_is_hardware_a_vm             (void);
guint            gsd_power_enable_screensaver_watchdog  (void);
void             reset_idletime                         (void);

/* Backlight helpers */

/* on ACPI machines we have 4-16 levels, on others it's ~150 */
#define BRIGHTNESS_STEP_AMOUNT(max) ((max) < 20 ? 1 : (max) / 20)

#define ABS_TO_PERCENTAGE(min, max, value) gsd_power_backlight_abs_to_percentage(min, max, value)
#define PERCENTAGE_TO_ABS(min, max, value) gsd_power_backlight_percentage_to_abs(min, max, value)

int              gsd_power_backlight_abs_to_percentage  (int min, int max, int value);
int              gsd_power_backlight_percentage_to_abs  (int min, int max, int value);

/* RandR helpers */
void             watch_external_monitor                 (void);
gboolean         external_monitor_is_connected          (void);

/* Sound helpers */
void             play_loop_start                        (guint *id);
void             play_loop_stop                         (guint *id);

G_END_DECLS

#endif  /* __GPMCOMMON_H */
