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

#include "config.h"
#include "gio/gio.h"

#include <sys/types.h>
#include <sys/wait.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>

#include <locale.h>

#include <gdk/gdk.h>

#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#if HAVE_WACOM
#include <libwacom/libwacom.h>
#endif

#include "gnome-settings-daemon/gsd-enums.h"
#include "gnome-settings-profile.h"
#include "gnome-settings-bus.h"
#include "gsd-wacom-manager.h"
#include "gsd-wacom-oled.h"
#include "gsd-settings-migrate.h"
#include "gsd-input-helper.h"


#define UNKNOWN_DEVICE_NOTIFICATION_TIMEOUT 15000

#define GSD_DBUS_NAME "org.gnome.SettingsDaemon"
#define GSD_DBUS_PATH "/org/gnome/SettingsDaemon"
#define GSD_DBUS_BASE_INTERFACE "org.gnome.SettingsDaemon"

#define GSD_WACOM_DBUS_PATH GSD_DBUS_PATH "/Wacom"
#define GSD_WACOM_DBUS_NAME GSD_DBUS_NAME ".Wacom"

#define LEFT_HANDED_KEY		"left-handed"

static const gchar introspection_xml[] =
"<node name='/org/gnome/SettingsDaemon/Wacom'>"
"  <interface name='org.gnome.SettingsDaemon.Wacom'>"
"    <method name='SetOLEDLabels'>"
"      <arg name='device_path' direction='in' type='s'/>"
"      <arg name='labels' direction='in' type='as'/>"
"    </method>"
"  </interface>"
"</node>";

struct _GsdWacomManager
{
        GApplication parent;

        guint start_idle_id;
        GdkSeat *seat;
        guint device_added_id;

        GsdShell *shell_proxy;

        gchar *machine_id;

#if HAVE_WACOM
        WacomDeviceDatabase *wacom_db;
#endif

        /* DBus */
        GDBusNodeInfo   *introspection_data;
        GDBusConnection *dbus_connection;
        GCancellable    *dbus_cancellable;
        guint            dbus_register_object_id;
        guint            name_id;
};

static void     gsd_wacom_manager_class_init  (GsdWacomManagerClass *klass);
static void     gsd_wacom_manager_init        (GsdWacomManager      *wacom_manager);
static void     gsd_wacom_manager_finalize    (GObject              *object);
static void     gsd_wacom_manager_startup     (GApplication         *app);
static void     gsd_wacom_manager_shutdown    (GApplication         *app);

static gboolean is_opaque_tablet (GsdWacomManager *manager,
                                  GdkDevice       *device);

G_DEFINE_TYPE (GsdWacomManager, gsd_wacom_manager, G_TYPE_APPLICATION)

static GVariant *
map_tablet_mapping (GVariant *value, GVariant *old_default, GVariant *new_default)
{
        const gchar *mapping;

        mapping = g_variant_get_boolean (value) ? "absolute" : "relative";
        return g_variant_new_string (mapping);
}

static GVariant *
map_tablet_left_handed (GVariant *value, GVariant *old_default, GVariant *new_default)
{
        const gchar *rotation = g_variant_get_string (value, NULL);
        return g_variant_new_boolean (g_strcmp0 (rotation, "half") == 0 ||
                                      g_strcmp0 (rotation, "ccw") == 0);
}

