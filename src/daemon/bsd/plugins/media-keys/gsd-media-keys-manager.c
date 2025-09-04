/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 8 -*-
 *
 * Copyright (C) 2001-2003 Bastien Nocera <hadess@hadess.net>
 * Copyright (C) 2006-2007 William Jon McCann <mccann@jhu.edu>
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

#include <sys/types.h>
#include <sys/wait.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <math.h>

#include <locale.h>

#include <glib.h>
#include <glib/gi18n.h>
#include <gio/gio.h>
#include <gdk/gdk.h>
#include <gtk/gtk.h>
#include <gio/gdesktopappinfo.h>
#include <gio/gunixfdlist.h>

#include <libupower-glib/upower.h>
#include <gdesktop-enums.h>
#define GNOME_DESKTOP_USE_UNSTABLE_API
#include <libgnome-desktop/gnome-systemd.h>

#if HAVE_GUDEV
#include <gudev/gudev.h>
#endif

#include "gsd-settings-migrate.h"

#include "mpris-controller.h"
#include "gnome-settings-bus.h"
#include "gnome-settings-profile.h"
#include "gsd-marshal.h"
#include "gsd-media-keys-manager.h"

#include "shortcuts-list.h"
#include "shell-key-grabber.h"
#include "gsd-input-helper.h"
#include "gnome-settings-daemon/gsd-enums.h"
#include "gsd-shell-helper.h"

#include <canberra.h>
#include <pulse/pulseaudio.h>
#include "gvc-mixer-control.h"
#include "gvc-mixer-sink.h"

#define GSD_DBUS_PATH "/org/gnome/SettingsDaemon"
#define GSD_DBUS_NAME "org.gnome.SettingsDaemon"
#define GSD_DBUS_BASE_INTERFACE "org.gnome.SettingsDaemon"

#define GSD_MEDIA_KEYS_DBUS_PATH GSD_DBUS_PATH "/MediaKeys"
#define GSD_MEDIA_KEYS_DBUS_NAME GSD_DBUS_NAME ".MediaKeys"

#define GNOME_KEYRING_DBUS_NAME "org.gnome.keyring"
#define GNOME_KEYRING_DBUS_PATH "/org/gnome/keyring/daemon"
#define GNOME_KEYRING_DBUS_INTERFACE "org.gnome.keyring.Daemon"

#define SHELL_DBUS_NAME "org.gnome.Shell"
#define SHELL_DBUS_PATH "/org/gnome/Shell"

#define CUSTOM_BINDING_SCHEMA SETTINGS_BINDING_DIR ".custom-keybinding"

#define SETTINGS_SOUND_DIR "org.gnome.desktop.sound"
#define ALLOW_VOLUME_ABOVE_100_PERCENT_KEY "allow-volume-above-100-percent"

#define SHELL_GRABBER_CALL_TIMEOUT G_MAXINT
#define SHELL_GRABBER_RETRY_INTERVAL_MS 1000

/* How long to suppress power-button presses after resume,
 * 3 seconds is the minimum necessary to make resume reliable */
#define GSD_REENABLE_POWER_BUTTON_DELAY                 3000 /* ms */

#define SETTINGS_INTERFACE_DIR "org.gnome.desktop.interface"
#define SETTINGS_POWER_DIR "org.gnome.settings-daemon.plugins.power"
#define SETTINGS_XSETTINGS_DIR "org.gnome.settings-daemon.plugins.xsettings"
#define SETTINGS_TOUCHPAD_DIR "org.gnome.desktop.peripherals.touchpad"
#define TOUCHPAD_ENABLED_KEY "send-events"
#define HIGH_CONTRAST "HighContrast"

#define REWIND_USEC (-10 * G_USEC_PER_SEC)
#define FASTFORWARD_USEC (45 * G_USEC_PER_SEC)

#define VOLUME_STEP "volume-step"
#define VOLUME_STEP_PRECISE 2
#define MAX_VOLUME 65536.0

#define SYSTEMD_DBUS_NAME                       "org.freedesktop.login1"
#define SYSTEMD_DBUS_PATH                       "/org/freedesktop/login1"
#define SYSTEMD_DBUS_INTERFACE                  "org.freedesktop.login1.Manager"

#define AUDIO_SELECTION_DBUS_NAME               "org.gnome.Shell.AudioDeviceSelection"
#define AUDIO_SELECTION_DBUS_PATH               "/org/gnome/Shell/AudioDeviceSelection"
#define AUDIO_SELECTION_DBUS_INTERFACE          "org.gnome.Shell.AudioDeviceSelection"

#define GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE(o) (gsd_media_keys_manager_get_instance_private (o))

typedef struct {
        char   *application;
        char   *dbus_name;
        guint32 time;
        guint   watch_id;
} MediaPlayer;

typedef struct {
        gint ref_count;

        MediaKeyType key_type;
        ShellActionMode modes;
        MetaKeyBindingFlags grab_flags;
        const char *settings_key;
        gboolean static_setting;
        char *custom_path;
        char *custom_command;
        GArray *accel_ids;
} MediaKey;

typedef struct {
        GsdMediaKeysManager *manager;
        GPtrArray *keys;

        /* NOTE: This is to implement a custom cancellation handling where
         *       we immediately emit an ungrab call if grabbing was cancelled.
         */
        gboolean cancelled;
} GrabUngrabData;

typedef struct
{
        /* Volume bits */
        GvcMixerControl *volume;
        GvcMixerStream  *sink;
        GvcMixerStream  *source;
        ca_context      *ca;
        GSettings       *sound_settings;
        pa_volume_t      max_volume;
        GtkSettings     *gtksettings;
#if HAVE_GUDEV
        GHashTable      *streams; /* key = X device ID, value = stream id */
        GUdevClient     *udev_client;
#endif /* HAVE_GUDEV */
        guint            audio_selection_watch_id;
        guint            audio_selection_signal_id;
        GDBusConnection *audio_selection_conn;
        gboolean         audio_selection_requested;
        guint            audio_selection_device_id;

        GSettings       *settings;
        GHashTable      *custom_settings;

        GPtrArray       *keys;

        /* HighContrast theme settings */
        GSettings       *interface_settings;
        char            *icon_theme;
        char            *gtk_theme;

        /* Power stuff */
        GSettings       *power_settings;
        GDBusProxy      *power_proxy;
        GDBusProxy      *power_screen_proxy;
        GDBusProxy      *power_keyboard_proxy;
        UpDevice        *composite_device;
        char            *chassis_type;
        gboolean         power_button_disabled;
        guint            reenable_power_button_timer_id;

        /* Shell stuff */
        GsdShell        *shell_proxy;
        ShellKeyGrabber *key_grabber;
        GCancellable    *grab_cancellable;
        GHashTable      *keys_to_sync;
        guint            keys_sync_source_id;
        GrabUngrabData  *keys_sync_data;

        /* ScreenSaver stuff */
        GsdScreenSaver  *screen_saver_proxy;

        /* Rotation */
        guint            iio_sensor_watch_id;
        gboolean         has_accel;
        GDBusProxy      *iio_sensor_proxy;

        /* RFKill stuff */
        guint            rfkill_watch_id;
        guint64          rfkill_last_time;
        GDBusProxy      *rfkill_proxy;
        GCancellable    *rfkill_cancellable;

        /* systemd stuff */
        GDBusProxy      *logind_proxy;
        gint             inhibit_keys_fd;
        gint             inhibit_suspend_fd;
        gboolean         inhibit_suspend_taken;

        GDBusConnection *connection;
        GCancellable    *bus_cancellable;

        guint            start_idle_id;

        /* Multimedia keys */
        MprisController *mpris_controller;
} GsdMediaKeysManagerPrivate;

static void     gsd_media_keys_manager_class_init  (GsdMediaKeysManagerClass *klass);
static void     gsd_media_keys_manager_init        (GsdMediaKeysManager      *media_keys_manager);
static void     gsd_media_keys_manager_finalize    (GObject                  *object);
static void     register_manager                   (GsdMediaKeysManager      *manager);
static void     custom_binding_changed             (GSettings           *settings,
                                                    const char          *settings_key,
                                                    GsdMediaKeysManager *manager);
static void     keys_sync_queue                    (GsdMediaKeysManager *manager,
                                                    gboolean             immediate,
                                                    gboolean             retry);
static void     keys_sync_continue                 (GsdMediaKeysManager *manager);


G_DEFINE_TYPE_WITH_PRIVATE (GsdMediaKeysManager, gsd_media_keys_manager, G_TYPE_APPLICATION)

static void
media_key_unref (MediaKey *key)
{
        if (key == NULL)
                return;
        if (!g_atomic_int_dec_and_test (&key->ref_count))
                return;
        g_clear_pointer (&key->accel_ids, g_array_unref);
        g_free (key->custom_path);
        g_free (key->custom_command);
        g_free (key);
}

static MediaKey *
media_key_ref (MediaKey *key)
{
        g_atomic_int_inc (&key->ref_count);
        return key;
}

static MediaKey *
media_key_new (void)
{
        MediaKey *key = g_new0 (MediaKey, 1);

        key->accel_ids = g_array_new (FALSE, TRUE, sizeof(guint));

        return media_key_ref (key);
}

G_DEFINE_AUTOPTR_CLEANUP_FUNC (MediaKey, media_key_unref)

static void
grab_ungrab_data_free (GrabUngrabData *data)
{
        /* NOTE: The manager pointer is not owned and is invalid if the
         *       operation was cancelled.
         */

        if (!data->cancelled) {
                GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (data->manager);

                if (priv->keys_sync_data == data)
                        priv->keys_sync_data = NULL;
        }

        data->manager = NULL;
        g_clear_pointer (&data->keys, g_ptr_array_unref);
        g_free (data);
}

G_DEFINE_AUTOPTR_CLEANUP_FUNC (GrabUngrabData, grab_ungrab_data_free)

static void
set_launch_context_env (GsdMediaKeysManager *manager,
			GAppLaunchContext   *launch_context)
{
	GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
	GError *error = NULL;
	GVariant *variant, *item;
	GVariantIter *iter;

	variant = g_dbus_connection_call_sync (priv->connection,
					       GNOME_KEYRING_DBUS_NAME,
					       GNOME_KEYRING_DBUS_PATH,
					       GNOME_KEYRING_DBUS_INTERFACE,
					       "GetEnvironment",
					       NULL,
					       NULL,
					       G_DBUS_CALL_FLAGS_NONE,
					       -1,
					       NULL,
					       &error);
	if (variant == NULL) {
		g_warning ("Failed to call GetEnvironment on keyring daemon: %s", error->message);
		g_error_free (error);
		return;
	}

	g_variant_get (variant, "(a{ss})", &iter);

	while ((item = g_variant_iter_next_value (iter))) {
		char *key;
		char *value;

		g_variant_get (item,
			       "{ss}",
			       &key,
			       &value);

		g_app_launch_context_setenv (launch_context, key, value);

		g_variant_unref (item);
		g_free (key);
		g_free (value);
	}

	g_variant_iter_free (iter);
	g_variant_unref (variant);
}

static char *
get_key_string (MediaKey *key)
{
	if (key->settings_key != NULL)
		return g_strdup_printf ("settings:%s", key->settings_key);
	else if (key->custom_path != NULL)
		return g_strdup_printf ("custom:%s", key->custom_path);
	else
		g_assert_not_reached ();
}

static GStrv
get_bindings (GsdMediaKeysManager *manager,
	      MediaKey            *key)
{
	GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
	GPtrArray *array;
	gchar *binding;

	if (key->settings_key != NULL) {
		g_autofree gchar *static_settings_key = NULL;
		g_autofree GStrv keys = NULL;
		g_autofree GStrv static_keys = NULL;
		gchar **item;

		if (!key->static_setting)
			return g_settings_get_strv (priv->settings, key->settings_key);

		static_settings_key = g_strconcat (key->settings_key, "-static", NULL);
		keys = g_settings_get_strv (priv->settings, key->settings_key);
		static_keys = g_settings_get_strv (priv->settings, static_settings_key);

		array = g_ptr_array_new ();
		/* Steals all strings from the settings */
		for (item = keys; *item; item++)
			g_ptr_array_add (array, *item);
		for (item = static_keys; *item; item++)
			g_ptr_array_add (array, *item);
		g_ptr_array_add (array, NULL);

		return (GStrv) g_ptr_array_free (array, FALSE);
	}

	else if (key->custom_path != NULL) {
                GSettings *settings;

                settings = g_hash_table_lookup (priv->custom_settings,
                                                key->custom_path);
		binding = g_settings_get_string (settings, "binding");
	} else
		g_assert_not_reached ();

        array = g_ptr_array_new ();
        g_ptr_array_add (array, binding);
        g_ptr_array_add (array, NULL);

        return (GStrv) g_ptr_array_free (array, FALSE);
}

static void
show_osd_with_max_level (GsdMediaKeysManager *manager,
                         const char          *icon,
                         const char          *label,
                         double               level,
                         double               max_level,
                         const gchar         *connector)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);

        if (priv->shell_proxy == NULL)
                return;

        shell_show_osd_with_max_level (priv->shell_proxy,
                                       icon, label, level, max_level, connector);
}

static void
show_osd (GsdMediaKeysManager *manager,
          const char          *icon,
          const char          *label,
          double               level,
          const char          *connector)
{
        show_osd_with_max_level(manager,
                                icon, label, level, -1, connector);
}

static const char *
get_icon_name_for_volume (gboolean is_mic,
                          gboolean muted,
                          double volume)
{
        static const char *icon_names[] = {
                "audio-volume-muted-symbolic",
                "audio-volume-low-symbolic",
                "audio-volume-medium-symbolic",
                "audio-volume-high-symbolic",
                "audio-volume-overamplified-symbolic",
                NULL
        };
        static const char *mic_icon_names[] = {
                "microphone-sensitivity-muted-symbolic",
                "microphone-sensitivity-low-symbolic",
                "microphone-sensitivity-medium-symbolic",
                "microphone-sensitivity-high-symbolic",
                NULL
        };
        int n;

        if (muted) {
                n = 0;
        } else {
                /* select image */
                n = ceill (3.0 * volume);
                if (n < 1)
                        n = 1;
                /* output volume above 100% */
                else if (n > 3 && !is_mic)
                        n = 4;
                else if (n > 3)
                        n = 3;
        }

	if (is_mic)
		return mic_icon_names[n];
	else
		return icon_names[n];
}

