/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 8 -*-
 *
 * Copyright (C) 2001 Bastien Nocera <hadess@hadess.net>
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

#ifndef __MEDIA_KEYS_H__
#define __MEDIA_KEYS_H__

typedef enum {
        TOUCHPAD_KEY,
        TOUCHPAD_ON_KEY,
        TOUCHPAD_OFF_KEY,
        MUTE_KEY,
        VOLUME_DOWN_KEY,
        VOLUME_UP_KEY,
        MIC_MUTE_KEY,
        MUTE_QUIET_KEY,
        VOLUME_DOWN_QUIET_KEY,
        VOLUME_UP_QUIET_KEY,
        VOLUME_DOWN_PRECISE_KEY,
        VOLUME_UP_PRECISE_KEY,
        LOGOUT_KEY,
        REBOOT_KEY,
        SHUTDOWN_KEY,
        EJECT_KEY,
        HOME_KEY,
        MEDIA_KEY,
        CALCULATOR_KEY,
        SEARCH_KEY,
        EMAIL_KEY,
        CONTROL_CENTER_KEY,
        SCREENSAVER_KEY,
        HELP_KEY,
        TERMINAL_KEY,
        WWW_KEY,
        PLAY_KEY,
        PAUSE_KEY,
        STOP_KEY,
        PREVIOUS_KEY,
        NEXT_KEY,
        REWIND_KEY,
        FORWARD_KEY,
        REPEAT_KEY,
        RANDOM_KEY,
        ROTATE_VIDEO_LOCK_KEY,
        MAGNIFIER_KEY,
        SCREENREADER_KEY,
        ON_SCREEN_KEYBOARD_KEY,
        INCREASE_TEXT_KEY,
        DECREASE_TEXT_KEY,
        TOGGLE_CONTRAST_KEY,
        MAGNIFIER_ZOOM_IN_KEY,
        MAGNIFIER_ZOOM_OUT_KEY,
        POWER_KEY,
        SUSPEND_KEY,
        HIBERNATE_KEY,
        SCREEN_BRIGHTNESS_UP_KEY,
        SCREEN_BRIGHTNESS_DOWN_KEY,
        SCREEN_BRIGHTNESS_CYCLE_KEY,
        KEYBOARD_BRIGHTNESS_UP_KEY,
        KEYBOARD_BRIGHTNESS_DOWN_KEY,
        KEYBOARD_BRIGHTNESS_TOGGLE_KEY,
        BATTERY_KEY,
        RFKILL_KEY,
        BLUETOOTH_RFKILL_KEY,
        CUSTOM_KEY
} MediaKeyType;

#endif  /* __MEDIA_KEYS_H__ */