static void
migrate_tablet_settings (GsdWacomManager *manager,
                         GdkDevice       *device)
{
        GsdSettingsMigrateEntry tablet_settings[] = {
                { "is-absolute", "mapping", map_tablet_mapping },
                { "keep-aspect", "keep-aspect", NULL },
                { "rotation", "left-handed", map_tablet_left_handed },
        };
        gchar *old_path, *new_path;
        const gchar *vendor, *product;

        vendor = gdk_device_get_vendor_id (device);
        product = gdk_device_get_product_id (device);

        old_path = g_strdup_printf ("/org/gnome/settings-daemon/peripherals/wacom/%s-usb:%s:%s/",
                                    manager->machine_id, vendor, product);
        new_path = g_strdup_printf ("/org/gnome/desktop/peripherals/tablets/%s:%s/",
                                    vendor, product);

        gsd_settings_migrate_check ("org.gnome.settings-daemon.peripherals.wacom.deprecated",
                                    old_path,
                                    "org.gnome.desktop.peripherals.tablet",
                                    new_path,
                                    tablet_settings, G_N_ELEMENTS (tablet_settings));

        /* Opaque tablets' mapping may be modified by users, so only these
         * need migration of settings.
         */
        if (is_opaque_tablet (manager, device)) {
                GsdSettingsMigrateEntry display_setting[] = {
                        { "display", "output", NULL },
                };

                gsd_settings_migrate_check ("org.gnome.desktop.peripherals.tablet.deprecated",
                                            new_path,
                                            "org.gnome.desktop.peripherals.tablet",
                                            new_path,
                                            display_setting, G_N_ELEMENTS (display_setting));
        }

        g_free (old_path);
        g_free (new_path);
}

static void
gsd_wacom_manager_class_init (GsdWacomManagerClass *klass)
{
        GObjectClass   *object_class = G_OBJECT_CLASS (klass);
        GApplicationClass *application_class = G_APPLICATION_CLASS (klass);

        object_class->finalize = gsd_wacom_manager_finalize;

        application_class->startup = gsd_wacom_manager_startup;
        application_class->shutdown = gsd_wacom_manager_shutdown;
}

static gchar *
get_device_path (GdkDevice *device)
{
#if HAVE_WAYLAND
        if (gnome_settings_is_wayland ())
                return g_strdup (gdk_wayland_device_get_node_path (device));
        else
#endif
                return xdevice_get_device_node (gdk_x11_device_get_id (device));
}

static gboolean
is_opaque_tablet (GsdWacomManager *manager,
                  GdkDevice       *device)
{
        gboolean is_opaque = FALSE;
#if HAVE_WACOM
        WacomDevice *wacom_device;
        gchar *devpath;

        devpath = get_device_path (device);
        wacom_device = libwacom_new_from_path (manager->wacom_db, devpath,
                                               WFALLBACK_GENERIC, NULL);
        if (wacom_device) {
                WacomIntegrationFlags integration_flags;

                integration_flags = libwacom_get_integration_flags (wacom_device);
                is_opaque = (integration_flags &
                             (WACOM_DEVICE_INTEGRATED_DISPLAY | WACOM_DEVICE_INTEGRATED_SYSTEM)) == 0;
                libwacom_destroy (wacom_device);
        }

#endif
        return is_opaque;
}

static GdkDevice *
lookup_device_by_path (GsdWacomManager *manager,
                       const gchar     *path)
{
        GList *devices, *l;

        devices = gdk_seat_get_slaves (manager->seat,
                                       GDK_SEAT_CAPABILITY_ALL);

        for (l = devices; l; l = l->next) {
                GdkDevice *device = l->data;
                gchar *dev_path = get_device_path (device);

                if (g_strcmp0 (dev_path, path) == 0) {
                        g_free (dev_path);
                        return device;
                }

                g_free (dev_path);
        }

        g_list_free (devices);

        return NULL;
}

static GSettings *
device_get_settings (GdkDevice *device)
{
        GSettings *settings;
        gchar *path;

        path = g_strdup_printf ("/org/gnome/desktop/peripherals/tablets/%s:%s/",
                                gdk_device_get_vendor_id (device),
                                gdk_device_get_product_id (device));
        settings = g_settings_new_with_path ("org.gnome.desktop.peripherals.tablet",
                                             path);
        g_free (path);

        return settings;
}

