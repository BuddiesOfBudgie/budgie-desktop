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

#ifndef __SHORTCUTS_LIST_H__
#define __SHORTCUTS_LIST_H__

#include "shell-action-modes.h"
#include "media-keys.h"

#define SETTINGS_BINDING_DIR "org.buddiesofbudgie.settings-daemon.plugins.media-keys"

#define GSD_ACTION_MODE_LAUNCHER (SHELL_ACTION_MODE_NORMAL | \
                                  SHELL_ACTION_MODE_OVERVIEW)
#define SCREENSAVER_MODE SHELL_ACTION_MODE_ALL & ~SHELL_ACTION_MODE_UNLOCK_SCREEN
#define NO_LOCK_MODE SCREENSAVER_MODE & ~SHELL_ACTION_MODE_LOCK_SCREEN
#define POWER_KEYS_MODE_NO_DIALOG (SHELL_ACTION_MODE_LOCK_SCREEN | \
				   SHELL_ACTION_MODE_UNLOCK_SCREEN)
#define POWER_KEYS_MODE (SHELL_ACTION_MODE_NORMAL | \
			 SHELL_ACTION_MODE_OVERVIEW | \
			 SHELL_ACTION_MODE_LOGIN_SCREEN |\
                         POWER_KEYS_MODE_NO_DIALOG)
#define GSD_ACTION_MODE_SCRIPT (SHELL_ACTION_MODE_ALL & \
				~SHELL_ACTION_MODE_LOGIN_SCREEN)