static void
ungrab_accelerators_complete (GObject      *object,
                              GAsyncResult *result,
                              gpointer      user_data)
{
        g_autoptr(GrabUngrabData) data = user_data;
        gboolean success = FALSE;
        g_autoptr(GError) error = NULL;
        gint i;

        g_debug ("Ungrab call completed!");

        if (!shell_key_grabber_call_ungrab_accelerators_finish (SHELL_KEY_GRABBER (object),
                                                                &success, result, &error)) {
                g_warning ("Failed to ungrab accelerators: %s", error->message);

                if (g_error_matches (error, G_DBUS_ERROR, G_DBUS_ERROR_UNKNOWN_METHOD)) {
                        keys_sync_queue (data->manager, FALSE, TRUE);
                        return;
                }

                /* We are screwed at this point; we'll still keep going assuming that we don't
                 * have the bindings registered anymore.
                 * The only alternative would be to die and force cleanup of all registered
                 * grabs that way.
                 */
        } else if (!success) {
                g_warning ("Failed to ungrab some accelerators, they were probably not registered!");
        }

        /* Clear the accelerator IDs. */
        for (i = 0; i < data->keys->len; i++) {
                MediaKey *key;

                key = g_ptr_array_index (data->keys, i);

                /* Always clear, as it would just fail again the next time. */
                g_array_set_size (key->accel_ids, 0);
        }

        /* Nothing left to do if the operation was cancelled */
        if (data->cancelled)
                return;

        keys_sync_continue (data->manager);
}

static void
grab_accelerators_complete (GObject      *object,
                            GAsyncResult *result,
                            gpointer      user_data)
{
        g_autoptr(GrabUngrabData) data = user_data;
        g_autoptr(GVariant) actions = NULL;
        g_autoptr(GError) error = NULL;
        gint i;

        g_debug ("Grab call completed!");

        if (!shell_key_grabber_call_grab_accelerators_finish (SHELL_KEY_GRABBER (object),
                                                              &actions, result, &error)) {
                g_warning ("Failed to grab accelerators: %s", error->message);

                if (g_error_matches (error, G_DBUS_ERROR, G_DBUS_ERROR_UNKNOWN_METHOD)) {
                        keys_sync_queue (data->manager, FALSE, TRUE);
                        return;
                }

                /* We are screwed at this point as we can't grab the keys. Most likely
                 * this means we are not running on GNOME, or ran into some other weird
                 * error.
                 * Either way, finish the operation as there is no way we can recover
                 * from this.
                 */
                keys_sync_continue (data->manager);
                return;
        }

        /* Do an immediate ungrab if the operation was cancelled.
         * This may happen on daemon shutdown for example. */
        if (data->cancelled) {
                g_debug ("Doing an immediate ungrab on the grabbed accelerators!");

                shell_key_grabber_call_ungrab_accelerators (SHELL_KEY_GRABBER (object),
                                                            actions,
                                                            NULL,
                                                            ungrab_accelerators_complete,
                                                            g_steal_pointer (&data));

                return;
        }

        /* We need to stow away the accel_ids that have been registered successfully. */
        for (i = 0; i < data->keys->len; i++) {
                MediaKey *key;

                key = g_ptr_array_index (data->keys, i);
                g_assert (key->accel_ids->len == 0);
        }
        for (i = 0; i < data->keys->len; i++) {
                MediaKey *key;
                guint accel_id;

                key = g_ptr_array_index (data->keys, i);

                g_variant_get_child (actions, i, "u", &accel_id);
                if (accel_id == 0) {
                        g_autofree gchar *tmp = NULL;
                        tmp = get_key_string (key);
                        g_warning ("Failed to grab accelerator for keybinding %s", tmp);
                } else {
                        g_array_append_val (key->accel_ids, accel_id);
                }
        }

        keys_sync_continue (data->manager);
}

static void
keys_sync_continue (GsdMediaKeysManager *manager)
{
	GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        g_auto(GVariantBuilder) ungrab_builder = G_VARIANT_BUILDER_INIT (G_VARIANT_TYPE ("au"));
        g_auto(GVariantBuilder) grab_builder = G_VARIANT_BUILDER_INIT (G_VARIANT_TYPE ("a(suu)"));
        g_autoptr(GPtrArray) keys_being_ungrabbed = NULL;
        g_autoptr(GPtrArray) keys_being_grabbed = NULL;
        g_autoptr(GrabUngrabData) data = NULL;
        GHashTableIter iter;
        MediaKey *key;
        gboolean need_ungrab = FALSE;

        /* Syncing keys is a two step process in principle, i.e. we first ungrab all keys
         * and then grab the new ones.
         * To make this work, this function will be called multiple times and it will
         * either emit an ungrab or grab call or do nothing when done.
         */

        /* If the keys_to_sync hash table is empty at this point, then we are done.
         * priv->keys_sync_data will be cleared automatically when it is unref'ed.
         */
        if (g_hash_table_size (priv->keys_to_sync) == 0)
                return;

        keys_being_ungrabbed = g_ptr_array_new_with_free_func ((GDestroyNotify) media_key_unref);
        keys_being_grabbed = g_ptr_array_new_with_free_func ((GDestroyNotify) media_key_unref);

        g_hash_table_iter_init (&iter, priv->keys_to_sync);
        while (g_hash_table_iter_next (&iter, (gpointer*) &key, NULL)) {
                g_auto(GStrv) bindings = NULL;
                gchar **pos = NULL;
                gint i;

                for (i = 0; i < key->accel_ids->len; i++) {
                        g_variant_builder_add (&ungrab_builder, "u", g_array_index (key->accel_ids, guint, i));
                        g_ptr_array_add (keys_being_ungrabbed, media_key_ref (key));

                        need_ungrab = TRUE;
                }

                /* Keys that are synced but aren't in the internal list are being removed. */
                if (!g_ptr_array_find (priv->keys, key, NULL))
                        continue;

                bindings = get_bindings (manager, key);
                pos = bindings;
                while (*pos) {
                        /* Do not try to register empty keybindings. */
                        if (strlen (*pos) > 0) {
                                g_variant_builder_add (&grab_builder, "(suu)", *pos, key->modes, key->grab_flags);
                                g_ptr_array_add (keys_being_grabbed, media_key_ref (key));
                        }
                        pos++;
                }
        }

        data = g_new0 (GrabUngrabData, 1);
        data->manager = manager;

        /* These calls intentionally do not get a cancellable. See comment in
         * GrabUngrabData.
         */
        priv->keys_sync_data = data;

        if (need_ungrab) {
                data->keys = g_steal_pointer (&keys_being_ungrabbed);

                shell_key_grabber_call_ungrab_accelerators (priv->key_grabber,
                                                            g_variant_builder_end (&ungrab_builder),
                                                            NULL,
                                                            ungrab_accelerators_complete,
                                                            g_steal_pointer (&data));
        } else {
                data->keys = g_steal_pointer (&keys_being_grabbed);

                g_hash_table_remove_all (priv->keys_to_sync);

                shell_key_grabber_call_grab_accelerators (priv->key_grabber,
                                                          g_variant_builder_end (&grab_builder),
                                                          NULL,
                                                          grab_accelerators_complete,
                                                          g_steal_pointer (&data));
        }
}

static gboolean
keys_sync_start (gpointer user_data)
{
        GsdMediaKeysManager *manager = GSD_MEDIA_KEYS_MANAGER (user_data);
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);

        priv->keys_sync_source_id = 0;
        g_assert (priv->keys_sync_data == NULL);
        keys_sync_continue (manager);

        return G_SOURCE_REMOVE;
}

void
keys_sync_queue (GsdMediaKeysManager *manager, gboolean immediate, gboolean retry)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        guint i;

        if (priv->keys_sync_source_id)
                g_source_remove (priv->keys_sync_source_id);

        if (retry) {
                /* Abort the currently running operation, and don't retry
                 * immediately to avoid race condition if an operation was
                 * already active. */
                if (priv->keys_sync_data) {
                        priv->keys_sync_data->cancelled = TRUE;
                        priv->keys_sync_data = NULL;

                        immediate = FALSE;
                }

                /* Mark all existing keys for sync. */
                for (i = 0; i < priv->keys->len; i++) {
                        MediaKey *key = g_ptr_array_index (priv->keys, i);
                        g_hash_table_add (priv->keys_to_sync, media_key_ref (key));
                }
        } else if (priv->keys_sync_data) {
                /* We are already actively syncing, no need to do anything. */
                return;
        }

        priv->keys_sync_source_id =
                g_timeout_add (immediate ? 0 : (retry ? SHELL_GRABBER_RETRY_INTERVAL_MS : 50),
                               keys_sync_start,
                               manager);
}

static void
gsettings_changed_cb (GSettings           *settings,
                      const gchar         *settings_key,
                      GsdMediaKeysManager *manager)
{
	GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        int      i;

        /* Give up if we don't have proxy to the shell */
        if (!priv->key_grabber)
                return;

	/* handled in gsettings_custom_changed_cb() */
        if (g_str_equal (settings_key, "custom-keybindings"))
		return;

        /* Find the key that was modified */
        if (priv->keys == NULL)
                return;

        for (i = 0; i < priv->keys->len; i++) {
                MediaKey *key;

                key = g_ptr_array_index (priv->keys, i);

                /* Skip over hard-coded and GConf keys */
                if (key->settings_key == NULL)
                        continue;
                if (strcmp (settings_key, key->settings_key) == 0) {
                        g_hash_table_add (priv->keys_to_sync, media_key_ref (key));
                        keys_sync_queue (manager, FALSE, FALSE);
                        break;
                }
        }
}

static MediaKey *
media_key_new_for_path (GsdMediaKeysManager *manager,
			char                *path)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        GSettings *settings;
        char *command, *binding;
        MediaKey *key;

        g_debug ("media_key_new_for_path: %s", path);

	settings = g_hash_table_lookup (priv->custom_settings, path);
	if (settings == NULL) {
		settings = g_settings_new_with_path (CUSTOM_BINDING_SCHEMA, path);

		g_signal_connect (settings, "changed",
				  G_CALLBACK (custom_binding_changed), manager);
		g_hash_table_insert (priv->custom_settings,
				     g_strdup (path), settings);
	}

        command = g_settings_get_string (settings, "command");
        binding = g_settings_get_string (settings, "binding");

        if (*command == '\0' && *binding == '\0') {
                g_debug ("Key binding (%s) is incomplete", path);
                g_free (command);
                g_free (binding);
                return NULL;
        }
        g_free (binding);

        key = media_key_new ();
        key->key_type = CUSTOM_KEY;
	if (g_settings_get_boolean (settings, "enable-in-lockscreen"))
		key->modes = GSD_ACTION_MODE_SCRIPT;
	else
		key->modes = GSD_ACTION_MODE_LAUNCHER;
        key->custom_path = g_strdup (path);
        key->custom_command = command;
        key->grab_flags = META_KEY_BINDING_NONE;

        return key;
}

static void
update_custom_binding (GsdMediaKeysManager *manager,
                       char                *path)
{
	GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        MediaKey *key;
        int i;

        /* Remove the existing key */
        for (i = 0; i < priv->keys->len; i++) {
                key = g_ptr_array_index (priv->keys, i);

                if (key->custom_path == NULL)
                        continue;
                if (strcmp (key->custom_path, path) == 0) {
                        g_debug ("Removing custom key binding %s", path);
                        g_hash_table_add (priv->keys_to_sync, media_key_ref (key));
                        g_ptr_array_remove_index_fast (priv->keys, i);
                        break;
                }
        }

        /* And create a new one! */
        key = media_key_new_for_path (manager, path);
        if (key) {
                g_debug ("Adding new custom key binding %s", path);
                g_ptr_array_add (priv->keys, key);

                g_hash_table_add (priv->keys_to_sync, media_key_ref (key));
        }

        keys_sync_queue (manager, FALSE, FALSE);
}

static void
update_custom_binding_command (GsdMediaKeysManager *manager,
                               GSettings           *settings,
                               char                *path)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        MediaKey *key;
        int i;

        for (i = 0; i < priv->keys->len; i++) {
                key = g_ptr_array_index (priv->keys, i);

                if (key->custom_path == NULL)
                        continue;
                if (strcmp (key->custom_path, path) == 0) {
                        g_free (key->custom_command);
                        key->custom_command = g_settings_get_string (settings, "command");
                        break;
                }
        }
}

static void
custom_binding_changed (GSettings           *settings,
                        const char          *settings_key,
                        GsdMediaKeysManager *manager)
{
        char *path;

        g_object_get (settings, "path", &path, NULL);

        if (strcmp (settings_key, "binding") == 0)
                update_custom_binding (manager, path);
        else if (strcmp (settings_key, "command") == 0)
                update_custom_binding_command (manager, settings, path);

        g_free (path);
}

static void
gsettings_custom_changed_cb (GSettings           *settings,
                             const char          *settings_key,
                             GsdMediaKeysManager *manager)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        char **bindings;
        int i, j, n_bindings;

        bindings = g_settings_get_strv (settings, settings_key);
        n_bindings = g_strv_length (bindings);

        /* Handle additions */
        for (i = 0; i < n_bindings; i++) {
                if (g_hash_table_lookup (priv->custom_settings,
                                         bindings[i]))
                        continue;
                update_custom_binding (manager, bindings[i]);
        }

        /* Handle removals */
        for (i = 0; i < priv->keys->len; i++) {
                gboolean found = FALSE;
                MediaKey *key = g_ptr_array_index (priv->keys, i);
                if (key->key_type != CUSTOM_KEY)
                        continue;

                for (j = 0; j < n_bindings && !found; j++)
                        found = strcmp (bindings[j], key->custom_path) == 0;

                if (found)
                        continue;

                g_hash_table_add (priv->keys_to_sync, media_key_ref (key));
                g_hash_table_remove (priv->custom_settings,
                                     key->custom_path);
                g_ptr_array_remove_index_fast (priv->keys, i);
                --i; /* make up for the removed key */
        }
        keys_sync_queue (manager, FALSE, FALSE);
        g_strfreev (bindings);
}

static void
add_key (GsdMediaKeysManager *manager, guint i)
{
	GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
	MediaKey *key;

	key = media_key_new ();
	key->key_type = media_keys[i].key_type;
	key->settings_key = media_keys[i].settings_key;
	key->static_setting = media_keys[i].static_setting;
	key->modes = media_keys[i].modes;
	key->grab_flags = media_keys[i].grab_flags;

	g_ptr_array_add (priv->keys, key);
}

static void
init_kbd (GsdMediaKeysManager *manager)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        char **custom_paths;
        int i;

        gnome_settings_profile_start (NULL);

        for (i = 0; i < G_N_ELEMENTS (media_keys); i++)
                add_key (manager, i);

        /* Custom shortcuts */
        custom_paths = g_settings_get_strv (priv->settings,
                                            "custom-keybindings");

        for (i = 0; i < g_strv_length (custom_paths); i++) {
                MediaKey *key;

                g_debug ("Setting up custom keybinding %s", custom_paths[i]);

                key = media_key_new_for_path (manager, custom_paths[i]);
                if (!key) {
                        continue;
                }
                g_ptr_array_add (priv->keys, key);
        }
        g_strfreev (custom_paths);

        keys_sync_queue (manager, TRUE, TRUE);

        gnome_settings_profile_end (NULL);
}