static void
handle_method_call (GDBusConnection       *connection,
                    const gchar           *sender,
                    const gchar           *object_path,
                    const gchar           *interface_name,
                    const gchar           *method_name,
                    GVariant              *parameters,
                    GDBusMethodInvocation *invocation,
                    gpointer               data)
{
	GsdWacomManager *self = GSD_WACOM_MANAGER (data);
        GError *error = NULL;
        GdkDevice *device;

        if (g_strcmp0 (method_name, "SetOLEDLabels") == 0) {
                gchar *device_path, *label;
                gboolean left_handed;
                GSettings *settings;
                GVariantIter *iter;
                gint i = 0;

		g_variant_get (parameters, "(sas)", &device_path, &iter);
                device = lookup_device_by_path (self, device_path);
                if (!device) {
                        g_dbus_method_invocation_return_value (invocation, NULL);
                        return;
                }

                settings = device_get_settings (device);
                left_handed = g_settings_get_boolean (settings, LEFT_HANDED_KEY);
                g_object_unref (settings);

                while (g_variant_iter_loop (iter, "s", &label)) {
                        if (!set_oled (device_path, left_handed, i, label, &error)) {
                                g_free (label);
                                break;
                        }
                        i++;
                }

                g_variant_iter_free (iter);

                if (error)
                        g_dbus_method_invocation_return_gerror (invocation, error);
                else
                        g_dbus_method_invocation_return_value (invocation, NULL);
        }
}

static const GDBusInterfaceVTable interface_vtable =
{
	handle_method_call,
	NULL, /* Get Property */
	NULL, /* Set Property */
};

static void
device_added_cb (GdkSeat         *seat,
                 GdkDevice       *device,
                 GsdWacomManager *manager)
{
        if (gdk_device_get_source (device) == GDK_SOURCE_PEN &&
            gdk_device_get_device_type (device) == GDK_DEVICE_TYPE_SLAVE) {
                migrate_tablet_settings (manager, device);
        }
}

static void
add_devices (GsdWacomManager     *manager,
             GdkSeatCapabilities  capabilities)
{
        GList *devices, *l;

        devices = gdk_seat_get_slaves (manager->seat, capabilities);
        for (l = devices; l ; l = l->next)
		device_added_cb (manager->seat, l->data, manager);
        g_list_free (devices);
}

static void
set_devicepresence_handler (GsdWacomManager *manager)
{
        GdkSeat *seat;

        seat = gdk_display_get_default_seat (gdk_display_get_default ());
        manager->device_added_id = g_signal_connect (seat, "device-added",
                                                           G_CALLBACK (device_added_cb), manager);
        manager->seat = seat;
}

static void
gsd_wacom_manager_init (GsdWacomManager *manager)
{
#if HAVE_WACOM
        manager->wacom_db = libwacom_database_new ();
#endif
}

static gboolean
gsd_wacom_manager_idle_cb (GsdWacomManager *manager)
{
        gnome_settings_profile_start (NULL);

        set_devicepresence_handler (manager);

        add_devices (manager, GDK_SEAT_CAPABILITY_TABLET_STYLUS);

        gnome_settings_profile_end (NULL);

        manager->start_idle_id = 0;

        return FALSE;
}

static void
on_bus_gotten (GObject		   *source_object,
	       GAsyncResult	   *res,
	       GsdWacomManager	   *manager)
{
	GDBusConnection	       *connection;
	GError		       *error = NULL;

	connection = g_bus_get_finish (res, &error);

	if (connection == NULL) {
		if (!g_error_matches (error, G_IO_ERROR, G_IO_ERROR_CANCELLED))
			g_warning ("Couldn't get session bus: %s", error->message);
		g_error_free (error);
		return;
	}

	manager->dbus_connection = connection;
	manager->dbus_register_object_id = g_dbus_connection_register_object (connection,
									      GSD_WACOM_DBUS_PATH,
									      manager->introspection_data->interfaces[0],
									      &interface_vtable,
									      manager,
									      NULL,
									      &error);

	if (manager->dbus_register_object_id == 0) {
		g_warning ("Error registering object: %s", error->message);
		g_error_free (error);
		return;
	}

        manager->name_id = g_bus_own_name_on_connection (connection,
                                                         GSD_WACOM_DBUS_NAME,
                                                         G_BUS_NAME_OWNER_FLAGS_NONE,
                                                         NULL,
                                                         NULL,
                                                         NULL,
                                                         NULL);
}