static struct {
        MediaKeyType key_type;
        const char *settings_key;
        gboolean static_setting;
        ShellActionMode modes;
        MetaKeyBindingFlags grab_flags;
} media_keys[] = {
        { TOUCHPAD_KEY, "touchpad-toggle", TRUE, SHELL_ACTION_MODE_ALL, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { TOUCHPAD_ON_KEY, "touchpad-on", TRUE, SHELL_ACTION_MODE_ALL, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { TOUCHPAD_OFF_KEY, "touchpad-off", TRUE, SHELL_ACTION_MODE_ALL, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { MUTE_KEY, "volume-mute", TRUE, SHELL_ACTION_MODE_ALL, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { VOLUME_DOWN_KEY, "volume-down", TRUE, SHELL_ACTION_MODE_ALL },
        { VOLUME_UP_KEY, "volume-up", TRUE, SHELL_ACTION_MODE_ALL },
        { MIC_MUTE_KEY, "mic-mute", TRUE, SHELL_ACTION_MODE_ALL, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { MUTE_QUIET_KEY, "volume-mute-quiet", TRUE, SHELL_ACTION_MODE_ALL, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { VOLUME_DOWN_QUIET_KEY, "volume-down-quiet", TRUE, SHELL_ACTION_MODE_ALL },
        { VOLUME_UP_QUIET_KEY, "volume-up-quiet", TRUE, SHELL_ACTION_MODE_ALL },
        { VOLUME_DOWN_PRECISE_KEY, "volume-down-precise", TRUE, SHELL_ACTION_MODE_ALL },
        { VOLUME_UP_PRECISE_KEY, "volume-up-precise", TRUE, SHELL_ACTION_MODE_ALL },
        { LOGOUT_KEY, "logout", FALSE, GSD_ACTION_MODE_LAUNCHER, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { REBOOT_KEY, "reboot", FALSE, GSD_ACTION_MODE_LAUNCHER, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { SHUTDOWN_KEY, "shutdown", FALSE, GSD_ACTION_MODE_LAUNCHER, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { EJECT_KEY, "eject", TRUE, SHELL_ACTION_MODE_ALL, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { HOME_KEY, "home", TRUE, GSD_ACTION_MODE_LAUNCHER, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { MEDIA_KEY, "media", TRUE, GSD_ACTION_MODE_LAUNCHER, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { CALCULATOR_KEY, "calculator", TRUE, GSD_ACTION_MODE_LAUNCHER, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { SEARCH_KEY, "search", TRUE, GSD_ACTION_MODE_LAUNCHER, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { EMAIL_KEY, "email", TRUE, GSD_ACTION_MODE_LAUNCHER, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { CONTROL_CENTER_KEY, "control-center", TRUE, GSD_ACTION_MODE_LAUNCHER, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { SCREENSAVER_KEY, "screensaver", TRUE, SCREENSAVER_MODE, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { HELP_KEY, "help", FALSE, GSD_ACTION_MODE_LAUNCHER, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { TERMINAL_KEY, "terminal", FALSE, GSD_ACTION_MODE_LAUNCHER, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { WWW_KEY, "www", TRUE, GSD_ACTION_MODE_LAUNCHER, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { PLAY_KEY, "play", TRUE, SHELL_ACTION_MODE_ALL, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { PAUSE_KEY, "pause", TRUE, SHELL_ACTION_MODE_ALL, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { STOP_KEY, "stop", TRUE, SHELL_ACTION_MODE_ALL, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { PREVIOUS_KEY, "previous", TRUE, SHELL_ACTION_MODE_ALL },
        { NEXT_KEY, "next", TRUE, SHELL_ACTION_MODE_ALL },
        { REWIND_KEY, "playback-rewind", TRUE, SHELL_ACTION_MODE_ALL },
        { FORWARD_KEY, "playback-forward", TRUE, SHELL_ACTION_MODE_ALL },
        { REPEAT_KEY, "playback-repeat", TRUE, SHELL_ACTION_MODE_ALL },
        { RANDOM_KEY, "playback-random", TRUE, SHELL_ACTION_MODE_ALL },
        { ROTATE_VIDEO_LOCK_KEY, "rotate-video-lock", TRUE, SHELL_ACTION_MODE_ALL },
        { MAGNIFIER_KEY, "magnifier", FALSE, SHELL_ACTION_MODE_ALL, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { SCREENREADER_KEY, "screenreader", FALSE, SHELL_ACTION_MODE_ALL, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { ON_SCREEN_KEYBOARD_KEY, "on-screen-keyboard", FALSE, SHELL_ACTION_MODE_ALL, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { INCREASE_TEXT_KEY, "increase-text-size", FALSE, SHELL_ACTION_MODE_ALL },
        { DECREASE_TEXT_KEY, "decrease-text-size", FALSE, SHELL_ACTION_MODE_ALL },
        { TOGGLE_CONTRAST_KEY, "toggle-contrast", FALSE, SHELL_ACTION_MODE_ALL, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { MAGNIFIER_ZOOM_IN_KEY, "magnifier-zoom-in", FALSE, SHELL_ACTION_MODE_ALL },
        { MAGNIFIER_ZOOM_OUT_KEY, "magnifier-zoom-out", FALSE, SHELL_ACTION_MODE_ALL },
        { POWER_KEY, "power", TRUE, POWER_KEYS_MODE, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        /* the kernel / Xorg names really are like this... */
        { SUSPEND_KEY, "suspend", TRUE, POWER_KEYS_MODE, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { HIBERNATE_KEY, "hibernate", TRUE, POWER_KEYS_MODE, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { SCREEN_BRIGHTNESS_UP_KEY, "screen-brightness-up", TRUE, SHELL_ACTION_MODE_ALL },
        { SCREEN_BRIGHTNESS_DOWN_KEY, "screen-brightness-down", TRUE, SHELL_ACTION_MODE_ALL },
        { SCREEN_BRIGHTNESS_CYCLE_KEY, "screen-brightness-cycle", TRUE, SHELL_ACTION_MODE_ALL },
        { KEYBOARD_BRIGHTNESS_UP_KEY, "keyboard-brightness-up", TRUE, SHELL_ACTION_MODE_ALL },
        { KEYBOARD_BRIGHTNESS_DOWN_KEY, "keyboard-brightness-down", TRUE, SHELL_ACTION_MODE_ALL },
        { KEYBOARD_BRIGHTNESS_TOGGLE_KEY, "keyboard-brightness-toggle", TRUE, SHELL_ACTION_MODE_ALL, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { BATTERY_KEY, "battery-status", TRUE, GSD_ACTION_MODE_LAUNCHER, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { RFKILL_KEY, "rfkill", TRUE, GSD_ACTION_MODE_LAUNCHER, META_KEY_BINDING_IGNORE_AUTOREPEAT },
        { BLUETOOTH_RFKILL_KEY, "rfkill-bluetooth", TRUE, GSD_ACTION_MODE_LAUNCHER, META_KEY_BINDING_IGNORE_AUTOREPEAT}
};

#undef SCREENSAVER_MODE

#endif /* __SHORTCUTS_LIST_H__ */