static void
app_launched_cb (GAppLaunchContext *context,
                 GAppInfo          *info,
                 GVariant          *platform_data,
                 gpointer           user_data)
{
        GsdMediaKeysManager *manager = GSD_MEDIA_KEYS_MANAGER (user_data);
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        gint32 pid;
        const gchar *app_name;

        if (!g_variant_lookup (platform_data, "pid", "i", &pid))
                return;

        app_name = g_app_info_get_id (info);
        if (app_name == NULL)
                app_name = g_app_info_get_executable (info);

        /* Start async request; we don't care about the result */
        gnome_start_systemd_scope (app_name,
                                   pid,
                                   NULL,
                                   priv->connection,
                                   NULL, NULL, NULL);
}

static void
launch_app (GsdMediaKeysManager *manager,
	    GAppInfo            *app_info,
	    gint64               timestamp)
{
	GError *error = NULL;
        GdkAppLaunchContext *launch_context;

        /* setup the launch context so the startup notification is correct */
        launch_context = gdk_display_get_app_launch_context (gdk_display_get_default ());
        gdk_app_launch_context_set_timestamp (launch_context, timestamp);
        set_launch_context_env (manager, G_APP_LAUNCH_CONTEXT (launch_context));

        g_signal_connect_object (launch_context,
                                 "launched",
                                 G_CALLBACK (app_launched_cb),
                                 manager,
                                 0);

	if (!g_app_info_launch (app_info, NULL, G_APP_LAUNCH_CONTEXT (launch_context), &error)) {
		g_warning ("Could not launch '%s': %s",
			   g_app_info_get_commandline (app_info),
			   error->message);
		g_error_free (error);
	}
        g_object_unref (launch_context);
}

static void
execute (GsdMediaKeysManager *manager,
         char                *cmd,
         gint64               timestamp)
{
	GAppInfo *app_info;
	g_autofree gchar *escaped = NULL;
	gchar *p;

	/* Escape all % characters as g_app_info_create_from_commandline will
	 * try to interpret them otherwise. */
	escaped = g_malloc (strlen (cmd) * 2 + 1);
	p = escaped;
	while (*cmd) {
		*p = *cmd;
		p++;
		if (*cmd == '%') {
			*p = '%';
			p++;
		}
		cmd++;
	}
	*p = '\0';

	app_info = g_app_info_create_from_commandline (escaped, NULL, G_APP_INFO_CREATE_NONE, NULL);
	launch_app (manager, app_info, timestamp);
	g_object_unref (app_info);
}

static void
do_url_action (GsdMediaKeysManager *manager,
               const char          *scheme,
               gint64               timestamp)
{
        GAppInfo *app_info;

        app_info = g_app_info_get_default_for_uri_scheme (scheme);
        if (app_info != NULL) {
                launch_app (manager, app_info, timestamp);
                g_object_unref (app_info);
        } else {
                g_warning ("Could not find default application for '%s' scheme", scheme);
	}
}

static void
do_media_action (GsdMediaKeysManager *manager,
		 gint64               timestamp)
{
        GAppInfo *app_info;

        app_info = g_app_info_get_default_for_type ("audio/x-vorbis+ogg", FALSE);
        if (app_info != NULL) {
                launch_app (manager, app_info, timestamp);
                g_object_unref (app_info);
        } else {
                g_warning ("Could not find default application for '%s' mime-type", "audio/x-vorbis+ogg");
        }
}

static void
gnome_session_logout_cb (GObject      *source_object,
                         GAsyncResult *res,
                         gpointer      user_data)
{
        GVariant *result;
        GError *error = NULL;

        result = g_dbus_proxy_call_finish (G_DBUS_PROXY (source_object),
                                           res,
                                           &error);
        if (result == NULL) {
                if (!g_error_matches (error, G_IO_ERROR, G_IO_ERROR_CANCELLED))
                        g_warning ("Failed to call Logout on session manager: %s",
                                   error->message);
                g_error_free (error);
        } else {
                g_variant_unref (result);
        }
}

static void
gnome_session_logout (GsdMediaKeysManager *manager,
                      guint                logout_mode)
{
	GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        GDBusProxy *proxy;

        proxy = G_DBUS_PROXY (gnome_settings_bus_get_session_proxy ());

        g_dbus_proxy_call (proxy,
                           "Logout",
                           g_variant_new ("(u)", logout_mode),
                           G_DBUS_CALL_FLAGS_NONE,
                           -1,
                           priv->bus_cancellable,
                           gnome_session_logout_cb,
                           NULL);

        g_object_unref (proxy);
}

static void
gnome_session_reboot_cb (GObject      *source_object,
                         GAsyncResult *res,
                         gpointer      user_data)
{
        GVariant *result;
        GError *error = NULL;

        result = g_dbus_proxy_call_finish (G_DBUS_PROXY (source_object),
                                           res,
                                           &error);
        if (result == NULL) {
                if (!g_error_matches (error, G_IO_ERROR, G_IO_ERROR_CANCELLED))
                        g_warning ("Failed to call Reboot on session manager: %s",
                                   error->message);
                g_error_free (error);
        } else {
                g_variant_unref (result);
        }
}

static void
gnome_session_reboot (GsdMediaKeysManager *manager)
{
	GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        GDBusProxy *proxy;

        proxy = G_DBUS_PROXY (gnome_settings_bus_get_session_proxy ());

        g_dbus_proxy_call (proxy,
                           "Reboot",
                           NULL,
                           G_DBUS_CALL_FLAGS_NONE,
                           -1,
                           priv->bus_cancellable,
                           gnome_session_reboot_cb,
                           NULL);

        g_object_unref (proxy);
}

static void
gnome_session_shutdown_cb (GObject *source_object,
                           GAsyncResult *res,
                           gpointer user_data)
{
        GVariant *result;
        GError *error = NULL;

        result = g_dbus_proxy_call_finish (G_DBUS_PROXY (source_object),
                                           res,
                                           &error);
        if (result == NULL) {
                if (!g_error_matches (error, G_IO_ERROR, G_IO_ERROR_CANCELLED))
                        g_warning ("Failed to call Shutdown on session manager: %s",
                                   error->message);
                g_error_free (error);
        } else {
                g_variant_unref (result);
        }
}

static void
do_terminal_action (GsdMediaKeysManager *manager)
{
        GSettings *settings;
        char *term;

        settings = g_settings_new ("org.gnome.desktop.default-applications.terminal");
        term = g_settings_get_string (settings, "exec");

        if (term)
        execute (manager, term, FALSE);

        g_free (term);
        g_object_unref (settings);
}

static void
gnome_session_shutdown (GsdMediaKeysManager *manager)
{
	GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        GDBusProxy *proxy;

        proxy = G_DBUS_PROXY (gnome_settings_bus_get_session_proxy ());

        g_dbus_proxy_call (proxy,
                           "Shutdown",
                           NULL,
                           G_DBUS_CALL_FLAGS_NONE,
                           -1,
                           priv->bus_cancellable,
                           gnome_session_shutdown_cb,
                           NULL);

        g_object_unref (proxy);
}

static void
do_eject_action_cb (GDrive              *drive,
                    GAsyncResult        *res,
                    GsdMediaKeysManager *manager)
{
        g_drive_eject_with_operation_finish (drive, res, NULL);
}

#define NO_SCORE 0
#define SCORE_CAN_EJECT 50
#define SCORE_HAS_MEDIA 100
static void
do_eject_action (GsdMediaKeysManager *manager)
{
        GList *drives, *l;
        GDrive *fav_drive;
        guint score;
        GVolumeMonitor *volume_monitor;

        volume_monitor = g_volume_monitor_get ();


        /* Find the best drive to eject */
        fav_drive = NULL;
        score = NO_SCORE;
        drives = g_volume_monitor_get_connected_drives (volume_monitor);
        for (l = drives; l != NULL; l = l->next) {
                GDrive *drive = l->data;

                if (g_drive_can_eject (drive) == FALSE)
                        continue;
                if (g_drive_is_media_removable (drive) == FALSE)
                        continue;
                if (score < SCORE_CAN_EJECT) {
                        fav_drive = drive;
                        score = SCORE_CAN_EJECT;
                }
                if (g_drive_has_media (drive) == FALSE)
                        continue;
                if (score < SCORE_HAS_MEDIA) {
                        fav_drive = drive;
                        score = SCORE_HAS_MEDIA;
                        break;
                }
        }

        /* Show OSD */
        show_osd (manager, "media-eject-symbolic", NULL, -1, NULL);

        /* Clean up the drive selection and exit if no suitable
         * drives are found */
        if (fav_drive != NULL)
                fav_drive = g_object_ref (fav_drive);

        g_list_foreach (drives, (GFunc) g_object_unref, NULL);
        if (fav_drive == NULL)
                return;

        /* Eject! */
        g_drive_eject_with_operation (fav_drive, G_MOUNT_UNMOUNT_FORCE,
                                      NULL, NULL,
                                      (GAsyncReadyCallback) do_eject_action_cb,
                                      manager);
        g_object_unref (fav_drive);
        g_object_unref (volume_monitor);
}

static void
do_home_key_action (GsdMediaKeysManager *manager,
		    gint64               timestamp)
{
	GFile *file;
	GError *error = NULL;
	char *uri;

	file = g_file_new_for_path (g_get_home_dir ());
	uri = g_file_get_uri (file);
	g_object_unref (file);

	if (gtk_show_uri_on_window (NULL, uri, timestamp, &error) == FALSE) {
		g_warning ("Failed to launch '%s': %s", uri, error->message);
		g_error_free (error);
	}
	g_free (uri);
}

static void
do_search_action (GsdMediaKeysManager *manager,
		  gint64               timestamp)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);

        if (priv->shell_proxy == NULL)
                return;

        gsd_shell_call_focus_search (priv->shell_proxy,
                                     NULL, NULL, NULL);
}

static void
do_execute_desktop_or_desktop (GsdMediaKeysManager *manager,
			       const char          *desktop,
			       const char          *alt_desktop,
			       gint64               timestamp)
{
        GDesktopAppInfo *app_info;

        app_info = g_desktop_app_info_new (desktop);
        if (app_info == NULL && alt_desktop != NULL)
                app_info = g_desktop_app_info_new (alt_desktop);

        if (app_info != NULL) {
                launch_app (manager, G_APP_INFO (app_info), timestamp);
                g_object_unref (app_info);
                return;
        }

        g_warning ("Could not find application '%s' or '%s'", desktop, alt_desktop);
}

static void
do_touchpad_osd_action (GsdMediaKeysManager *manager, gboolean state)
{
        show_osd (manager, state ? "input-touchpad-symbolic"
                                 : "touchpad-disabled-symbolic", NULL, -1, NULL);
}

static void
do_touchpad_action (GsdMediaKeysManager *manager)
{
        GSettings *settings;
        gboolean state;

        settings = g_settings_new (SETTINGS_TOUCHPAD_DIR);
        state = (g_settings_get_enum (settings, TOUCHPAD_ENABLED_KEY) ==
                 G_DESKTOP_DEVICE_SEND_EVENTS_ENABLED);

        do_touchpad_osd_action (manager, !state);

        g_settings_set_enum (settings, TOUCHPAD_ENABLED_KEY,
                             !state ?
                             G_DESKTOP_DEVICE_SEND_EVENTS_ENABLED :
                             G_DESKTOP_DEVICE_SEND_EVENTS_DISABLED);
        g_object_unref (settings);
}

static void
on_screen_locked (GsdScreenSaver      *screen_saver,
                  GAsyncResult        *result,
                  GsdMediaKeysManager *manager)
{
        gboolean is_locked;
        GError *error = NULL;

        is_locked = gsd_screen_saver_call_lock_finish (screen_saver, result, &error);

        if (!is_locked) {
                g_warning ("Couldn't lock screen: %s", error->message);
                g_error_free (error);
                return;
        }
}

static void
do_lock_screensaver (GsdMediaKeysManager *manager)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);

        if (priv->screen_saver_proxy == NULL)
                priv->screen_saver_proxy = gnome_settings_bus_get_screen_saver_proxy ();

        gsd_screen_saver_call_lock (priv->screen_saver_proxy,
                                    priv->bus_cancellable,
                                    (GAsyncReadyCallback) on_screen_locked,
                                    manager);
}

static void
sound_theme_changed (GsdMediaKeysManager *manager)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        char *theme_name;

        g_object_get (G_OBJECT (priv->gtksettings), "gtk-sound-theme-name", &theme_name, NULL);
        if (theme_name)
                ca_context_change_props (priv->ca, CA_PROP_CANBERRA_XDG_THEME_NAME, theme_name, NULL);
        g_free (theme_name);
}

static void
allow_volume_above_100_percent_changed_cb (GSettings           *settings,
                                           const char          *settings_key,
                                           GsdMediaKeysManager *manager)
{
	GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        gboolean allow_volume_above_100_percent;

        g_assert (g_str_equal (settings_key, ALLOW_VOLUME_ABOVE_100_PERCENT_KEY));

        allow_volume_above_100_percent = g_settings_get_boolean (settings, settings_key);
        priv->max_volume = allow_volume_above_100_percent ? PA_VOLUME_UI_MAX : PA_VOLUME_NORM;
}

static void
play_volume_changed_audio (GsdMediaKeysManager *manager,
                           GvcMixerStream      *stream)
{
	GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);

	if (priv->ca == NULL) {
                ca_context_create (&priv->ca);
                ca_context_set_driver (priv->ca, "pulse");
                ca_context_change_props (priv->ca, 0,
                                         CA_PROP_APPLICATION_ID,
                                         "org.gnome.VolumeControl",
                                         NULL);

                priv->gtksettings =
                        gtk_settings_get_for_screen (gdk_screen_get_default ());

                g_signal_connect_swapped (priv->gtksettings,
                                          "notify::gtk-sound-theme-name",
                                          G_CALLBACK (sound_theme_changed),
                                          manager);
                sound_theme_changed (manager);
        }

        ca_context_change_device (priv->ca,
                                  gvc_mixer_stream_get_name (stream));
        ca_context_play (priv->ca, 1,
                         CA_PROP_EVENT_ID, "audio-volume-change",
                         CA_PROP_EVENT_DESCRIPTION, "volume changed through key press",
                         CA_PROP_CANBERRA_CACHE_CONTROL, "permanent",
                         NULL);
}

