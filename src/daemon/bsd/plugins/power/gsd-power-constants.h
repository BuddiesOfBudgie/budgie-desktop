/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 8 -*-
 *
 * Copyright (C) 2013 Red Hat Inc.
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

/* The blank delay when the screensaver is active */
#define SCREENSAVER_TIMEOUT_BLANK                       30 /* seconds */

/* The dim delay when dimming on idle is requested but idle-delay
 * is set to "Never" */
#define IDLE_DIM_BLANK_DISABLED_MIN                     60 /* seconds */

/* Which fraction of the idle-delay is the idle-dim delay */
#define IDLE_DELAY_TO_IDLE_DIM_MULTIPLIER                1.0/2.0

/* The dim delay under which we do not bother dimming */
#define MINIMUM_IDLE_DIM_DELAY                          10 /* seconds */

/* The amount of time we'll undim if the machine is idle when plugged in */
#define POWER_UP_TIME_ON_AC                             15 /* seconds */

/* Default brightness values for the mock backlight used in the test suite */
#define GSD_MOCK_DEFAULT_BRIGHTNESS                     50
#define GSD_MOCK_MAX_BRIGHTNESS                        100

/* When unplugging the external monitor, give a certain amount
 * of time before suspending the laptop */
#define LID_CLOSE_SAFETY_TIMEOUT                        8 /* seconds */
