/* -*- Mode: C; tab-width: 8; indent-tabs-mode: t; c-basic-offset: 8 -*-
 *
 * Copyright (C) 2006-2011 Richard Hughes <richard@hughsie.com>
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

#include "config.h"

#include <string.h>
#include <unistd.h>
#include <stdio.h>
#include <glib.h>
#include <gio/gio.h>

#if HAVE_WAYLAND
#include <wayland-client.h>
#endif

#include "gnome-settings-bus.h"

#define GNOME_SESSION_DBUS_NAME      "org.gnome.SessionManager"
#define GNOME_SESSION_DBUS_OBJECT    "/org/gnome/SessionManager"

#define GNOME_SCREENSAVER_DBUS_NAME      "org.gnome.ScreenSaver"
#define GNOME_SCREENSAVER_DBUS_OBJECT    "/org/gnome/ScreenSaver"

#define GNOME_SHELL_DBUS_NAME      "org.gnome.Shell"
#define GNOME_SHELL_DBUS_OBJECT    "/org/gnome/Shell"

#define MUTTER_DISPLAY_CONFIG_DBUS_NAME      "org.gnome.Mutter.DisplayConfig"
#define MUTTER_DISPLAY_CONFIG_DBUS_OBJECT    "/org/gnome/Mutter/DisplayConfig"

GsdSessionManager *
gnome_settings_bus_get_session_proxy (void)
{
        static GsdSessionManager *session_proxy;
        GError *error =  NULL;

        if (session_proxy != NULL) {
                g_object_ref (session_proxy);
        } else {
                session_proxy = gsd_session_manager_proxy_new_for_bus_sync (G_BUS_TYPE_SESSION,
                                                                            G_DBUS_PROXY_FLAGS_NONE,
                                                                            GNOME_SESSION_DBUS_NAME,
                                                                            GNOME_SESSION_DBUS_OBJECT,
                                                                            NULL,
                                                                            &error);
                if (error) {
                        g_warning ("Failed to connect to the session manager: %s", error->message);
                        g_error_free (error);
                } else {
                        g_object_add_weak_pointer (G_OBJECT (session_proxy), (gpointer*)&session_proxy);
                }
        }

        return session_proxy;
}

GsdScreenSaver *
gnome_settings_bus_get_screen_saver_proxy (void)
{
        static GsdScreenSaver *screen_saver_proxy;
        GError *error =  NULL;

        if (screen_saver_proxy != NULL) {
                g_object_ref (screen_saver_proxy);
        } else {
                screen_saver_proxy = gsd_screen_saver_proxy_new_for_bus_sync (G_BUS_TYPE_SESSION,
                                                                              G_DBUS_PROXY_FLAGS_DO_NOT_LOAD_PROPERTIES,
                                                                              GNOME_SCREENSAVER_DBUS_NAME,
                                                                              GNOME_SCREENSAVER_DBUS_OBJECT,
                                                                              NULL,
                                                                              &error);
                if (error) {
                        g_warning ("Failed to connect to the screen saver: %s", error->message);
                        g_error_free (error);
                } else {
                        g_object_add_weak_pointer (G_OBJECT (screen_saver_proxy), (gpointer*)&screen_saver_proxy);
                }
        }

        return screen_saver_proxy;
}

GsdShell *
gnome_settings_bus_get_shell_proxy (void)
{
        static GsdShell *shell_proxy = NULL;
        GError *error =  NULL;

        if (shell_proxy != NULL) {
                g_object_ref (shell_proxy);
        } else {
                shell_proxy = gsd_shell_proxy_new_for_bus_sync (G_BUS_TYPE_SESSION,
								G_DBUS_PROXY_FLAGS_DO_NOT_LOAD_PROPERTIES |
								G_DBUS_PROXY_FLAGS_DO_NOT_AUTO_START,
								GNOME_SHELL_DBUS_NAME,
								GNOME_SHELL_DBUS_OBJECT,
								NULL,
								&error);
                if (error) {
                        g_warning ("Failed to connect to the shell: %s", error->message);
                        g_error_free (error);
                } else {
                        g_object_add_weak_pointer (G_OBJECT (shell_proxy), (gpointer*)&shell_proxy);
                }
        }

        return shell_proxy;
}

GsdDisplayConfig *
gnome_settings_bus_get_display_config_proxy (void)
{
        static GsdDisplayConfig *display_config_proxy = NULL;
        g_autoptr(GError) error =  NULL;

        if (display_config_proxy != NULL) {
                g_object_ref (display_config_proxy);
        } else {
                display_config_proxy =
                        gsd_display_config_proxy_new_for_bus_sync (G_BUS_TYPE_SESSION,
                                                                   G_DBUS_PROXY_FLAGS_DO_NOT_AUTO_START,
                                                                   MUTTER_DISPLAY_CONFIG_DBUS_NAME,
                                                                   MUTTER_DISPLAY_CONFIG_DBUS_OBJECT,
                                                                   NULL,
                                                                   &error);
                if (error) {
                        g_warning ("Failed to connect to display config: %s", error->message);
                } else {
                        g_object_add_weak_pointer (G_OBJECT (display_config_proxy),
                                                   (gpointer*)&display_config_proxy);
                }
        }

        return display_config_proxy;
}

char *
gnome_settings_get_chassis_type (void)
{
        char *ret = NULL;
        GError *error = NULL;
        GVariant *inner;
        GVariant *variant = NULL;
        GDBusConnection *connection;

        connection = g_bus_get_sync (G_BUS_TYPE_SYSTEM,
                                     NULL,
                                     &error);
        if (connection == NULL) {
                g_warning ("system bus not available: %s", error->message);
                g_error_free (error);
                goto out;
        }

        variant = g_dbus_connection_call_sync (connection,
                                               "org.freedesktop.hostname1",
                                               "/org/freedesktop/hostname1",
                                               "org.freedesktop.DBus.Properties",
                                               "Get",
                                               g_variant_new ("(ss)",
                                                              "org.freedesktop.hostname1",
                                                              "Chassis"),
                                               NULL,
                                               G_DBUS_CALL_FLAGS_NONE,
                                               -1,
                                               NULL,
                                               &error);
        if (variant == NULL) {
                g_debug ("Failed to get property '%s': %s", "Chassis", error->message);
                g_error_free (error);
                goto out;
        }

        g_variant_get (variant, "(v)", &inner);
        ret = g_variant_dup_string (inner, NULL);
        g_variant_unref (inner);
out:
        g_clear_object (&connection);
        g_clear_pointer (&variant, g_variant_unref);
        return ret;
}

static gpointer
is_wayland_session (gpointer user_data)
{
#if HAVE_WAYLAND
        struct wl_display *display;

        display = wl_display_connect (NULL);
        if (!display)
                return GUINT_TO_POINTER(FALSE);
        wl_display_disconnect (display);
        return GUINT_TO_POINTER(TRUE);
#else
        return GUINT_TO_POINTER(FALSE);
#endif
}

gboolean
gnome_settings_is_wayland (void)
{
        static GOnce wayland_once = G_ONCE_INIT;

        g_once (&wayland_once, is_wayland_session, NULL);

        return GPOINTER_TO_UINT(wayland_once.retval);
}