static void
show_volume_osd (GsdMediaKeysManager *manager,
                 GvcMixerStream      *stream,
                 guint                vol,
                 gboolean             muted,
                 gboolean             sound_changed,
                 gboolean             quiet)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        GvcMixerUIDevice *device;
        const GvcMixerStreamPort *port;
        const char *icon;
        gboolean playing = FALSE;
        double new_vol;
        double max_volume;

        max_volume = (double) priv->max_volume / PA_VOLUME_NORM;
        if (!muted) {
                new_vol = (double) vol / PA_VOLUME_NORM;
                new_vol = CLAMP (new_vol, 0, max_volume);
        } else {
                new_vol = 0.0;
        }
        icon = get_icon_name_for_volume (!GVC_IS_MIXER_SINK (stream), muted, new_vol);
        port = gvc_mixer_stream_get_port (stream);
        if (g_strcmp0 (gvc_mixer_stream_get_form_factor (stream), "internal") != 0 ||
            (port != NULL &&
             g_strcmp0 (port->port, "[OUT] Speaker") != 0 &&
             g_strcmp0 (port->port, "[OUT] Handset") != 0 &&
             g_strcmp0 (port->port, "analog-output-speaker") != 0 &&
             g_strcmp0 (port->port, "analog-output") != 0)) {
                device = gvc_mixer_control_lookup_device_from_stream (priv->volume, stream);
                show_osd_with_max_level (manager, icon,
                                         gvc_mixer_ui_device_get_description (device),
                                         new_vol, max_volume, NULL);
        } else {
                show_osd_with_max_level (manager, icon, NULL, new_vol, max_volume, NULL);
        }

        if (priv->ca)
                ca_context_playing (priv->ca, 1, &playing);
        playing = !playing && gvc_mixer_stream_get_state (stream) == GVC_STREAM_STATE_RUNNING;

        if (quiet == FALSE && sound_changed != FALSE && muted == FALSE && playing == FALSE)
                play_volume_changed_audio (manager, stream);
}

#if HAVE_GUDEV
/* PulseAudio gives us /devices/... paths, when udev
 * expects /sys/devices/... paths. */
static GUdevDevice *
get_udev_device_for_sysfs_path (GsdMediaKeysManager *manager,
				const char *sysfs_path)
{
	GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
	char *path;
	GUdevDevice *dev;

	path = g_strdup_printf ("/sys%s", sysfs_path);
	dev = g_udev_client_query_by_sysfs_path (priv->udev_client, path);
	g_free (path);

	return dev;
}

static GvcMixerStream *
get_stream_for_device_node (GsdMediaKeysManager *manager,
                            gboolean             is_output,
                            const gchar         *devnode)
{
	GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
	gpointer id_ptr;
	GvcMixerStream *res;
	GUdevDevice *dev, *parent;
	GSList *streams, *l;

	id_ptr = g_hash_table_lookup (priv->streams, devnode);
	if (id_ptr != NULL) {
		if (GPOINTER_TO_UINT (id_ptr) == (guint) -1)
			return NULL;
		else
			return gvc_mixer_control_lookup_stream_id (priv->volume, GPOINTER_TO_UINT (id_ptr));
	}

	dev = g_udev_client_query_by_device_file (priv->udev_client, devnode);
	if (dev == NULL) {
		g_debug ("Could not find udev device for device path '%s'", devnode);
		return NULL;
	}

	if (g_strcmp0 (g_udev_device_get_property (dev, "ID_BUS"), "usb") != 0) {
		g_debug ("Not handling XInput device %s, not USB", devnode);
		g_hash_table_insert (priv->streams,
				     g_strdup (devnode),
				     GUINT_TO_POINTER ((guint) -1));
		g_object_unref (dev);
		return NULL;
	}

	parent = g_udev_device_get_parent_with_subsystem (dev, "usb", "usb_device");
	if (parent == NULL) {
		g_warning ("No USB device parent for XInput device %s even though it's USB", devnode);
		g_object_unref (dev);
		return NULL;
	}

	res = NULL;
	if (is_output)
		streams = gvc_mixer_control_get_sinks (priv->volume);
	else
		streams = gvc_mixer_control_get_sources (priv->volume);
	for (l = streams; l; l = l->next) {
		GvcMixerStream *stream = l->data;
		const char *sysfs_path;
		GUdevDevice *stream_dev, *stream_parent;

		sysfs_path = gvc_mixer_stream_get_sysfs_path (stream);
		stream_dev = get_udev_device_for_sysfs_path (manager, sysfs_path);
		if (stream_dev == NULL)
			continue;
		stream_parent = g_udev_device_get_parent_with_subsystem (stream_dev, "usb", "usb_device");
		g_object_unref (stream_dev);
		if (stream_parent == NULL)
			continue;

		if (g_strcmp0 (g_udev_device_get_sysfs_path (stream_parent),
			       g_udev_device_get_sysfs_path (parent)) == 0) {
			res = stream;
		}
		g_object_unref (stream_parent);
		if (res != NULL)
			break;
	}

	g_slist_free (streams);

	if (res)
		g_hash_table_insert (priv->streams,
				     g_strdup (devnode),
				     GUINT_TO_POINTER (gvc_mixer_stream_get_id (res)));
	else
		g_hash_table_insert (priv->streams,
				     g_strdup (devnode),
				     GUINT_TO_POINTER ((guint) -1));

	return res;
}
#endif /* HAVE_GUDEV */

typedef enum {
	SOUND_ACTION_FLAG_IS_OUTPUT  = 1 << 0,
	SOUND_ACTION_FLAG_IS_QUIET   = 1 << 1,
	SOUND_ACTION_FLAG_IS_PRECISE = 1 << 2,
} SoundActionFlags;

static void
do_sound_action (GsdMediaKeysManager *manager,
                 const gchar         *device_node,
                 int                  type,
                 SoundActionFlags     flags)
{
	GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        GvcMixerStream *stream = NULL;
        gboolean old_muted, new_muted;
        guint old_vol, new_vol, norm_vol_step, vol_step;
        gboolean sound_changed;

        /* Find the stream that corresponds to the device, if any */
        stream = NULL;
#if HAVE_GUDEV
        if (device_node) {
                stream = get_stream_for_device_node (manager,
                                                     flags & SOUND_ACTION_FLAG_IS_OUTPUT,
                                                     device_node);
        }
#endif /* HAVE_GUDEV */

        if (stream == NULL) {
                if (flags & SOUND_ACTION_FLAG_IS_OUTPUT)
                        stream = priv->sink;
                else
                        stream = priv->source;
        }

        if (stream == NULL)
                return;

        if (flags & SOUND_ACTION_FLAG_IS_PRECISE) {
                norm_vol_step = PA_VOLUME_NORM * VOLUME_STEP_PRECISE / 100;
        }
        else {
                vol_step = g_settings_get_int (priv->settings, VOLUME_STEP);
                norm_vol_step = PA_VOLUME_NORM * vol_step / 100;
        }
        /* FIXME: this is racy */
        new_vol = old_vol = gvc_mixer_stream_get_volume (stream);
        new_muted = old_muted = gvc_mixer_stream_get_is_muted (stream);
        sound_changed = FALSE;

        switch (type) {
        case MUTE_KEY:
                new_muted = !old_muted;
                break;
        case VOLUME_DOWN_KEY:
                if (old_vol <= norm_vol_step) {
                        new_vol = 0;
                        new_muted = TRUE;
                } else {
                        new_vol = old_vol - norm_vol_step;
                }
                break;
        case VOLUME_UP_KEY:
                new_muted = FALSE;
                /* When coming out of mute only increase the volume if it was 0 */
                if (!old_muted || old_vol == 0)
                        new_vol = MIN (old_vol + norm_vol_step, priv->max_volume);
                break;
        }

        if (old_muted != new_muted) {
                gvc_mixer_stream_change_is_muted (stream, new_muted);
                sound_changed = TRUE;
        }

        if (old_vol != new_vol) {
                if (gvc_mixer_stream_set_volume (stream, new_vol) != FALSE) {
                        gvc_mixer_stream_push_volume (stream);
                        sound_changed = TRUE;
                }
        }

        show_volume_osd (manager, stream, new_vol, new_muted, sound_changed,
                         flags & SOUND_ACTION_FLAG_IS_QUIET);
}

static void
update_default_sink (GsdMediaKeysManager *manager,
                     gboolean             warn)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        GvcMixerStream *stream;

        stream = gvc_mixer_control_get_default_sink (priv->volume);
        if (stream == priv->sink)
                return;

        g_clear_object (&priv->sink);

        if (stream != NULL) {
                priv->sink = g_object_ref (stream);
        } else {
                if (warn)
                        g_warning ("Unable to get default sink");
                else
                        g_debug ("Unable to get default sink");
        }
}

static void
update_default_source (GsdMediaKeysManager *manager,
                       gboolean             warn)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        GvcMixerStream *stream;

        stream = gvc_mixer_control_get_default_source (priv->volume);
        if (stream == priv->source)
                return;

        g_clear_object (&priv->source);

        if (stream != NULL) {
                priv->source = g_object_ref (stream);
        } else {
                if (warn)
                        g_warning ("Unable to get default source");
                else
                        g_debug ("Unable to get default source");
        }
}

static void
on_control_state_changed (GvcMixerControl     *control,
                          GvcMixerControlState new_state,
                          GsdMediaKeysManager *manager)
{
        update_default_sink (manager, new_state == GVC_STATE_READY);
        update_default_source (manager, new_state == GVC_STATE_READY);
}

static void
on_control_default_sink_changed (GvcMixerControl     *control,
                                 guint                id,
                                 GsdMediaKeysManager *manager)
{
        update_default_sink (manager, TRUE);
}

static void
on_control_default_source_changed (GvcMixerControl     *control,
                                   guint                id,
                                   GsdMediaKeysManager *manager)
{
        update_default_source (manager, TRUE);
}

#if HAVE_GUDEV
static gboolean
remove_stream (gpointer key,
	       gpointer value,
	       gpointer id)
{
	if (GPOINTER_TO_UINT (value) == GPOINTER_TO_UINT (id))
		return TRUE;
	return FALSE;
}
#endif /* HAVE_GUDEV */

static void
on_control_stream_removed (GvcMixerControl     *control,
                           guint                id,
                           GsdMediaKeysManager *manager)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);

        if (priv->sink != NULL) {
		if (gvc_mixer_stream_get_id (priv->sink) == id)
			g_clear_object (&priv->sink);
        }
        if (priv->source != NULL) {
		if (gvc_mixer_stream_get_id (priv->source) == id)
			g_clear_object (&priv->source);
        }

#if HAVE_GUDEV
	g_hash_table_foreach_remove (priv->streams, (GHRFunc) remove_stream, GUINT_TO_POINTER (id));
#endif
}

static gboolean
do_multimedia_player_action (GsdMediaKeysManager *manager,
                             const char          *key)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);

        g_return_val_if_fail (key != NULL, FALSE);

        g_debug ("Media key '%s' pressed", key);

        if (mpris_controller_get_has_active_player (priv->mpris_controller)) {
                if (g_str_equal (key, "Rewind")) {
                        if (mpris_controller_seek (priv->mpris_controller, REWIND_USEC))
                                return TRUE;
                } else if (g_str_equal (key, "FastForward")) {
                        if (mpris_controller_seek (priv->mpris_controller, FASTFORWARD_USEC))
                                return TRUE;
                } else if (g_str_equal (key, "Repeat")) {
                        if (mpris_controller_toggle (priv->mpris_controller, "LoopStatus"))
                                return TRUE;
                } else if (g_str_equal (key, "Shuffle")) {
                        if (mpris_controller_toggle (priv->mpris_controller, "Shuffle"))
                                return TRUE;
                } else if (mpris_controller_key (priv->mpris_controller, key)) {
                        return TRUE;
                }
        }

	/* Popup a dialog with an (/) icon */
	show_osd (manager, "action-unavailable-symbolic", NULL, -1, NULL);
	return TRUE;
}

static void
sensor_properties_changed (GDBusProxy *proxy,
                           GVariant   *changed_properties,
                           GStrv       invalidated_properties,
                           gpointer    user_data)
{
        GsdMediaKeysManager *manager = user_data;
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        GVariant *v;
        GVariantDict dict;

        if (priv->iio_sensor_proxy == NULL)
                return;

        if (changed_properties)
                g_variant_dict_init (&dict, changed_properties);

        if (changed_properties == NULL ||
            g_variant_dict_contains (&dict, "HasAccelerometer")) {
                v = g_dbus_proxy_get_cached_property (priv->iio_sensor_proxy,
                                                      "HasAccelerometer");
                if (v == NULL) {
                        g_debug ("Couldn't fetch HasAccelerometer property");
                        return;
                }
                priv->has_accel = g_variant_get_boolean (v);
                g_variant_unref (v);
        }
}

static void
iio_sensor_appeared_cb (GDBusConnection *connection,
                        const gchar     *name,
                        const gchar     *name_owner,
                        gpointer         user_data)
{
        GsdMediaKeysManager *manager = user_data;
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        GError *error = NULL;

        priv->iio_sensor_proxy = g_dbus_proxy_new_sync (connection,
                                                        G_DBUS_PROXY_FLAGS_NONE,
                                                        NULL,
                                                        "net.hadess.SensorProxy",
                                                        "/net/hadess/SensorProxy",
                                                        "net.hadess.SensorProxy",
                                                        NULL,
                                                        &error);

        if (priv->iio_sensor_proxy == NULL) {
                g_warning ("Failed to access net.hadess.SensorProxy after it appeared");
                return;
        }
        g_signal_connect (G_OBJECT (priv->iio_sensor_proxy),
                          "g-properties-changed",
                          G_CALLBACK (sensor_properties_changed), manager);

        sensor_properties_changed (priv->iio_sensor_proxy,
                                   NULL, NULL, manager);
}

static void
iio_sensor_disappeared_cb (GDBusConnection *connection,
                           const gchar     *name,
                           gpointer         user_data)
{
        GsdMediaKeysManager *manager = user_data;
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);

        g_clear_object (&priv->iio_sensor_proxy);
        priv->has_accel = FALSE;
}

static void
do_video_rotate_lock_action (GsdMediaKeysManager *manager,
                             gint64               timestamp)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        GSettings *settings;
        gboolean locked;

        if (!priv->has_accel) {
                g_debug ("Ignoring attempt to set orientation lock: no accelerometer");
                return;
        }

        settings = g_settings_new ("org.gnome.settings-daemon.peripherals.touchscreen");
        locked = !g_settings_get_boolean (settings, "orientation-lock");
        g_settings_set_boolean (settings, "orientation-lock", locked);
        g_object_unref (settings);

        show_osd (manager, locked ? "rotation-locked-symbolic"
                                  : "rotation-allowed-symbolic", NULL, -1, NULL);
}