static void
register_manager (GsdWacomManager *manager)
{
        manager->introspection_data = g_dbus_node_info_new_for_xml (introspection_xml, NULL);
        manager->dbus_cancellable = g_cancellable_new ();
        g_assert (manager->introspection_data != NULL);

        g_bus_get (G_BUS_TYPE_SESSION,
                   manager->dbus_cancellable,
                   (GAsyncReadyCallback) on_bus_gotten,
                   manager);
}

static gchar *
get_machine_id (void)
{
        gchar *no_per_machine_file, *machine_id = NULL;
        gboolean per_machine;
        gsize len;

        no_per_machine_file = g_build_filename (g_get_user_config_dir (), "gnome-settings-daemon", "no-per-machine-config", NULL);
        per_machine = !g_file_test (no_per_machine_file, G_FILE_TEST_EXISTS);
        g_free (no_per_machine_file);

        if (!per_machine ||
            (!g_file_get_contents ("/etc/machine-id", &machine_id, &len, NULL) &&
             !g_file_get_contents ("/var/lib/dbus/machine-id", &machine_id, &len, NULL))) {
                return g_strdup ("00000000000000000000000000000000");
        }

        machine_id[len - 1] = '\0';
        return machine_id;
}

static void
gsd_wacom_manager_startup (GApplication *app)
{
        GsdWacomManager *manager = GSD_WACOM_MANAGER (app);

        gnome_settings_profile_start (NULL);

        register_manager (manager);

        manager->machine_id = get_machine_id ();

        manager->start_idle_id = g_idle_add ((GSourceFunc) gsd_wacom_manager_idle_cb, manager);
        g_source_set_name_by_id (manager->start_idle_id, "[gnome-settings-daemon] gsd_wacom_manager_idle_cb");

        G_APPLICATION_CLASS (gsd_wacom_manager_parent_class)->startup (app);

        gnome_settings_profile_end (NULL);
}

static void
gsd_wacom_manager_shutdown (GApplication *app)
{
        GsdWacomManager *manager = GSD_WACOM_MANAGER (app);

        g_debug ("Stopping wacom manager");

        g_clear_pointer (&manager->machine_id, g_free);

        if (manager->name_id != 0) {
                g_bus_unown_name (manager->name_id);
                manager->name_id = 0;
        }

        if (manager->dbus_register_object_id) {
                g_dbus_connection_unregister_object (manager->dbus_connection,
                                                     manager->dbus_register_object_id);
                manager->dbus_register_object_id = 0;
        }

        if (manager->seat != NULL) {
                g_signal_handler_disconnect (manager->seat, manager->device_added_id);
                manager->seat = NULL;
        }

        g_clear_handle_id (&manager->start_idle_id, g_source_remove);

        g_clear_pointer (&manager->introspection_data, g_dbus_node_info_unref);

        if (manager->dbus_cancellable != NULL) {
                g_cancellable_cancel (manager->dbus_cancellable);
                g_clear_object (&manager->dbus_cancellable);
        }

        g_clear_object (&manager->dbus_connection);

        G_APPLICATION_CLASS (gsd_wacom_manager_parent_class)->shutdown (app);
}

static void
gsd_wacom_manager_finalize (GObject *object)
{
        GsdWacomManager *wacom_manager;

        g_return_if_fail (object != NULL);
        g_return_if_fail (GSD_IS_WACOM_MANAGER (object));

        wacom_manager = GSD_WACOM_MANAGER (object);

        g_return_if_fail (wacom_manager != NULL);

        g_clear_object (&wacom_manager->shell_proxy);

#if HAVE_WACOM
        libwacom_database_destroy (wacom_manager->wacom_db);
#endif

        G_OBJECT_CLASS (gsd_wacom_manager_parent_class)->finalize (object);
}