static void
do_toggle_accessibility_key (const char *key)
{
        GSettings *settings;
        gboolean state;

        settings = g_settings_new ("org.gnome.desktop.a11y.applications");
        state = g_settings_get_boolean (settings, key);
        g_settings_set_boolean (settings, key, !state);
        g_object_unref (settings);
}

static void
do_magnifier_action (GsdMediaKeysManager *manager)
{
        do_toggle_accessibility_key ("screen-magnifier-enabled");
}

static void
do_screenreader_action (GsdMediaKeysManager *manager)
{
        do_toggle_accessibility_key ("screen-reader-enabled");
}

static void
do_on_screen_keyboard_action (GsdMediaKeysManager *manager)
{
        do_toggle_accessibility_key ("screen-keyboard-enabled");
}

static void
do_text_size_action (GsdMediaKeysManager *manager,
		     MediaKeyType         type)
{
	GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
	gdouble factor, best, distance;
	guint i;

	/* Same values used in the Seeing tab of the Universal Access panel */
	static gdouble factors[] = {
		0.75,
		1.0,
		1.25,
		1.5
	};

	/* Figure out the current DPI scaling factor */
	factor = g_settings_get_double (priv->interface_settings, "text-scaling-factor");
	factor += (type == INCREASE_TEXT_KEY ? 0.25 : -0.25);

	/* Try to find a matching value */
	distance = 1e6;
	best = 1.0;
	for (i = 0; i < G_N_ELEMENTS(factors); i++) {
		gdouble d;
		d = fabs (factor - factors[i]);
		if (d < distance) {
			best = factors[i];
			distance = d;
		}
	}

	if (best == 1.0)
		g_settings_reset (priv->interface_settings, "text-scaling-factor");
	else
		g_settings_set_double (priv->interface_settings, "text-scaling-factor", best);
}

static void
do_magnifier_zoom_action (GsdMediaKeysManager *manager,
			  MediaKeyType         type)
{
	GSettings *settings;
	gdouble offset, value;

	if (type == MAGNIFIER_ZOOM_IN_KEY)
		offset = 1.0;
	else
		offset = -1.0;

	settings = g_settings_new ("org.gnome.desktop.a11y.magnifier");
	value = g_settings_get_double (settings, "mag-factor");
	value += offset;
	value = roundl (value);
	g_settings_set_double (settings, "mag-factor", value);
	g_object_unref (settings);
}

static void
do_toggle_contrast_action (GsdMediaKeysManager *manager)
{
	GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
	gboolean high_contrast;
	char *theme;

	/* Are we using HighContrast now? */
	theme = g_settings_get_string (priv->interface_settings, "gtk-theme");
	high_contrast = g_str_equal (theme, HIGH_CONTRAST);
	g_free (theme);

	if (high_contrast != FALSE) {
		if (priv->gtk_theme == NULL)
			g_settings_reset (priv->interface_settings, "gtk-theme");
		else
			g_settings_set (priv->interface_settings, "gtk-theme", priv->gtk_theme);
		g_settings_set (priv->interface_settings, "icon-theme", priv->icon_theme);
	} else {
		g_settings_set (priv->interface_settings, "gtk-theme", HIGH_CONTRAST);
		g_settings_set (priv->interface_settings, "icon-theme", HIGH_CONTRAST);
	}
}

static void
power_action (GsdMediaKeysManager *manager,
              const char          *action,
              gboolean             allow_interaction)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);

        g_dbus_proxy_call (priv->logind_proxy,
                           action,
                           g_variant_new ("(b)", allow_interaction),
                           G_DBUS_CALL_FLAGS_NONE,
                           G_MAXINT,
                           priv->bus_cancellable,
                           NULL, NULL);
}

static void
do_config_power_action (GsdMediaKeysManager *manager,
                        GsdPowerActionType   action_type,
                        gboolean             in_lock_screen)
{
        switch (action_type) {
        case GSD_POWER_ACTION_SUSPEND:
                power_action (manager, "Suspend", !in_lock_screen);
                break;
        case GSD_POWER_ACTION_INTERACTIVE:
                if (!in_lock_screen)
                        gnome_session_shutdown (manager);
                break;
        case GSD_POWER_ACTION_SHUTDOWN:
                power_action (manager, "PowerOff", !in_lock_screen);
                break;
        case GSD_POWER_ACTION_HIBERNATE:
                power_action (manager, "Hibernate", !in_lock_screen);
                break;
        case GSD_POWER_ACTION_BLANK:
        case GSD_POWER_ACTION_LOGOUT:
        case GSD_POWER_ACTION_NOTHING:
                /* these actions cannot be handled by media-keys and
                 * are not used in this context */
                break;
        }
}

static gboolean
supports_power_action (GsdMediaKeysManager *manager,
                       GsdPowerActionType   action_type)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        const char *method_name = NULL;
        g_autoptr(GVariant) variant = NULL;
        const char *reply;
        gboolean result = FALSE;

        switch (action_type) {
        case GSD_POWER_ACTION_SUSPEND:
                method_name = "CanSuspend";
                break;
        case GSD_POWER_ACTION_SHUTDOWN:
                method_name = "CanPowerOff";
                break;
        case GSD_POWER_ACTION_HIBERNATE:
                method_name = "CanHibernate";
                break;
        case GSD_POWER_ACTION_INTERACTIVE:
        case GSD_POWER_ACTION_BLANK:
        case GSD_POWER_ACTION_LOGOUT:
        case GSD_POWER_ACTION_NOTHING:
                break;
        }

        if (method_name == NULL)
                return FALSE;

        variant = g_dbus_proxy_call_sync (priv->logind_proxy,
                                          method_name,
                                          NULL,
                                          G_DBUS_CALL_FLAGS_NONE,
                                          -1,
                                          priv->bus_cancellable,
                                          NULL);

        if (variant == NULL)
                return FALSE;

        g_variant_get (variant, "(&s)", &reply);
        if (g_strcmp0 (reply, "yes") == 0)
                result = TRUE;

        return result;
}

static void
do_config_power_button_action (GsdMediaKeysManager *manager,
                               gboolean             in_lock_screen)
{
	GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        GsdPowerButtonActionType action_type;
        GsdPowerActionType action;

        if (priv->power_button_disabled)
                return;

        action_type = g_settings_get_enum (priv->power_settings, "power-button-action");
        /* Always power off VMs, except when power-button-action is "nothing" */
        if (g_strcmp0 (priv->chassis_type, "vm") == 0) {
                g_warning_once ("Virtual machines only honor the 'nothing' power-button-action, and will shutdown otherwise");

                if (action_type != GSD_POWER_BUTTON_ACTION_NOTHING)
                        power_action (manager, "PowerOff", FALSE);

                return;
        }

        switch (action_type) {
        case GSD_POWER_BUTTON_ACTION_SUSPEND:
                action = GSD_POWER_ACTION_SUSPEND;
                break;
        case GSD_POWER_BUTTON_ACTION_HIBERNATE:
                action = GSD_POWER_ACTION_HIBERNATE;
                break;
        case GSD_POWER_BUTTON_ACTION_INTERACTIVE:
                action = GSD_POWER_ACTION_INTERACTIVE;
                break;
        default:
                g_warn_if_reached ();
                G_GNUC_FALLTHROUGH;
        case GSD_POWER_BUTTON_ACTION_NOTHING:
                /* do nothing */
                return;
        }

        if (action != GSD_POWER_ACTION_INTERACTIVE && !supports_power_action (manager, action))
                action = GSD_POWER_ACTION_INTERACTIVE;

        do_config_power_action (manager, action, in_lock_screen);
}

static void
update_brightness_cb (GObject             *source_object,
                      GAsyncResult        *res,
                      gpointer             user_data)
{
        GError *error = NULL;
        int percentage;
        GVariant *variant;
        GsdMediaKeysManager *manager = GSD_MEDIA_KEYS_MANAGER (user_data);
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        const char *icon, *debug;
        char *connector = NULL;

        /* update the dialog with the new value */
        if (G_DBUS_PROXY (source_object) == priv->power_keyboard_proxy) {
                debug = "keyboard";
        } else {
                debug = "screen";
        }

        variant = g_dbus_proxy_call_finish (G_DBUS_PROXY (source_object),
                                        res, &error);
        if (variant == NULL) {
                if (!g_error_matches (error, G_IO_ERROR, G_IO_ERROR_CANCELLED))
                        g_warning ("Failed to set new %s percentage: %s",
                                   debug, error->message);
                g_error_free (error);
                return;
        }

        /* update the dialog with the new value */
        if (G_DBUS_PROXY (source_object) == priv->power_keyboard_proxy) {
                icon = "keyboard-brightness-symbolic";
                g_variant_get (variant, "(i)", &percentage);
        } else {
                icon = "display-brightness-symbolic";
                g_variant_get (variant, "(i&s)", &percentage, &connector);
        }

        show_osd (manager, icon, NULL, (double) percentage / 100.0, connector);
        g_variant_unref (variant);
}

static void
do_brightness_action (GsdMediaKeysManager *manager,
                      MediaKeyType type)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        const char *cmd;
        GDBusProxy *proxy;

        switch (type) {
        case KEYBOARD_BRIGHTNESS_UP_KEY:
        case KEYBOARD_BRIGHTNESS_DOWN_KEY:
        case KEYBOARD_BRIGHTNESS_TOGGLE_KEY:
                proxy = priv->power_keyboard_proxy;
                break;
        case SCREEN_BRIGHTNESS_UP_KEY:
        case SCREEN_BRIGHTNESS_DOWN_KEY:
        case SCREEN_BRIGHTNESS_CYCLE_KEY:
                proxy = priv->power_screen_proxy;
                break;
        default:
                g_assert_not_reached ();
        }

        if (priv->connection == NULL ||
            proxy == NULL) {
                g_warning ("No existing D-Bus connection trying to handle power keys");
                return;
        }

        switch (type) {
        case KEYBOARD_BRIGHTNESS_UP_KEY:
        case SCREEN_BRIGHTNESS_UP_KEY:
                cmd = "StepUp";
                break;
        case KEYBOARD_BRIGHTNESS_DOWN_KEY:
        case SCREEN_BRIGHTNESS_DOWN_KEY:
                cmd = "StepDown";
                break;
        case KEYBOARD_BRIGHTNESS_TOGGLE_KEY:
                cmd = "Toggle";
                break;
        case SCREEN_BRIGHTNESS_CYCLE_KEY:
                cmd = "Cycle";
                break;
        default:
                g_assert_not_reached ();
        }

        /* call into the power plugin */
        g_dbus_proxy_call (proxy,
                           cmd,
                           NULL,
                           G_DBUS_CALL_FLAGS_NONE,
                           -1,
                           NULL,
                           update_brightness_cb,
                           manager);
}

static void
do_battery_action (GsdMediaKeysManager *manager)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        gdouble percentage;
        UpDeviceKind kind;
        gchar *icon_name;

        g_return_if_fail (priv->composite_device != NULL);

        g_object_get (priv->composite_device,
                      "kind", &kind,
                      "icon-name", &icon_name,
                      "percentage", &percentage,
                      NULL);

        if (kind == UP_DEVICE_KIND_UPS || kind == UP_DEVICE_KIND_BATTERY) {
                g_debug ("showing battery level OSD");
                show_osd (manager, icon_name, NULL, (double) percentage / 100.0, NULL);
        }

        g_free (icon_name);
}

static gboolean
get_rfkill_property (GsdMediaKeysManager *manager,
                     const char          *property)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        GVariant *v;
        gboolean ret;

        v = g_dbus_proxy_get_cached_property (priv->rfkill_proxy, property);
        if (!v)
                return FALSE;
        ret = g_variant_get_boolean (v);
        g_variant_unref (v);

        return ret;
}

typedef struct {
        GsdMediaKeysManager *manager;
        char *property;
        gboolean bluetooth;
        gboolean target_state;
} RfkillData;

static void
set_rfkill_complete (GObject      *object,
                     GAsyncResult *result,
                     gpointer      user_data)
{
        GError *error = NULL;
        GVariant *variant;
        RfkillData *data = user_data;

        variant = g_dbus_proxy_call_finish (G_DBUS_PROXY (object), result, &error);

        if (variant == NULL) {
                if (!g_error_matches (error, G_IO_ERROR, G_IO_ERROR_CANCELLED))
                        g_warning ("Failed to set '%s' property: %s", data->property, error->message);
                g_error_free (error);
                goto out;
        }
        g_variant_unref (variant);

        g_debug ("Finished changing rfkill, property %s is now %s",
                 data->property, data->target_state ? "true" : "false");

        if (data->bluetooth) {
                if (data->target_state)
                        show_osd (data->manager, "bluetooth-disabled-symbolic",
                                  _("Bluetooth Disabled"), -1, NULL);
                else
                        show_osd (data->manager, "bluetooth-active-symbolic",
                                  _("Bluetooth Enabled"), -1, NULL);
        } else {
                if (data->target_state)
                        show_osd (data->manager, "airplane-mode-symbolic",
                                  _("Airplane Mode Enabled"), -1, NULL);
                else
                        show_osd (data->manager, "airplane-mode-disabled-symbolic",
                                  _("Airplane Mode Disabled"), -1, NULL);
        }

out:
        g_free (data->property);
        g_free (data);
}

static void
do_rfkill_action (GsdMediaKeysManager *manager,
                  gboolean             bluetooth)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        const char *has_mode, *hw_mode, *mode;
        gboolean new_state;
        guint64 current_time;
        RfkillData *data;

        has_mode = bluetooth ? "BluetoothHasAirplaneMode" : "HasAirplaneMode";
        hw_mode = bluetooth ? "BluetoothHardwareAirplaneMode" : "HardwareAirplaneMode";
        mode = bluetooth ? "BluetoothAirplaneMode" : "AirplaneMode";

        if (priv->rfkill_proxy == NULL)
                return;

        /* Some hardwares can generate multiple rfkill events from different
         * drivers, on a single hotkey press. Only process the first event and
         * debounce the others */
        current_time = g_get_monotonic_time ();
        if (current_time - priv->rfkill_last_time < G_USEC_PER_SEC)
                return;

        priv->rfkill_last_time = current_time;

        if (get_rfkill_property (manager, has_mode) == FALSE)
                return;

        if (get_rfkill_property (manager, hw_mode)) {
                show_osd (manager, "airplane-mode-symbolic",
                          _("Hardware Airplane Mode"), -1, NULL);
                return;
        }

        new_state = !get_rfkill_property (manager, mode);
        data = g_new0 (RfkillData, 1);
        data->manager = manager;
        data->property = g_strdup (mode);
        data->bluetooth = bluetooth;
        data->target_state = new_state;
        g_dbus_proxy_call (priv->rfkill_proxy,
                           "org.freedesktop.DBus.Properties.Set",
                           g_variant_new ("(ssv)",
                                          "org.gnome.SettingsDaemon.Rfkill",
                                          data->property,
                                          g_variant_new_boolean (new_state)),
                           G_DBUS_CALL_FLAGS_NONE, -1,
                           priv->rfkill_cancellable,
                           set_rfkill_complete, data);

        g_debug ("Setting rfkill property %s to %s",
                 data->property, new_state ? "true" : "false");
}

static void
do_custom_action (GsdMediaKeysManager *manager,
                  const gchar         *device_node,
                  MediaKey            *key,
                  gint64               timestamp)
{
        g_debug ("Launching custom action for key (on device node %s)", device_node);

	execute (manager, key->custom_command, timestamp);
}

static gboolean
do_action (GsdMediaKeysManager *manager,
           const gchar         *device_node,
           guint                mode,
           MediaKeyType         type,
           gint64               timestamp)
{
        g_debug ("Launching action for key type '%d' (on device node %s)", type, device_node);

        gboolean power_action_noninteractive = (POWER_KEYS_MODE_NO_DIALOG & mode);

        switch (type) {
        case TOUCHPAD_KEY:
                do_touchpad_action (manager);
                break;
        case TOUCHPAD_ON_KEY:
                do_touchpad_osd_action (manager, TRUE);
                break;
        case TOUCHPAD_OFF_KEY:
                do_touchpad_osd_action (manager, FALSE);
                break;
        case MUTE_KEY:
        case VOLUME_DOWN_KEY:
        case VOLUME_UP_KEY:
                do_sound_action (manager, device_node, type, SOUND_ACTION_FLAG_IS_OUTPUT);
                break;
        case MIC_MUTE_KEY:
                do_sound_action (manager, device_node, MUTE_KEY, SOUND_ACTION_FLAG_IS_QUIET);
                break;
        case MUTE_QUIET_KEY:
                do_sound_action (manager, device_node, MUTE_KEY,
                                 SOUND_ACTION_FLAG_IS_OUTPUT | SOUND_ACTION_FLAG_IS_QUIET);
                break;
        case VOLUME_DOWN_QUIET_KEY:
                do_sound_action (manager, device_node, VOLUME_DOWN_KEY,
                                 SOUND_ACTION_FLAG_IS_OUTPUT | SOUND_ACTION_FLAG_IS_QUIET);
                break;
        case VOLUME_UP_QUIET_KEY:
                do_sound_action (manager, device_node, VOLUME_UP_KEY,
                                 SOUND_ACTION_FLAG_IS_OUTPUT | SOUND_ACTION_FLAG_IS_QUIET);
                break;
        case VOLUME_DOWN_PRECISE_KEY:
                do_sound_action (manager, device_node, VOLUME_DOWN_KEY,
                                 SOUND_ACTION_FLAG_IS_OUTPUT | SOUND_ACTION_FLAG_IS_PRECISE);
                break;
        case VOLUME_UP_PRECISE_KEY:
                do_sound_action (manager, device_node, VOLUME_UP_KEY,
                                 SOUND_ACTION_FLAG_IS_OUTPUT | SOUND_ACTION_FLAG_IS_PRECISE);
                break;
        case LOGOUT_KEY:
                gnome_session_logout (manager, 0);
                break;
        case REBOOT_KEY:
                gnome_session_reboot (manager);
                break;
        case SHUTDOWN_KEY:
                gnome_session_shutdown (manager);
                break;
        case EJECT_KEY:
                do_eject_action (manager);
                break;
        case HOME_KEY:
                do_home_key_action (manager, timestamp);
                break;
        case SEARCH_KEY:
                do_search_action (manager, timestamp);
                break;
        case EMAIL_KEY:
                do_url_action (manager, "mailto", timestamp);
                break;
        case SCREENSAVER_KEY:
                do_lock_screensaver (manager);
                break;
        case HELP_KEY:
                do_url_action (manager, "ghelp", timestamp);
                break;
        case TERMINAL_KEY:
                do_terminal_action (manager);
                break;
        case WWW_KEY:
                do_url_action (manager, "http", timestamp);
                break;
        case MEDIA_KEY:
                do_media_action (manager, timestamp);
                break;
        case CALCULATOR_KEY:
                do_execute_desktop_or_desktop (manager, "org.gnome.Calculator.desktop", "gnome-calculator_gnome-calculator.desktop", timestamp);
                break;
        case CONTROL_CENTER_KEY:
                do_execute_desktop_or_desktop (manager, "org.gnome.Settings.desktop", NULL, timestamp);
                break;
        case PLAY_KEY:
                return do_multimedia_player_action (manager, "Play");
        case PAUSE_KEY:
                return do_multimedia_player_action (manager, "Pause");
        case STOP_KEY:
                return do_multimedia_player_action (manager, "Stop");
        case PREVIOUS_KEY:
                return do_multimedia_player_action (manager, "Previous");
        case NEXT_KEY:
                return do_multimedia_player_action (manager, "Next");
        case REWIND_KEY:
                return do_multimedia_player_action (manager, "Rewind");
        case FORWARD_KEY:
                return do_multimedia_player_action (manager, "FastForward");
        case REPEAT_KEY:
                return do_multimedia_player_action (manager, "Repeat");
        case RANDOM_KEY:
                return do_multimedia_player_action (manager, "Shuffle");
        case ROTATE_VIDEO_LOCK_KEY:
                do_video_rotate_lock_action (manager, timestamp);
                break;
        case MAGNIFIER_KEY:
                do_magnifier_action (manager);
                break;
        case SCREENREADER_KEY:
                do_screenreader_action (manager);
                break;
        case ON_SCREEN_KEYBOARD_KEY:
                do_on_screen_keyboard_action (manager);
                break;
	case INCREASE_TEXT_KEY:
	case DECREASE_TEXT_KEY:
		do_text_size_action (manager, type);
		break;
	case MAGNIFIER_ZOOM_IN_KEY:
	case MAGNIFIER_ZOOM_OUT_KEY:
		do_magnifier_zoom_action (manager, type);
		break;
	case TOGGLE_CONTRAST_KEY:
		do_toggle_contrast_action (manager);
		break;
        case POWER_KEY:
                do_config_power_button_action (manager, power_action_noninteractive);
                break;
        case SUSPEND_KEY:
                do_config_power_action (manager, GSD_POWER_ACTION_SUSPEND, power_action_noninteractive);
                break;
        case HIBERNATE_KEY:
                do_config_power_action (manager, GSD_POWER_ACTION_HIBERNATE, power_action_noninteractive);
                break;
        case SCREEN_BRIGHTNESS_UP_KEY:
        case SCREEN_BRIGHTNESS_DOWN_KEY:
        case SCREEN_BRIGHTNESS_CYCLE_KEY:
        case KEYBOARD_BRIGHTNESS_UP_KEY:
        case KEYBOARD_BRIGHTNESS_DOWN_KEY:
        case KEYBOARD_BRIGHTNESS_TOGGLE_KEY:
                do_brightness_action (manager, type);
                break;
        case BATTERY_KEY:
                do_battery_action (manager);
                break;
        case RFKILL_KEY:
                do_rfkill_action (manager, FALSE);
                break;
        case BLUETOOTH_RFKILL_KEY:
                do_rfkill_action (manager, TRUE);
                break;
        /* Note, no default so compiler catches missing keys */
        case CUSTOM_KEY:
                g_assert_not_reached ();
        }

        return FALSE;
}

static void
on_accelerator_activated (ShellKeyGrabber     *grabber,
                          guint                accel_id,
                          GVariant            *parameters,
                          GsdMediaKeysManager *manager)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        GVariantDict dict;
        guint i;
        guint deviceid;
        gchar *device_node;
        guint timestamp;
        guint mode;

        g_variant_dict_init (&dict, parameters);

        if (!g_variant_dict_lookup (&dict, "device-id", "u", &deviceid))
              deviceid = 0;
        if (!g_variant_dict_lookup (&dict, "device-node", "s", &device_node))
              device_node = NULL;
        if (!g_variant_dict_lookup (&dict, "timestamp", "u", &timestamp))
              timestamp = GDK_CURRENT_TIME;
        if (!g_variant_dict_lookup (&dict, "action-mode", "u", &mode))
              mode = 0;

	if (!device_node && !gnome_settings_is_wayland ())
              device_node = xdevice_get_device_node (deviceid);

        g_debug ("Received accel id %u (device-id: %u, timestamp: %u, mode: 0x%X)",
                 accel_id, deviceid, timestamp, mode);

        for (i = 0; i < priv->keys->len; i++) {
                MediaKey *key;
                guint j;

                key = g_ptr_array_index (priv->keys, i);

                for (j = 0; j < key->accel_ids->len; j++) {
                        if (g_array_index (key->accel_ids, guint, j) == accel_id)
                                break;
                }
                if (j >= key->accel_ids->len)
                        continue;

                if (key->key_type == CUSTOM_KEY)
                        do_custom_action (manager, device_node, key, timestamp);
                else
                        do_action (manager, device_node, mode, key->key_type, timestamp);

                g_free (device_node);
                return;
        }

        g_warning ("Could not find accelerator for accel id %u", accel_id);
        g_free (device_node);
}

static void
update_theme_settings (GSettings           *settings,
		       const char          *key,
		       GsdMediaKeysManager *manager)
{
	GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
	char *theme;

	theme = g_settings_get_string (priv->interface_settings, key);
	if (g_str_equal (theme, HIGH_CONTRAST)) {
		g_free (theme);
	} else {
		if (g_str_equal (key, "gtk-theme")) {
			g_free (priv->gtk_theme);
			priv->gtk_theme = theme;
		} else {
			g_free (priv->icon_theme);
			priv->icon_theme = theme;
		}
	}
}

typedef struct {
        GvcHeadsetPortChoice choice;
        gchar *name;
} AudioSelectionChoice;

static AudioSelectionChoice audio_selection_choices[] = {
        { GVC_HEADSET_PORT_CHOICE_HEADPHONES,   "headphones" },
        { GVC_HEADSET_PORT_CHOICE_HEADSET,      "headset" },
        { GVC_HEADSET_PORT_CHOICE_MIC,          "microphone" },
};

static void
audio_selection_done (GDBusConnection *connection,
                      const gchar     *sender_name,
                      const gchar     *object_path,
                      const gchar     *interface_name,
                      const gchar     *signal_name,
                      GVariant        *parameters,
                      gpointer         data)
{
        GsdMediaKeysManager *manager = GSD_MEDIA_KEYS_MANAGER (data);
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        const gchar *choice;
        guint i;

        if (!priv->audio_selection_requested)
                return;

        choice = NULL;
        g_variant_get_child (parameters, 0, "&s", &choice);
        if (!choice)
                return;

        for (i = 0; i < G_N_ELEMENTS (audio_selection_choices); ++i) {
                if (g_str_equal (choice, audio_selection_choices[i].name)) {
                        gvc_mixer_control_set_headset_port (priv->volume,
                                                            priv->audio_selection_device_id,
                                                            audio_selection_choices[i].choice);
                        break;
                }
        }

        priv->audio_selection_requested = FALSE;
}

static void
audio_selection_needed (GvcMixerControl      *control,
                        guint                 id,
                        gboolean              show_dialog,
                        GvcHeadsetPortChoice  choices,
                        GsdMediaKeysManager  *manager)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        gchar *args[G_N_ELEMENTS (audio_selection_choices) + 1];
        guint i, n;

        if (!priv->audio_selection_conn)
                return;

        if (priv->audio_selection_requested) {
                g_dbus_connection_call (priv->audio_selection_conn,
                                        AUDIO_SELECTION_DBUS_NAME,
                                        AUDIO_SELECTION_DBUS_PATH,
                                        AUDIO_SELECTION_DBUS_INTERFACE,
                                        "Close", NULL, NULL,
                                        G_DBUS_CALL_FLAGS_NONE,
                                        -1, NULL, NULL, NULL);
                priv->audio_selection_requested = FALSE;
        }

        if (!show_dialog)
                return;

        n = 0;
        for (i = 0; i < G_N_ELEMENTS (audio_selection_choices); ++i) {
                if (choices & audio_selection_choices[i].choice)
                        args[n++] = audio_selection_choices[i].name;
        }
        args[n] = NULL;

        priv->audio_selection_requested = TRUE;
        priv->audio_selection_device_id = id;
        g_dbus_connection_call (priv->audio_selection_conn,
                                AUDIO_SELECTION_DBUS_NAME,
                                AUDIO_SELECTION_DBUS_PATH,
                                AUDIO_SELECTION_DBUS_INTERFACE,
                                "Open",
                                g_variant_new ("(^as)", args),
                                NULL,
                                G_DBUS_CALL_FLAGS_NONE,
                                -1, NULL, NULL, NULL);
}

static void
audio_selection_appeared (GDBusConnection *connection,
                          const gchar     *name,
                          const gchar     *name_owner,
                          gpointer         data)
{
        GsdMediaKeysManager *manager = data;
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);

        priv->audio_selection_conn = connection;
        priv->audio_selection_signal_id =
                g_dbus_connection_signal_subscribe (connection,
                                                    AUDIO_SELECTION_DBUS_NAME,
                                                    AUDIO_SELECTION_DBUS_INTERFACE,
                                                    "DeviceSelected",
                                                    AUDIO_SELECTION_DBUS_PATH,
                                                    NULL,
                                                    G_DBUS_SIGNAL_FLAGS_NONE,
                                                    audio_selection_done,
                                                    manager,
                                                    NULL);
}

static void
clear_audio_selection (GsdMediaKeysManager *manager)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);

        if (priv->audio_selection_signal_id)
                g_dbus_connection_signal_unsubscribe (priv->audio_selection_conn,
                                                      priv->audio_selection_signal_id);
        priv->audio_selection_signal_id = 0;
        priv->audio_selection_conn = NULL;
}

static void
audio_selection_vanished (GDBusConnection *connection,
                          const gchar     *name,
                          gpointer         data)
{
        if (connection)
                clear_audio_selection (data);
}

static void
initialize_volume_handler (GsdMediaKeysManager *manager)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);

        /* initialise Volume handler
         *
         * We do this one here to force checking gstreamer cache, etc.
         * The rest (grabbing and setting the keys) can happen in an
         * idle.
         */
        gnome_settings_profile_start ("gvc_mixer_control_new");

        priv->volume = gvc_mixer_control_new ("GNOME Volume Control Media Keys");

        g_signal_connect (priv->volume,
                          "state-changed",
                          G_CALLBACK (on_control_state_changed),
                          manager);
        g_signal_connect (priv->volume,
                          "default-sink-changed",
                          G_CALLBACK (on_control_default_sink_changed),
                          manager);
        g_signal_connect (priv->volume,
                          "default-source-changed",
                          G_CALLBACK (on_control_default_source_changed),
                          manager);
        g_signal_connect (priv->volume,
                          "stream-removed",
                          G_CALLBACK (on_control_stream_removed),
                          manager);
        g_signal_connect (priv->volume,
                          "audio-device-selection-needed",
                          G_CALLBACK (audio_selection_needed),
                          manager);

        gvc_mixer_control_open (priv->volume);

        priv->audio_selection_watch_id =
                g_bus_watch_name (G_BUS_TYPE_SESSION,
                                  AUDIO_SELECTION_DBUS_NAME,
                                  G_BUS_NAME_WATCHER_FLAGS_NONE,
                                  audio_selection_appeared,
                                  audio_selection_vanished,
                                  manager,
                                  NULL);

        gnome_settings_profile_end ("gvc_mixer_control_new");
}

static void
on_key_grabber_ready (GObject      *source,
                      GAsyncResult *result,
                      gpointer      data)
{
        GsdMediaKeysManager *manager = data;
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        GError *error = NULL;

        priv->key_grabber = shell_key_grabber_proxy_new_for_bus_finish (result, &error);

        if (!priv->key_grabber) {
                if (!g_error_matches (error, G_IO_ERROR, G_IO_ERROR_CANCELLED))
                        g_warning ("Failed to create proxy for key grabber: %s", error->message);
                g_error_free (error);
                return;
        }

        g_dbus_proxy_set_default_timeout (G_DBUS_PROXY (priv->key_grabber),
                                          SHELL_GRABBER_CALL_TIMEOUT);

        g_signal_connect (priv->key_grabber, "accelerator-activated",
                          G_CALLBACK (on_accelerator_activated), manager);

        init_kbd (manager);
}

static void
shell_presence_changed (GsdMediaKeysManager *manager)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        gchar *name_owner;

        name_owner = g_dbus_proxy_get_name_owner (G_DBUS_PROXY (priv->shell_proxy));

        g_ptr_array_set_size (priv->keys, 0);
        g_clear_object (&priv->key_grabber);

        if (name_owner) {
                shell_key_grabber_proxy_new_for_bus (G_BUS_TYPE_SESSION,
                                                     0,
                                                     name_owner,
                                                     SHELL_DBUS_PATH,
                                                     priv->grab_cancellable,
                                                     on_key_grabber_ready, manager);
                g_free (name_owner);
        }
}

static void
on_rfkill_proxy_ready (GObject      *source,
                       GAsyncResult *result,
                       gpointer      data)
{
        GsdMediaKeysManager *manager = data;
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);

        priv->rfkill_proxy =
                g_dbus_proxy_new_for_bus_finish (result, NULL);
}

static void
rfkill_appeared_cb (GDBusConnection *connection,
                    const gchar     *name,
                    const gchar     *name_owner,
                    gpointer         user_data)
{
        GsdMediaKeysManager *manager = user_data;
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);

        g_dbus_proxy_new_for_bus (G_BUS_TYPE_SESSION,
                                  0, NULL,
                                  "org.gnome.SettingsDaemon.Rfkill",
                                  "/org/gnome/SettingsDaemon/Rfkill",
                                  "org.gnome.SettingsDaemon.Rfkill",
                                  priv->rfkill_cancellable,
                                  on_rfkill_proxy_ready, manager);
}

static gboolean
start_media_keys_idle_cb (GsdMediaKeysManager *manager)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);

        g_debug ("Starting media_keys manager");
        gnome_settings_profile_start (NULL);

        priv->keys = g_ptr_array_new_with_free_func ((GDestroyNotify) media_key_unref);
        priv->keys_to_sync = g_hash_table_new_full (g_direct_hash, g_direct_equal, (GDestroyNotify) media_key_unref, NULL);

        initialize_volume_handler (manager);

        priv->settings = g_settings_new (SETTINGS_BINDING_DIR);
        g_signal_connect (G_OBJECT (priv->settings), "changed",
                          G_CALLBACK (gsettings_changed_cb), manager);
        g_signal_connect (G_OBJECT (priv->settings), "changed::custom-keybindings",
                          G_CALLBACK (gsettings_custom_changed_cb), manager);

        priv->custom_settings =
          g_hash_table_new_full (g_str_hash, g_str_equal,
                                 g_free, g_object_unref);

        priv->sound_settings = g_settings_new (SETTINGS_SOUND_DIR);
        g_signal_connect (G_OBJECT (priv->sound_settings),
			  "changed::" ALLOW_VOLUME_ABOVE_100_PERCENT_KEY,
                          G_CALLBACK (allow_volume_above_100_percent_changed_cb), manager);
        allow_volume_above_100_percent_changed_cb (priv->sound_settings,
                                                   ALLOW_VOLUME_ABOVE_100_PERCENT_KEY, manager);

        /* for the power plugin interface code */
        priv->power_settings = g_settings_new (SETTINGS_POWER_DIR);
        priv->chassis_type = gnome_settings_get_chassis_type ();

        /* Logic from http://git.gnome.org/browse/gnome-shell/tree/js/ui/status/accessibility.js#n163 */
        priv->interface_settings = g_settings_new (SETTINGS_INTERFACE_DIR);
        g_signal_connect (G_OBJECT (priv->interface_settings), "changed::gtk-theme",
			  G_CALLBACK (update_theme_settings), manager);
        g_signal_connect (G_OBJECT (priv->interface_settings), "changed::icon-theme",
			  G_CALLBACK (update_theme_settings), manager);
	priv->gtk_theme = g_settings_get_string (priv->interface_settings, "gtk-theme");
	if (g_str_equal (priv->gtk_theme, HIGH_CONTRAST)) {
		g_free (priv->gtk_theme);
		priv->gtk_theme = NULL;
	}
	priv->icon_theme = g_settings_get_string (priv->interface_settings, "icon-theme");

        priv->grab_cancellable = g_cancellable_new ();
        priv->rfkill_cancellable = g_cancellable_new ();

        priv->shell_proxy = gnome_settings_bus_get_shell_proxy ();
        g_signal_connect_swapped (priv->shell_proxy, "notify::g-name-owner",
                                  G_CALLBACK (shell_presence_changed), manager);
        shell_presence_changed (manager);

        priv->rfkill_watch_id = g_bus_watch_name (G_BUS_TYPE_SESSION,
                                                  "org.gnome.SettingsDaemon.Rfkill",
                                                  G_BUS_NAME_WATCHER_FLAGS_NONE,
                                                  rfkill_appeared_cb,
                                                  NULL,
                                                  manager, NULL);

        g_debug ("Starting mpris controller");
        priv->mpris_controller = mpris_controller_new ();

        /* Rotation */
        priv->iio_sensor_watch_id = g_bus_watch_name (G_BUS_TYPE_SYSTEM,
                                                      "net.hadess.SensorProxy",
                                                      G_BUS_NAME_WATCHER_FLAGS_NONE,
                                                      iio_sensor_appeared_cb,
                                                      iio_sensor_disappeared_cb,
                                                      manager, NULL);

        gnome_settings_profile_end (NULL);

        priv->start_idle_id = 0;

        return FALSE;
}

static GVariant *
map_keybinding (GVariant *variant, GVariant *old_default, GVariant *new_default)
{
        g_autoptr(GPtrArray) array = g_ptr_array_new ();
        g_autofree const gchar **defaults = NULL;
        const gchar *old_default_value;
        const gchar **pos;
        const gchar *value;

        defaults = g_variant_get_strv (new_default, NULL);
        g_return_val_if_fail (defaults != NULL, NULL);
        pos = defaults;

        value = g_variant_get_string (variant, NULL);
        old_default_value = g_variant_get_string (old_default, NULL);

        /* Reset the keybinding configuration even if the user has the default
         * configured explicitly (as the key will be bound by the corresponding
         * static binding now). */
        if (g_strcmp0 (value, old_default_value) == 0)
                return NULL;

        /* If the user has a custom value that is not in the list, then
         * insert it instead of the first default entry. */
        if (!g_strv_contains (defaults, value)) {
                g_ptr_array_add (array, (gpointer) value);
                if (*pos)
                        pos++;
        }

        /* Add all remaining default values */
        for (; *pos; pos++)
              g_ptr_array_add (array, (gpointer) *pos);

        g_ptr_array_add (array, NULL);

        return g_variant_new_strv ((const gchar * const *) array->pdata, -1);
}

static void
migrate_keybinding_settings (void)
{
        GsdSettingsMigrateEntry binding_entries[] = {
                { "calculator",                 "calculator",                   map_keybinding },
                { "control-center",             "control-center",               map_keybinding },
                { "email",                      "email",                        map_keybinding },
                { "eject",                      "eject",                        map_keybinding },
                { "help",                       "help",                         map_keybinding },
                { "home",                       "home",                         map_keybinding },
                { "media",                      "media",                        map_keybinding },
                { "next",                       "next",                         map_keybinding },
                { "pause",                      "pause",                        map_keybinding },
                { "play",                       "play",                         map_keybinding },
                { "logout",                     "logout",                       map_keybinding },
                { "previous",                   "previous",                     map_keybinding },
                { "screensaver",                "screensaver",                  map_keybinding },
                { "search",                     "search",                       map_keybinding },
                { "stop",                       "stop",                         map_keybinding },
                { "volume-down",                "volume-down",                  map_keybinding },
                { "volume-mute",                "volume-mute",                  map_keybinding },
                { "volume-up",                  "volume-up",                    map_keybinding },
                { "mic-mute",                   "mic-mute",                     map_keybinding },
                { "terminal",                   "terminal",                     map_keybinding },
                { "www",                        "www",                          map_keybinding },
                { "magnifier",                  "magnifier",                    map_keybinding },
                { "screenreader",               "screenreader",                 map_keybinding },
                { "on-screen-keyboard",         "on-screen-keyboard",           map_keybinding },
                { "increase-text-size",         "increase-text-size",           map_keybinding },
                { "decrease-text-size",         "decrease-text-size",           map_keybinding },
                { "toggle-contrast",            "toggle-contrast",              map_keybinding },
                { "magnifier-zoom-in",          "magnifier-zoom-in",            map_keybinding },
                { "magnifier-zoom-out",         "magnifier-zoom-out",           map_keybinding },
        };

        gsd_settings_migrate_check ("org.gnome.settings-daemon.plugins.media-keys.deprecated",
                                    "/org/gnome/settings-daemon/plugins/media-keys/",
                                    "org.buddiesofbudgie.settings-daemon.plugins.media-keys",
                                    "/org/buddiesofbudgie/settings-daemon/plugins/media-keys/",
                                    binding_entries, G_N_ELEMENTS (binding_entries));
}

static void
gsd_media_keys_manager_startup (GApplication *app)
{
        GsdMediaKeysManager *manager = GSD_MEDIA_KEYS_MANAGER (app);
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        const char * const subsystems[] = { "input", "usb", "sound", NULL };

        gnome_settings_profile_start (NULL);

        migrate_keybinding_settings ();

#if HAVE_GUDEV
        priv->streams = g_hash_table_new_full (g_str_hash, g_str_equal, g_free, NULL);
        priv->udev_client = g_udev_client_new (subsystems);
#endif

        priv->start_idle_id = g_idle_add ((GSourceFunc) start_media_keys_idle_cb, manager);
        g_source_set_name_by_id (priv->start_idle_id, "[gnome-settings-daemon] start_media_keys_idle_cb");

        register_manager (manager);

        G_APPLICATION_CLASS (gsd_media_keys_manager_parent_class)->startup (app);

        gnome_settings_profile_end (NULL);
}

static void
gsd_media_keys_manager_shutdown (GApplication *app)
{
        GsdMediaKeysManager *manager = GSD_MEDIA_KEYS_MANAGER (app);
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);

        g_debug ("Stopping media_keys manager");

        if (priv->start_idle_id != 0) {
                g_source_remove (priv->start_idle_id);
                priv->start_idle_id = 0;
        }

        if (priv->bus_cancellable != NULL) {
                g_cancellable_cancel (priv->bus_cancellable);
                g_object_unref (priv->bus_cancellable);
                priv->bus_cancellable = NULL;
        }

        if (priv->gtksettings != NULL) {
                g_signal_handlers_disconnect_by_func (priv->gtksettings, sound_theme_changed, manager);
                priv->gtksettings = NULL;
        }

        if (priv->rfkill_watch_id > 0) {
                g_bus_unwatch_name (priv->rfkill_watch_id);
                priv->rfkill_watch_id = 0;
        }

        if (priv->iio_sensor_watch_id > 0) {
                g_bus_unwatch_name (priv->iio_sensor_watch_id);
                priv->iio_sensor_watch_id = 0;
        }

        if (priv->inhibit_suspend_fd != -1) {
                close (priv->inhibit_suspend_fd);
                priv->inhibit_suspend_fd = -1;
                priv->inhibit_suspend_taken = FALSE;
        }

        if (priv->reenable_power_button_timer_id) {
                g_source_remove (priv->reenable_power_button_timer_id);
                priv->reenable_power_button_timer_id = 0;
        }

        g_clear_pointer (&priv->ca, ca_context_destroy);

#if HAVE_GUDEV
        g_clear_pointer (&priv->streams, g_hash_table_destroy);
        g_clear_object (&priv->udev_client);
#endif /* HAVE_GUDEV */

        g_clear_object (&priv->logind_proxy);
        g_clear_object (&priv->settings);
        g_clear_object (&priv->sound_settings);
        g_clear_object (&priv->power_settings);
        g_clear_object (&priv->power_proxy);
        g_clear_object (&priv->power_screen_proxy);
        g_clear_object (&priv->power_keyboard_proxy);
        g_clear_object (&priv->composite_device);
        g_clear_object (&priv->mpris_controller);
        g_clear_object (&priv->iio_sensor_proxy);
        g_clear_pointer (&priv->chassis_type, g_free);
        g_clear_object (&priv->connection);

        if (priv->keys_sync_data) {
                /* Cancel ongoing sync. */
                priv->keys_sync_data->cancelled = TRUE;
                priv->keys_sync_data = NULL;
        }
        if (priv->keys_sync_source_id)
                g_source_remove (priv->keys_sync_source_id);
        priv->keys_sync_source_id = 0;

        /* Remove all grabs; i.e.:
         *  - add all keys to the sync queue
         *  - remove all keys from the internal keys list
         *  - call the function to start a sync
         *  - "cancel" the sync operation as the manager will be gone
         */
        if (priv->keys != NULL) {
                while (priv->keys->len) {
                        MediaKey *key = g_ptr_array_index (priv->keys, 0);
                        g_hash_table_add (priv->keys_to_sync, media_key_ref (key));
                        g_ptr_array_remove_index_fast (priv->keys, 0);
                }

                keys_sync_start (manager);

                g_clear_pointer (&priv->keys, g_ptr_array_unref);
        }

        g_clear_pointer (&priv->keys_to_sync, g_hash_table_destroy);

        g_clear_object (&priv->key_grabber);

        if (priv->grab_cancellable != NULL) {
                g_cancellable_cancel (priv->grab_cancellable);
                g_clear_object (&priv->grab_cancellable);
        }

        if (priv->rfkill_cancellable != NULL) {
                g_cancellable_cancel (priv->rfkill_cancellable);
                g_clear_object (&priv->rfkill_cancellable);
        }

        g_clear_object (&priv->sink);
        g_clear_object (&priv->source);
        g_clear_object (&priv->volume);
        g_clear_object (&priv->shell_proxy);

        if (priv->audio_selection_watch_id)
                g_bus_unwatch_name (priv->audio_selection_watch_id);
        priv->audio_selection_watch_id = 0;
        clear_audio_selection (manager);

        G_APPLICATION_CLASS (gsd_media_keys_manager_parent_class)->shutdown (app);
}

static void
inhibit_suspend_done (GObject      *source,
                      GAsyncResult *result,
                      gpointer      user_data)
{
        GDBusProxy *proxy = G_DBUS_PROXY (source);
        GsdMediaKeysManager *manager = GSD_MEDIA_KEYS_MANAGER (user_data);
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        GError *error = NULL;
        GVariant *res;
        GUnixFDList *fd_list = NULL;
        gint idx;

        res = g_dbus_proxy_call_with_unix_fd_list_finish (proxy, &fd_list, result, &error);
        if (res == NULL) {
                if (!g_error_matches (error, G_IO_ERROR, G_IO_ERROR_CANCELLED))
                        g_warning ("Unable to inhibit suspend: %s", error->message);
                g_error_free (error);
        } else {
                g_variant_get (res, "(h)", &idx);
                priv->inhibit_suspend_fd = g_unix_fd_list_get (fd_list, idx, &error);
                if (priv->inhibit_suspend_fd == -1) {
                        g_warning ("Failed to receive system suspend inhibitor fd: %s", error->message);
                        g_error_free (error);
                }
                g_debug ("System suspend inhibitor fd is %d", priv->inhibit_suspend_fd);
                g_object_unref (fd_list);
                g_variant_unref (res);
        }
}

/* We take a delay inhibitor here, which causes logind to send a PrepareForSleep
 * signal, so that we can set power_button_disabled on suspend.
 */
static void
inhibit_suspend (GsdMediaKeysManager *manager)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);

        if (priv->inhibit_suspend_taken) {
                g_debug ("already inhibited suspend");
                return;
        }
        g_debug ("Adding suspend delay inhibitor");
        priv->inhibit_suspend_taken = TRUE;
        g_dbus_proxy_call_with_unix_fd_list (priv->logind_proxy,
                                             "Inhibit",
                                             g_variant_new ("(ssss)",
                                                            "sleep",
                                                            g_get_user_name (),
                                                            "GNOME handling keypresses",
                                                            "delay"),
                                             0,
                                             G_MAXINT,
                                             NULL,
                                             NULL,
                                             inhibit_suspend_done,
                                             manager);
}

static void
uninhibit_suspend (GsdMediaKeysManager *manager)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);

        if (priv->inhibit_suspend_fd == -1) {
                g_debug ("no suspend delay inhibitor");
                return;
        }
        g_debug ("Removing suspend delay inhibitor");
        close (priv->inhibit_suspend_fd);
        priv->inhibit_suspend_fd = -1;
        priv->inhibit_suspend_taken = FALSE;
}

static gboolean
reenable_power_button_timer_cb (GsdMediaKeysManager *manager)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);

        priv->power_button_disabled = FALSE;
        /* This is a one shot timer. */
        priv->reenable_power_button_timer_id = 0;
        return G_SOURCE_REMOVE;
}

static void
setup_reenable_power_button_timer (GsdMediaKeysManager *manager)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);

        if (priv->reenable_power_button_timer_id != 0)
                return;

        priv->reenable_power_button_timer_id =
                g_timeout_add (GSD_REENABLE_POWER_BUTTON_DELAY,
                               (GSourceFunc) reenable_power_button_timer_cb,
                               manager);
        g_source_set_name_by_id (priv->reenable_power_button_timer_id,
                                 "[GsdMediaKeysManager] Reenable power button timer");
}

static void
stop_reenable_power_button_timer (GsdMediaKeysManager *manager)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);

        if (priv->reenable_power_button_timer_id == 0)
                return;

        g_source_remove (priv->reenable_power_button_timer_id);
        priv->reenable_power_button_timer_id = 0;
}

static void
logind_proxy_signal_cb (GDBusProxy  *proxy,
                        const gchar *sender_name,
                        const gchar *signal_name,
                        GVariant    *parameters,
                        gpointer     user_data)
{
        GsdMediaKeysManager *manager = GSD_MEDIA_KEYS_MANAGER (user_data);
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        gboolean is_about_to_suspend;

        if (g_strcmp0 (signal_name, "PrepareForSleep") != 0)
                return;
        g_variant_get (parameters, "(b)", &is_about_to_suspend);
        if (is_about_to_suspend) {
                /* Some devices send a power-button press on resume when woken
                 * up with the power-button, suppress this, to avoid immediate
                 * re-suspend. */
                stop_reenable_power_button_timer (manager);
                priv->power_button_disabled = TRUE;
                uninhibit_suspend (manager);
        } else {
                inhibit_suspend (manager);
                /* Re-enable power-button handling (after a small delay) */
                setup_reenable_power_button_timer (manager);
        }
}

static void
gsd_media_keys_manager_class_init (GsdMediaKeysManagerClass *klass)
{
        GObjectClass   *object_class = G_OBJECT_CLASS (klass);
        GApplicationClass *application_class = G_APPLICATION_CLASS (klass);

        object_class->finalize = gsd_media_keys_manager_finalize;

        application_class->startup = gsd_media_keys_manager_startup;
        application_class->shutdown = gsd_media_keys_manager_shutdown;
}

static void
inhibit_done (GObject      *source,
              GAsyncResult *result,
              gpointer      user_data)
{
        GDBusProxy *proxy = G_DBUS_PROXY (source);
        GsdMediaKeysManager *manager = GSD_MEDIA_KEYS_MANAGER (user_data);
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        GError *error = NULL;
        GVariant *res;
        GUnixFDList *fd_list = NULL;
        gint idx;

        res = g_dbus_proxy_call_with_unix_fd_list_finish (proxy, &fd_list, result, &error);
        if (res == NULL) {
                if (!g_error_matches (error, G_IO_ERROR, G_IO_ERROR_CANCELLED))
                        g_warning ("Unable to inhibit keypresses: %s", error->message);
                g_error_free (error);
        } else {
                g_variant_get (res, "(h)", &idx);
                priv->inhibit_keys_fd = g_unix_fd_list_get (fd_list, idx, &error);
                if (priv->inhibit_keys_fd == -1) {
                        g_warning ("Failed to receive system inhibitor fd: %s", error->message);
                        g_error_free (error);
                }
                g_debug ("System inhibitor fd is %d", priv->inhibit_keys_fd);
                g_object_unref (fd_list);
                g_variant_unref (res);
        }
}

static void
gsd_media_keys_manager_init (GsdMediaKeysManager *manager)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        GError *error;
        GDBusConnection *bus;

        error = NULL;
        priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);

        bus = g_bus_get_sync (G_BUS_TYPE_SYSTEM, NULL, &error);
        if (bus == NULL) {
                g_warning ("Failed to connect to system bus: %s",
                           error->message);
                g_error_free (error);
                return;
        }

        priv->logind_proxy =
                g_dbus_proxy_new_sync (bus,
                                       0,
                                       NULL,
                                       SYSTEMD_DBUS_NAME,
                                       SYSTEMD_DBUS_PATH,
                                       SYSTEMD_DBUS_INTERFACE,
                                       NULL,
                                       &error);

        if (priv->logind_proxy == NULL) {
                g_warning ("Failed to connect to systemd: %s",
                           error->message);
                g_error_free (error);
        }

        g_object_unref (bus);

        g_debug ("Adding system inhibitors for power keys");
        priv->inhibit_keys_fd = -1;
        g_dbus_proxy_call_with_unix_fd_list (priv->logind_proxy,
                                             "Inhibit",
                                             g_variant_new ("(ssss)",
                                                            "handle-power-key:handle-suspend-key:handle-hibernate-key",
                                                            g_get_user_name (),
                                                            "GNOME handling keypresses",
                                                            "block"),
                                             0,
                                             G_MAXINT,
                                             NULL,
                                             NULL,
                                             inhibit_done,
                                             manager);

        g_debug ("Adding delay inhibitor for suspend");
        priv->inhibit_suspend_fd = -1;
        g_signal_connect (priv->logind_proxy, "g-signal",
                          G_CALLBACK (logind_proxy_signal_cb),
                          manager);
        inhibit_suspend (manager);
}

static void
gsd_media_keys_manager_finalize (GObject *object)
{
        GsdMediaKeysManager *manager = GSD_MEDIA_KEYS_MANAGER (object);
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);

        if (priv->inhibit_keys_fd != -1)
                close (priv->inhibit_keys_fd);

        g_clear_object (&priv->logind_proxy);
        g_clear_object (&priv->screen_saver_proxy);

        G_OBJECT_CLASS (gsd_media_keys_manager_parent_class)->finalize (object);
}

static void
power_keyboard_proxy_signal_cb (GDBusProxy  *proxy,
                       const gchar *sender_name,
                       const gchar *signal_name,
                       GVariant    *parameters,
                       gpointer     user_data)
{
        GsdMediaKeysManager *manager = GSD_MEDIA_KEYS_MANAGER (user_data);
        gint brightness;
        const gchar *source;

        if (g_strcmp0 (signal_name, "BrightnessChanged") != 0)
                return;

        g_variant_get (parameters, "(i&s)", &brightness, &source);

        /* For non "internal" changes we already show the osd when handling
         * the hotkey causing the change. */
        if (g_strcmp0 (source, "internal") != 0)
                return;

        show_osd (manager, "keyboard-brightness-symbolic", NULL, (double) brightness / 100.0, NULL);
}

static void
power_ready_cb (GObject             *source_object,
                GAsyncResult        *res,
                GsdMediaKeysManager *manager)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        GError *error = NULL;

        priv->power_proxy = g_dbus_proxy_new_finish (res, &error);
        if (priv->power_proxy == NULL) {
                if (!g_error_matches (error, G_IO_ERROR, G_IO_ERROR_CANCELLED))
                        g_warning ("Failed to get proxy for power: %s",
                                   error->message);
                g_error_free (error);
        }
}

static void
power_screen_ready_cb (GObject             *source_object,
                       GAsyncResult        *res,
                       GsdMediaKeysManager *manager)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        GError *error = NULL;

        priv->power_screen_proxy = g_dbus_proxy_new_finish (res, &error);
        if (priv->power_screen_proxy == NULL) {
                if (!g_error_matches (error, G_IO_ERROR, G_IO_ERROR_CANCELLED))
                        g_warning ("Failed to get proxy for power (screen): %s",
                                   error->message);
                g_error_free (error);
        }
}

static void
power_keyboard_ready_cb (GObject             *source_object,
                         GAsyncResult        *res,
                         GsdMediaKeysManager *manager)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        GError *error = NULL;

        priv->power_keyboard_proxy = g_dbus_proxy_new_finish (res, &error);
        if (priv->power_keyboard_proxy == NULL) {
                if (!g_error_matches (error, G_IO_ERROR, G_IO_ERROR_CANCELLED))
                        g_warning ("Failed to get proxy for power (keyboard): %s",
                                   error->message);
                g_error_free (error);
        }

        g_signal_connect (priv->power_keyboard_proxy, "g-signal",
                          G_CALLBACK (power_keyboard_proxy_signal_cb),
                          manager);
}

static void
on_bus_gotten (GObject             *source_object,
               GAsyncResult        *res,
               GsdMediaKeysManager *manager)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);
        GDBusConnection *connection;
        GError *error = NULL;
        UpClient *up_client;

        connection = g_bus_get_finish (res, &error);
        if (connection == NULL) {
                if (!g_error_matches (error, G_IO_ERROR, G_IO_ERROR_CANCELLED))
                        g_warning ("Could not get session bus: %s", error->message);
                g_error_free (error);
                return;
        }
        priv->connection = connection;

        g_dbus_proxy_new (priv->connection,
                          G_DBUS_PROXY_FLAGS_NONE,
                          NULL,
                          GSD_DBUS_NAME ".Power",
                          GSD_DBUS_PATH "/Power",
                          GSD_DBUS_BASE_INTERFACE ".Power",
                          NULL,
                          (GAsyncReadyCallback) power_ready_cb,
                          manager);

        g_dbus_proxy_new (priv->connection,
                          G_DBUS_PROXY_FLAGS_NONE,
                          NULL,
                          GSD_DBUS_NAME ".Power",
                          GSD_DBUS_PATH "/Power",
                          GSD_DBUS_BASE_INTERFACE ".Power.Screen",
                          NULL,
                          (GAsyncReadyCallback) power_screen_ready_cb,
                          manager);

        g_dbus_proxy_new (priv->connection,
                          G_DBUS_PROXY_FLAGS_NONE,
                          NULL,
                          GSD_DBUS_NAME ".Power",
                          GSD_DBUS_PATH "/Power",
                          GSD_DBUS_BASE_INTERFACE ".Power.Keyboard",
                          NULL,
                          (GAsyncReadyCallback) power_keyboard_ready_cb,
                          manager);

        up_client = up_client_new ();
        priv->composite_device = up_client_get_display_device (up_client);
        g_object_unref (up_client);
}

static void
register_manager (GsdMediaKeysManager *manager)
{
        GsdMediaKeysManagerPrivate *priv = GSD_MEDIA_KEYS_MANAGER_GET_PRIVATE (manager);

        priv->bus_cancellable = g_cancellable_new ();
        g_bus_get (G_BUS_TYPE_SESSION,
                   priv->bus_cancellable,
                   (GAsyncReadyCallback) on_bus_gotten,
                   manager);
}
