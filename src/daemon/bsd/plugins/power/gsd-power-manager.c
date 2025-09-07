/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 8 -*-
 *
 * Copyright (C) 2007 William Jon McCann <mccann@jhu.edu>
 * Copyright (C) 2011-2012, 2015 Richard Hughes <richard@hughsie.com>
 * Copyright (C) 2011 Ritesh Khadgaray <khadgaray@gmail.com>
 * Copyright (C) 2012-2013 Red Hat Inc.
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

#include <stdlib.h>
#include <string.h>
#include <glib/gi18n.h>
#include <gtk/gtk.h>
#include <libupower-glib/upower.h>
#include <libnotify/notify.h>
#include <canberra-gtk.h>
#include <glib-unix.h>
#include <gio/gunixfdlist.h>

#define GNOME_DESKTOP_USE_UNSTABLE_API
#include <libgnome-desktop/gnome-idle-monitor.h>

#include <gsd-input-helper.h>

#include "gsd-power-constants.h"
#include "gsm-inhibitor-flag.h"
#include "gsm-presence-flag.h"
#include "gsm-manager-logout-mode.h"
#include "gpm-common.h"
#include "gsd-backlight.h"
#include "gnome-settings-profile.h"
#include "gnome-settings-bus.h"
#include "gnome-settings-daemon/gsd-enums.h"
#include "gsd-power-manager.h"

#include "gsd-display-config-glue.h"

#define GSD_DBUS_NAME "org.gnome.SettingsDaemon"
#define GSD_DBUS_PATH "/org/gnome/SettingsDaemon"
#define GSD_DBUS_BASE_INTERFACE "org.gnome.SettingsDaemon"

#define UPOWER_DBUS_NAME                        "org.freedesktop.UPower"
#define UPOWER_DBUS_PATH                        "/org/freedesktop/UPower"
#define UPOWER_DBUS_PATH_KBDBACKLIGHT           "/org/freedesktop/UPower/KbdBacklight"
#define UPOWER_DBUS_INTERFACE                   "org.freedesktop.UPower"
#define UPOWER_DBUS_INTERFACE_KBDBACKLIGHT      "org.freedesktop.UPower.KbdBacklight"

#define PPD_DBUS_NAME                           "org.freedesktop.UPower.PowerProfiles"
#define PPD_DBUS_PATH                           "/org/freedesktop/UPower/PowerProfiles"
#define PPD_DBUS_INTERFACE                      "org.freedesktop.UPower.PowerProfiles"

#define GSD_POWER_SETTINGS_SCHEMA               "org.gnome.settings-daemon.plugins.power"

#define GSD_POWER_DBUS_NAME                     GSD_DBUS_NAME ".Power"
#define GSD_POWER_DBUS_PATH                     GSD_DBUS_PATH "/Power"
#define GSD_POWER_DBUS_INTERFACE                GSD_DBUS_BASE_INTERFACE ".Power"
#define GSD_POWER_DBUS_INTERFACE_SCREEN         GSD_POWER_DBUS_INTERFACE ".Screen"
#define GSD_POWER_DBUS_INTERFACE_KEYBOARD       GSD_POWER_DBUS_INTERFACE ".Keyboard"

#define GSD_POWER_MANAGER_NOTIFY_TIMEOUT_SHORT          10 * 1000 /* ms */
#define GSD_POWER_MANAGER_NOTIFY_TIMEOUT_LONG           30 * 1000 /* ms */

#define SYSTEMD_DBUS_NAME                       "org.freedesktop.login1"
#define SYSTEMD_DBUS_PATH                       "/org/freedesktop/login1"
#define SYSTEMD_DBUS_INTERFACE                  "org.freedesktop.login1.Manager"

/* Time between notifying the user about a critical action and the action itself in UPower. */
#define GSD_ACTION_DELAY 20
/* And the time before we stop the warning sound */
#define GSD_STOP_SOUND_DELAY GSD_ACTION_DELAY - 2

/* The bandwidth of the low-pass filter used to smooth ambient light readings,
 * measured in Hz.  Smaller numbers result in smoother backlight changes.
 * Larger numbers are more responsive to abrupt changes in ambient light. */
#define GSD_AMBIENT_BANDWIDTH_HZ       0.1f

/* Convert bandwidth to time constant.  Units of constant are microseconds. */
#define GSD_AMBIENT_TIME_CONSTANT       (G_USEC_PER_SEC * 1.0f / (2.0f * G_PI * GSD_AMBIENT_BANDWIDTH_HZ))

static const gchar introspection_xml[] =
"<node>"
"  <interface name='org.gnome.SettingsDaemon.Power.Screen'>"
"    <property name='Brightness' type='i' access='readwrite'/>"
"    <method name='StepUp'>"
"      <arg type='i' name='new_percentage' direction='out'/>"
"      <arg type='s' name='connector' direction='out'/>"
"    </method>"
"    <method name='StepDown'>"
"      <arg type='i' name='new_percentage' direction='out'/>"
"      <arg type='s' name='connector' direction='out'/>"
"    </method>"
"    <method name='Cycle'>"
"      <arg type='i' name='new_percentage' direction='out'/>"
"      <arg type='i' name='output_id' direction='out'/>"
"    </method>"
"  </interface>"
"  <interface name='org.gnome.SettingsDaemon.Power.Keyboard'>"
"    <property name='Brightness' type='i' access='readwrite'/>"
"    <property name='Steps' type='i' access='read'/>"
"    <method name='StepUp'>"
"      <arg type='i' name='new_percentage' direction='out'/>"
"    </method>"
"    <method name='StepDown'>"
"      <arg type='i' name='new_percentage' direction='out'/>"
"    </method>"
"    <method name='Toggle'>"
"      <arg type='i' name='new_percentage' direction='out'/>"
"    </method>"
"    <signal name='BrightnessChanged'>"
"      <arg name='brightness' type='i'/>"
"      <arg name='source' type='s'/>"
"    </signal>"
"  </interface>"
"</node>";

typedef enum {
        GSD_POWER_IDLE_MODE_NORMAL,
        GSD_POWER_IDLE_MODE_DIM,
        GSD_POWER_IDLE_MODE_BLANK,
        GSD_POWER_IDLE_MODE_SLEEP
} GsdPowerIdleMode;

struct _GsdPowerManager
{
        GApplication             parent;

        /* D-Bus */
        GsdSessionManager       *session;
        guint                    name_id;
        GDBusNodeInfo           *introspection_data;
        GDBusConnection         *connection;
        GCancellable            *cancellable;

        /* Settings */
        GSettings               *settings;
        GSettings               *settings_bus;
        GSettings               *settings_screensaver;

        /* Screensaver */
        GsdScreenSaver          *screensaver_proxy;
        gboolean                 screensaver_active;

        /* State */
        gboolean                 lid_is_present;
        gboolean                 lid_is_closed;
        gboolean                 session_is_active;
        UpClient                *up_client;
        GPtrArray               *devices_array;
        UpDevice                *device_composite;
        NotifyNotification      *notification_ups_discharging;
        NotifyNotification      *notification_low;
        NotifyNotification      *notification_sleep_warning;
        GsdPowerActionType       sleep_action_type;
        GHashTable              *devices_notified_ht; /* key = serial str, value = UpDeviceLevel */
        gboolean                 battery_is_low; /* battery low, or UPS discharging */

        /* Brightness */
        GsdBacklight            *backlight;
        gint                     pre_dim_brightness; /* level, not percentage */

        /* Keyboard */
        GDBusProxy              *upower_kbd_proxy;
        gint                     kbd_brightness_now;
        gint                     kbd_brightness_max;
        gint                     kbd_brightness_old;
        gint                     kbd_brightness_pre_dim;

        /* Ambient */
        GDBusProxy              *iio_proxy;
        guint                    iio_proxy_watch_id;
        gboolean                 ambient_norm_required;
        gdouble                  ambient_accumulator;
        gdouble                  ambient_norm_value;
        gdouble                  ambient_percentage_old;
        gdouble                  ambient_last_absolute;
        gint64                   ambient_last_time;

        /* Power Profiles */
        GDBusProxy              *power_profiles_proxy;
        guint32                  power_saver_cookie;
        gboolean                 power_saver_enabled;

        /* Sound */
        guint32                  critical_alert_timeout_id;

        /* systemd stuff */
        GDBusProxy              *logind_proxy;
        gint                     inhibit_lid_switch_fd;
        gboolean                 inhibit_lid_switch_taken;
        gint                     inhibit_suspend_fd;
        gboolean                 inhibit_suspend_taken;
        guint                    inhibit_lid_switch_timer_id;
        gboolean                 is_virtual_machine;

        /* Idles */
        GnomeIdleMonitor        *idle_monitor;
        guint                    idle_dim_id;
        guint                    idle_blank_id;
        guint                    idle_sleep_warning_id;
        guint                    idle_sleep_id;
        guint                    user_active_id;
        GsdPowerIdleMode         current_idle_mode;

        guint                    temporary_unidle_on_ac_id;
        GsdPowerIdleMode         previous_idle_mode;

        guint                    xscreensaver_watchdog_timer_id;

        /* Device Properties */
        gboolean                 show_sleep_warnings;

        /* Screens */
        GsdDisplayConfig        *display_config;
};

enum {
        PROP_0,
};

static void     gsd_power_manager_class_init  (GsdPowerManagerClass *klass);
static void     gsd_power_manager_init        (GsdPowerManager      *power_manager);
static void     gsd_power_manager_startup     (GApplication *app);
static void     gsd_power_manager_shutdown    (GApplication *app);

static void      engine_device_warning_changed_cb (UpDevice *device, GParamSpec *pspec, GsdPowerManager *manager);
static void      do_power_action_type (GsdPowerManager *manager, GsdPowerActionType action_type);
static void      uninhibit_lid_switch (GsdPowerManager *manager);
static void      stop_inhibit_lid_switch_timer (GsdPowerManager *manager);
static void      sync_lid_inhibitor (GsdPowerManager *manager);
static void      main_battery_or_ups_low_changed (GsdPowerManager *manager, gboolean is_low);
static gboolean  idle_is_session_inhibited (GsdPowerManager *manager, GsmInhibitorFlag mask, gboolean *is_inhibited);
static void      idle_triggered_idle_cb (GnomeIdleMonitor *monitor, guint watch_id, gpointer user_data);
static void      idle_became_active_cb (GnomeIdleMonitor *monitor, guint watch_id, gpointer user_data);
static void      iio_proxy_changed (GsdPowerManager *manager);
static void      iio_proxy_changed_cb (GDBusProxy *proxy, GVariant *changed_properties, GStrv invalidated_properties, gpointer user_data);
static void      register_manager_dbus (GsdPowerManager *manager);

static void      initable_iface_init (GInitableIface *initable_iface);

G_DEFINE_TYPE_WITH_CODE (GsdPowerManager, gsd_power_manager, G_TYPE_APPLICATION,
                         G_IMPLEMENT_INTERFACE (G_TYPE_INITABLE, initable_iface_init))

GQuark
gsd_power_manager_error_quark (void)
{
        static GQuark quark = 0;
        if (!quark)
                quark = g_quark_from_static_string ("gsd_power_manager_error");
        return quark;
}

static void
notify_close_if_showing (NotifyNotification **notification)
{
        if (*notification == NULL)
                return;
        notify_notification_close (*notification, NULL);
        g_clear_object (notification);
}

static void
engine_device_add (GsdPowerManager *manager, UpDevice *device)
{
        UpDeviceKind kind;

        /* Batteries and UPSes are already handled through
         * the composite battery */
        g_object_get (device, "kind", &kind, NULL);
        if (kind == UP_DEVICE_KIND_BATTERY ||
            kind == UP_DEVICE_KIND_UPS ||
            kind == UP_DEVICE_KIND_LINE_POWER)
                return;
        g_ptr_array_add (manager->devices_array, g_object_ref (device));

        g_signal_connect (device, "notify::warning-level",
                          G_CALLBACK (engine_device_warning_changed_cb), manager);

        engine_device_warning_changed_cb (device, NULL, manager);
}

static gboolean
engine_coldplug (GsdPowerManager *manager)
{
        guint i;
        GPtrArray *array = NULL;
        UpDevice *device;

        /* add to database */
        array = up_client_get_devices2 (manager->up_client);

        for (i = 0 ; array != NULL && i < array->len ; i++) {
                device = g_ptr_array_index (array, i);
                engine_device_add (manager, device);
        }

        g_clear_pointer (&array, g_ptr_array_unref);

        /* never repeat */
        return FALSE;
}

static void
engine_device_added_cb (UpClient *client, UpDevice *device, GsdPowerManager *manager)
{
        engine_device_add (manager, device);
}

static void
engine_device_removed_cb (UpClient *client, const char *object_path, GsdPowerManager *manager)
{
        guint i;

        for (i = 0; i < manager->devices_array->len; i++) {
                UpDevice *device = g_ptr_array_index (manager->devices_array, i);

                if (g_strcmp0 (object_path, up_device_get_object_path (device)) == 0) {
                        g_ptr_array_remove_index (manager->devices_array, i);
                        break;
                }
        }
}

static void
on_notification_closed (NotifyNotification *notification, gpointer data)
{
    g_object_unref (notification);
}

/* See PrivacyScope in messageTray.js in gnome-shell. A notification with
 * ‘system’ scope has its detailed description shown in the lock screen. ‘user’
 * scope notifications don’t (because they could contain private information). */
typedef enum
{
        NOTIFICATION_PRIVACY_USER,
        NOTIFICATION_PRIVACY_SYSTEM,
} NotificationPrivacyScope;

static const gchar *
notification_privacy_scope_to_string (NotificationPrivacyScope scope)
{
        switch (scope) {
        case NOTIFICATION_PRIVACY_USER:
                return "user";
        case NOTIFICATION_PRIVACY_SYSTEM:
                return "system";
        default:
                g_assert_not_reached ();
        }
}

static void
create_notification (const char *summary,
                     const char *body,
                     const char *icon_name,
                     NotificationPrivacyScope privacy_scope,
                     NotifyNotification **weak_pointer_location)
{
        NotifyNotification *notification;

        notification = notify_notification_new (summary, body, NULL);
        /* TRANSLATORS: this is the notification application name */
        notify_notification_set_app_name (notification, _("Power"));
        notify_notification_set_hint_string (notification, "desktop-entry", "gnome-power-panel");
        notify_notification_set_hint_string (notification, "x-gnome-privacy-scope",
                                             notification_privacy_scope_to_string (privacy_scope));
        notify_notification_set_hint (notification, "image-path", g_variant_new_string (icon_name));
        notify_notification_set_urgency (notification,
                                         NOTIFY_URGENCY_CRITICAL);
        *weak_pointer_location = notification;
        g_object_add_weak_pointer (G_OBJECT (notification),
                                   (gpointer *) weak_pointer_location);
        g_signal_connect (notification, "closed",
                          G_CALLBACK (on_notification_closed), NULL);
}

static void
engine_ups_discharging (GsdPowerManager *manager, UpDevice *device)
{
        const gchar *title;
        gchar *remaining_text = NULL;
        gdouble percentage;
        gint64 time_to_empty;
        GString *message;
        UpDeviceKind kind;

        /* get device properties */
        g_object_get (device,
                      "kind", &kind,
                      "percentage", &percentage,
                      "time-to-empty", &time_to_empty,
                      NULL);

        if (kind != UP_DEVICE_KIND_UPS)
                return;

        /* only show text if there is a valid time */
        if (time_to_empty > 0)
                remaining_text = gpm_get_timestring (time_to_empty);

        /* TRANSLATORS: UPS is now discharging */
        title = _("UPS Discharging");

        message = g_string_new ("");
        if (remaining_text != NULL) {
                /* TRANSLATORS: tell the user how much time they have got */
                g_string_append_printf (message, _("%s of UPS backup power remaining"),
                                        remaining_text);
        } else {
                g_string_append (message, _("Unknown amount of UPS backup power remaining"));
        }
        g_string_append_printf (message, " (%.0f%%)", percentage);

        /* close any existing notification of this class */
        notify_close_if_showing (&manager->notification_ups_discharging);

        /* create a new notification */
        create_notification (title, message->str,
                             "battery-low-symbolic",
                             NOTIFICATION_PRIVACY_SYSTEM,
                             &manager->notification_ups_discharging);
        notify_notification_set_timeout (manager->notification_ups_discharging,
                                         GSD_POWER_MANAGER_NOTIFY_TIMEOUT_LONG);
        notify_notification_set_hint (manager->notification_ups_discharging,
                                      "transient", g_variant_new_boolean (TRUE));

        notify_notification_show (manager->notification_ups_discharging, NULL);

        g_string_free (message, TRUE);
        g_free (remaining_text);
}

static GsdPowerActionType
manager_critical_action_get (GsdPowerManager *manager)
{
        GsdPowerActionType policy;
        char *action;

        action = up_client_get_critical_action (manager->up_client);
        /* We don't make the difference between HybridSleep and Hibernate */
        if (g_strcmp0 (action, "PowerOff") == 0)
                policy = GSD_POWER_ACTION_SHUTDOWN;
        else
                policy = GSD_POWER_ACTION_HIBERNATE;
        g_free (action);
        return policy;
}

static gboolean
manager_critical_action_stop_sound_cb (GsdPowerManager *manager)
{
        /* stop playing the alert as it's too late to do anything now */
        play_loop_stop (&manager->critical_alert_timeout_id);

        return FALSE;
}

static gboolean
engine_device_debounce_warn (GsdPowerManager *manager,
                             UpDeviceKind kind,
                             UpDeviceLevel warning,
                             const char *serial)
{
        gpointer last_warning_ptr;
        UpDeviceLevel last_warning;
        gboolean ret = TRUE;

        if (!serial)
                return TRUE;

        if (kind == UP_DEVICE_KIND_BATTERY ||
            kind == UP_DEVICE_KIND_UPS)
                return TRUE;

        if (g_hash_table_lookup_extended (manager->devices_notified_ht, serial,
                                          NULL, &last_warning_ptr)) {
                last_warning = GPOINTER_TO_INT (last_warning_ptr);

                if (last_warning >= warning)
                        ret = FALSE;
        }

        if (warning != UP_DEVICE_LEVEL_UNKNOWN && warning != UP_DEVICE_LEVEL_NONE)
                g_hash_table_insert (manager->devices_notified_ht,
                                     g_strdup (serial),
                                     GINT_TO_POINTER (warning));

        return ret;
}

static const struct {
        UpDeviceKind kind;
        const char *title;
        const char *low_body_remain;
        const char *low_body;
        const char *low_body_unk;
        const char *crit_body;
        const char *crit_body_unk;
} peripheral_battery_notifications[] = {
        /* Intentionally skipped types (too uncommon, and name too imprecise):
         * UP_DEVICE_KIND_MODEM
         * UP_DEVICE_KIND_NETWORK
         * UP_DEVICE_KIND_VIDEO
         * UP_DEVICE_KIND_WEARABLE
         * UP_DEVICE_KIND_TOY
         */
        {
                .kind = UP_DEVICE_KIND_MOUSE,
                /* TRANSLATORS: notification title, a wireless mouse is low or very low on power */
                .title         = N_("Mouse battery low"),

                /* TRANSLATORS: notification body, a wireless mouse is low on power */
                .low_body      = N_("Wireless mouse is low on power (%.0f%%)"),
                .low_body_unk  = N_("Wireless mouse is low on power"),
                /* TRANSLATORS: notification body, a wireless mouse is very low on power */
                .crit_body     = N_("Wireless mouse is very low on power (%.0f%%). "
                                    "This device will soon stop functioning if not charged."),
                .crit_body_unk = N_("Wireless mouse is very low on power. "
                                    "This device will soon stop functioning if not charged."),
        }, {
                .kind = UP_DEVICE_KIND_KEYBOARD,
                /* TRANSLATORS: notification title, a wireless keyboard is low or very low on power */
                .title         = N_("Keyboard battery low"),

                /* TRANSLATORS: notification body, a wireless keyboard is low on power */
                .low_body      = N_("Wireless keyboard is low on power (%.0f%%)"),
                .low_body_unk  = N_("Wireless keyboard is low on power"),
                /* TRANSLATORS: notification body, a wireless keyboard is very low on power */
                .crit_body     = N_("Wireless keyboard is very low on power (%.0f%%). "
                                    "This device will soon stop functioning if not charged."),
                .crit_body_unk = N_("Wireless keyboard is very low on power. "
                                    "This device will soon stop functioning if not charged."),
        }, {
                .kind = UP_DEVICE_KIND_PDA,
                /* TRANSLATORS: notification title, a PDA (Personal Digital Assistance device) is low or very on power */
                .title         = N_("PDA battery low"),

                /* TRANSLATORS: notification body, a PDA (Personal Digital Assistance device) is low on power */
                .low_body      = N_("PDA is low on power (%.0f%%)"),
                .low_body_unk  = N_("PDA is low on power"),
                /* TRANSLATORS: notification body, a PDA (Personal Digital Assistance device) is very low on power */
                .crit_body     = N_("PDA is very low on power (%.0f%%). "
                                    "This device will soon stop functioning if not charged."),
                .crit_body_unk = N_("PDA is very low on power. "
                                    "This device will soon stop functioning if not charged."),
        }, {
                .kind = UP_DEVICE_KIND_PHONE,
                /* TRANSLATORS: notification title, a cell phone (mobile phone) is low or very low on power */
                .title         = N_("Cell phone battery low"),

                /* TRANSLATORS: notification body, a cell phone (mobile phone) is low on power */
                .low_body      = N_("Cell phone is low on power (%.0f%%)"),
                .low_body_unk  = N_("Cell phone is low on power"),
                /* TRANSLATORS: notification body, a cell phone (mobile phone) is very low on power */
                .crit_body     = N_("Cell phone is very low on power (%.0f%%). "
                                    "This device will soon stop functioning if not charged."),
                .crit_body_unk = N_("Cell phone is very low on power. "
                                    "This device will soon stop functioning if not charged."),
        }, {
                .kind = UP_DEVICE_KIND_MEDIA_PLAYER,
                /* TRANSLATORS: notification title, a media player (e.g. mp3 player) is low or very low on power */
                .title         = N_("Media player battery low"),

                /* TRANSLATORS: notification body, a media player (e.g. mp3 player) is low on power */
                .low_body      = N_("Media player is low on power (%.0f%%)"),
                .low_body_unk  = N_("Media player is low on power"),
                /* TRANSLATORS: notification body, a media player (e.g. mp3 player) is very low on power */
                .crit_body     = N_("Media player is very low on power (%.0f%%). "
                                    "This device will soon stop functioning if not charged."),
                .crit_body_unk = N_("Media player is very low on power. "
                                    "This device will soon stop functioning if not charged."),
        }, {
                .kind = UP_DEVICE_KIND_TABLET,
                /* TRANSLATORS: notification title, a graphics tablet (e.g. wacom) is low or very low on power */
                .title         = N_("Tablet battery low"),

                /* TRANSLATORS: notification body, a graphics tablet (e.g. wacom) is low on power */
                .low_body      = N_("Tablet is low on power (%.0f%%)"),
                .low_body_unk  = N_("Tablet is low on power"),
                /* TRANSLATORS: notification body, a graphics tablet (e.g. wacom) is very low on power */
                .crit_body     = N_("Tablet is very low on power (%.0f%%). "
                                    "This device will soon stop functioning if not charged."),
                .crit_body_unk = N_("Tablet is very low on power. "
                                    "This device will soon stop functioning if not charged."),
        }, {
                .kind = UP_DEVICE_KIND_COMPUTER,
                /* TRANSLATORS: notification title, an attached computer (e.g. ipad) is low or very low on power */
                .title         = N_("Attached computer battery low"),

                /* TRANSLATORS: notification body, an attached computer (e.g. ipad) is low on power */
                .low_body      = N_("Attached computer is low on power (%.0f%%)"),
                .low_body_unk  = N_("Attached computer is low on power"),
                /* TRANSLATORS: notification body, an attached computer (e.g. ipad) is very low on power */
                .crit_body     = N_("Attached computer is very low on power (%.0f%%). "
                                    "The device will soon shutdown if not charged."),
                .crit_body_unk = N_("Attached computer is very low on power. "
                                    "The device will soon shutdown if not charged."),
        }, {
                .kind = UP_DEVICE_KIND_GAMING_INPUT,
                /* TRANSLATORS: notification title, a game controller (e.g. joystick or joypad) is low or very low on power */
                .title         = N_("Game controller battery low"),

                /* TRANSLATORS: notification body, a game controller (e.g. joystick or joypad) is low on power */
                .low_body      = N_("Game controller is low on power (%.0f%%)"),
                .low_body_unk  = N_("Game controller is low on power"),
                /* TRANSLATORS: notification body, an attached game controller (e.g. joystick or joypad) is very low on power */
                .crit_body     = N_("Game controller is very low on power (%.0f%%). "
                                    "The device will soon shutdown if not charged."),
                .crit_body_unk = N_("Game controller is very low on power. "
                                    "The device will soon shutdown if not charged."),
        }, {
                .kind = UP_DEVICE_KIND_PEN,
                /* TRANSLATORS: notification title, a pen is low or very low on power */
                .title         = N_("Pen battery low"),

                /* TRANSLATORS: notification body, a pen is low on power */
                .low_body      = N_("Pen is low on power (%.0f%%)"),
                .low_body_unk  = N_("Pen is low on power"),
                /* TRANSLATORS: notification body, a pen is very low on power */
                .crit_body     = N_("Pen is very low on power (%.0f%%). "
                                    "The device will soon shutdown if not charged."),
                .crit_body_unk = N_("Pen is very low on power. "
                                    "The device will soon shutdown if not charged."),
        }, {
                .kind = UP_DEVICE_KIND_TOUCHPAD,
                /* TRANSLATORS: notification title, an external touchpad is low or very low on power */
                .title         = N_("Touchpad battery low"),

                /* TRANSLATORS: notification body, an external touchpad is low on power */
                .low_body      = N_("Touchpad is low on power (%.0f%%)"),
                .low_body_unk  = N_("Touchpad is low on power"),
                /* TRANSLATORS: notification body, an external touchpad is very low on power */
                .crit_body     = N_("Touchpad is very low on power (%.0f%%). "
                                    "The device will soon shutdown if not charged."),
                .crit_body_unk = N_("Touchpad is very low on power. "
                                    "The device will soon shutdown if not charged."),
        }, {
                .kind = UP_DEVICE_KIND_HEADSET,
                /* TRANSLATORS: notification title, a headset (headphones + microphone) is low or very low on power */
                .title         = N_("Headset battery low"),

                /* TRANSLATORS: notification body, a headset (headphones + microphone) is low on power */
                .low_body      = N_("Headset is low on power (%.0f%%)"),
                .low_body_unk  = N_("Headset is low on power"),
                /* TRANSLATORS: notification body, a headset (headphones + microphone) is very low on power */
                .crit_body     = N_("Headset is very low on power (%.0f%%). "
                                    "The device will soon shutdown if not charged."),
                .crit_body_unk = N_("Headset is very low on power. "
                                    "The device will soon shutdown if not charged."),
        }, {
                .kind = UP_DEVICE_KIND_SPEAKERS,
                /* TRANSLATORS: notification title, speaker is low or very low on power */
                .title         = N_("Speaker battery low"),

                /* TRANSLATORS: notification body, a speaker is low on power */
                .low_body      = N_("Speaker is low on power (%.0f%%)"),
                .low_body_unk  = N_("Speaker is low on power"),
                /* TRANSLATORS: notification body, a speaker is very low on power */
                .crit_body     = N_("Speaker is very low on power (%.0f%%). "
                                    "The device will soon shutdown if not charged."),
                .crit_body_unk = N_("Speaker is very low on power. "
                                    "The device will soon shutdown if not charged."),
        }, {
                .kind = UP_DEVICE_KIND_HEADPHONES,
                /* TRANSLATORS: notification title, headphones (no microphone) are low or very low on power */
                .title         = N_("Headphones battery low"),

                /* TRANSLATORS: notification body, headphones (no microphone) are low on power */
                .low_body      = N_("Headphones are low on power (%.0f%%)"),
                .low_body_unk  = N_("Headphones are low on power"),
                /* TRANSLATORS: notification body, headphones (no microphone) are very low on power */
                .crit_body     = N_("Headphones are very low on power (%.0f%%). "
                                    "The device will soon shutdown if not charged."),
                .crit_body_unk = N_("Headphones are very low on power. "
                                    "The device will soon shutdown if not charged."),
        }, {
                .kind = UP_DEVICE_KIND_OTHER_AUDIO,
                /* TRANSLATORS: notification title, an audio device is low or very low on power */
                .title         = N_("Audio device battery low"),

                /* TRANSLATORS: notification body, an audio device is low on power */
                .low_body      = N_("Audio device is low on power (%.0f%%)"),
                .low_body_unk  = N_("Audio device is low on power"),
                /* TRANSLATORS: notification body, an audio device is very low on power */
                .crit_body     = N_("Audio device is very low on power (%.0f%%). "
                                    "The device will soon shutdown if not charged."),
                .crit_body_unk = N_("Audio device is very low on power. "
                                    "The device will soon shutdown if not charged."),
        }, {
                .kind = UP_DEVICE_KIND_REMOTE_CONTROL,
                /* TRANSLATORS: notification title, a remote control is low or very low on power */
                .title         = N_("Remote battery low"),

                /* TRANSLATORS: notification body, an remote control is low on power */
                .low_body      = N_("Remote is low on power (%.0f%%)"),
                .low_body_unk  = N_("Remote is low on power"),
                /* TRANSLATORS: notification body, a remote control is very low on power */
                .crit_body     = N_("Remote is very low on power (%.0f%%). "
                                    "The device will soon shutdown if not charged."),
                .crit_body_unk = N_("Remote is very low on power. "
                                    "The device will soon shutdown if not charged."),
        }, {
                .kind = UP_DEVICE_KIND_PRINTER,
                /* TRANSLATORS: notification title, a printer is low or very low on power */
                .title         = N_("Printer battery low"),

                /* TRANSLATORS: notification body, a printer is low on power */
                .low_body      = N_("Printer is low on power (%.0f%%)"),
                .low_body_unk  = N_("Printer is low on power"),
                /* TRANSLATORS: notification body, a printer is very low on power */
                .crit_body     = N_("Printer is very low on power (%.0f%%). "
                                    "The device will soon shutdown if not charged."),
                .crit_body_unk = N_("Printer is very low on power. "
                                    "The device will soon shutdown if not charged."),
        }, {
                .kind = UP_DEVICE_KIND_SCANNER,
                /* TRANSLATORS: notification title, a scanner is low or very low on power */
                .title         = N_("Scanner battery low"),

                /* TRANSLATORS: notification body, a scanner is low on power */
                .low_body      = N_("Scanner is low on power (%.0f%%)"),
                .low_body_unk  = N_("Scanner is low on power"),
                /* TRANSLATORS: notification body, a scanner is very low on power */
                .crit_body     = N_("Scanner is very low on power (%.0f%%). "
                                    "The device will soon shutdown if not charged."),
                .crit_body_unk = N_("Scanner is very low on power. "
                                    "The device will soon shutdown if not charged."),
        }, {
                .kind = UP_DEVICE_KIND_CAMERA,
                /* TRANSLATORS: notification title, a camera is low or very low on power */
                .title         = N_("Camera battery low"),

                /* TRANSLATORS: notification body, a camera is low on power */
                .low_body      = N_("Camera is low on power (%.0f%%)"),
                .low_body_unk  = N_("Camera is low on power"),
                /* TRANSLATORS: notification body, a camera is very low on power */
                .crit_body     = N_("Camera is very low on power (%.0f%%). "
                                    "The device will soon shutdown if not charged."),
                .crit_body_unk = N_("Camera is very low on power. "
                                    "The device will soon shutdown if not charged."),
        }, {
                .kind = UP_DEVICE_KIND_BLUETOOTH_GENERIC,
                /* TRANSLATORS: notification title, a Bluetooth device is low or very low on power */
                .title         = N_("Bluetooth device battery low"),

                /* TRANSLATORS: notification body, a Bluetooth device is low on power */
                .low_body      = N_("Bluetooth device is low on power (%.0f%%)"),
                .low_body_unk  = N_("Bluetooth device is low on power"),
                /* TRANSLATORS: notification body, a Bluetooth device is very low on power */
                .crit_body     = N_("Bluetooth device is very low on power (%.0f%%). "
                                    "The device will soon shutdown if not charged."),
                .crit_body_unk = N_("Bluetooth device is very low on power. "
                                    "The device will soon shutdown if not charged."),
        }, {
                /* Last entry is the fallback (kind is actually unused)! */
                .kind = UP_DEVICE_KIND_UNKNOWN,
                /* TRANSLATORS: notification title, a connected (wireless) device or peripheral of unhandled type is low or very on power */
                .title         = N_("Connected device battery is low"),

                /* TRANSLATORS: notification body, a connected (wireless) device or peripheral of unhandled type is low on power */
                .low_body      = N_("A connected device is low on power (%.0f%%)"),
                .low_body_unk  = N_("A connected device is low on power"),
                /* TRANSLATORS: notification body, a connected (wireless) device or peripheral of unhandled type is very low on power */
                .crit_body     = N_("A connected device is very low on power (%.0f%%). "
                                    "The device will soon shutdown if not charged."),
                .crit_body_unk = N_("A connected device is very low on power. "
                                    "The device will soon shutdown if not charged."),
        }
};

static void
engine_charge_low (GsdPowerManager *manager, UpDevice *device)
{
        const gchar *title = NULL;
        gchar *message = NULL;
        gdouble percentage;
        guint battery_level;
        UpDeviceKind kind;

        /* get device properties */
        g_object_get (device,
                      "kind", &kind,
                      "percentage", &percentage,
                      "battery-level", &battery_level,
                      NULL);

        if (battery_level == UP_DEVICE_LEVEL_UNKNOWN)
                battery_level = UP_DEVICE_LEVEL_NONE;

        if (kind == UP_DEVICE_KIND_BATTERY) {
                /* TRANSLATORS: notification title, the battery of this laptop/tablet/phone is running low, shows percentage remaining */
                title = _("Low Battery");

                /* TRANSLATORS: notification body, the battery of this laptop/tablet/phone is running low, shows percentage remaining */
                message = g_strdup_printf (_("%.0f%% battery remaining"), percentage);
        } else if (kind == UP_DEVICE_KIND_UPS) {
                /* TRANSLATORS: notification title, an Uninterruptible Power Supply (UPS) is running low, shows percentage remaining */
                title = _("UPS Low");

                /* TRANSLATORS: notification body, an Uninterruptible Power Supply (UPS) is running low, shows percentage remaining */
                message = g_strdup_printf (_("%.0f%% UPS power remaining"), percentage);
        } else {
                guint i;

                for (i = 0; i < G_N_ELEMENTS (peripheral_battery_notifications); i++) {
                        if (peripheral_battery_notifications[i].kind == kind)
                                break;
                }
                /* Use the last element if nothing was found*/
                i = MIN (i, G_N_ELEMENTS (peripheral_battery_notifications) - 1);

                title = gettext (peripheral_battery_notifications[i].title);

                if (battery_level == UP_DEVICE_LEVEL_NONE)
                        message = g_strdup_printf (gettext (peripheral_battery_notifications[i].low_body), percentage);
                else
                        message = g_strdup (gettext (peripheral_battery_notifications[i].low_body_unk));
        }

        /* close any existing notification of this class */
        notify_close_if_showing (&manager->notification_low);

        /* create a new notification */
        create_notification (title, message,
                             "battery-low-symbolic",
                             NOTIFICATION_PRIVACY_SYSTEM,
                             &manager->notification_low);
        notify_notification_set_timeout (manager->notification_low,
                                         GSD_POWER_MANAGER_NOTIFY_TIMEOUT_LONG);
        notify_notification_set_hint (manager->notification_low,
                                      "transient", g_variant_new_boolean (TRUE));

        notify_notification_show (manager->notification_low, NULL);

        /* play the sound, using sounds from the naming spec */
        ca_context_play (ca_gtk_context_get (), 0,
                         CA_PROP_EVENT_ID, "battery-low",
                         /* TRANSLATORS: this is the sound description */
                         CA_PROP_EVENT_DESCRIPTION, _("Battery is low"), NULL);

        g_free (message);
}

static void
engine_charge_critical (GsdPowerManager *manager, UpDevice *device)
{
        const gchar *title = NULL;
        gchar *message = NULL;
        gdouble percentage;
        guint battery_level;
        UpDeviceKind kind;

        /* get device properties */
        g_object_get (device,
                      "kind", &kind,
                      "percentage", &percentage,
                      "battery-level", &battery_level,
                      NULL);

        if (battery_level == UP_DEVICE_LEVEL_UNKNOWN)
                battery_level = UP_DEVICE_LEVEL_NONE;

        if (kind == UP_DEVICE_KIND_BATTERY) {
                /* TRANSLATORS: notification title, the battery of this laptop/tablet/phone is critically low, advice on what the user should do */
                title = _("Battery Almost Empty");

                /* TRANSLATORS: notification body, the battery of this laptop/tablet/phone is critically running low, advice on what the user should do */
                message = g_strdup_printf (_("Connect power now"));
        } else if (kind == UP_DEVICE_KIND_UPS) {
                /* TRANSLATORS: notification title, an Uninterruptible Power Supply (UPS) is running low, warning about action happening soon */
                title = _("UPS Almost Empty");

                /* TRANSLATORS: notification body, an Uninterruptible Power Supply (UPS) is running low, warning about action happening soon */
                message = g_strdup_printf (_("%.0f%% UPS power remaining"), percentage);
        } else {
                guint i;

                for (i = 0; i < G_N_ELEMENTS (peripheral_battery_notifications); i++) {
                        if (peripheral_battery_notifications[i].kind == kind)
                                break;
                }
                /* Use the last element if nothing was found*/
                i = MIN (i, G_N_ELEMENTS (peripheral_battery_notifications) - 1);

                title = gettext (peripheral_battery_notifications[i].title);

                if (battery_level == UP_DEVICE_LEVEL_NONE)
                        message = g_strdup_printf (gettext (peripheral_battery_notifications[i].crit_body), percentage);
                else
                        message = g_strdup (gettext (peripheral_battery_notifications[i].crit_body_unk));
        }

        /* close any existing notification of this class */
        notify_close_if_showing (&manager->notification_low);

        /* create a new notification */
        create_notification (title, message,
                             "battery-caution-symbolic",
                             NOTIFICATION_PRIVACY_SYSTEM,
                             &manager->notification_low);
        notify_notification_set_timeout (manager->notification_low,
                                         NOTIFY_EXPIRES_NEVER);

        notify_notification_show (manager->notification_low, NULL);

        switch (kind) {

        case UP_DEVICE_KIND_BATTERY:
        case UP_DEVICE_KIND_UPS:
                g_debug ("critical charge level reached, starting sound loop");
                play_loop_start (&manager->critical_alert_timeout_id);
                break;

        default:
                /* play the sound, using sounds from the naming spec */
                ca_context_play (ca_gtk_context_get (), 0,
                                 CA_PROP_EVENT_ID, "battery-caution",
                                 /* TRANSLATORS: this is the sound description */
                                 CA_PROP_EVENT_DESCRIPTION, _("Battery is critically low"), NULL);
                break;
        }

        g_free (message);
}

static void
engine_charge_action (GsdPowerManager *manager, UpDevice *device)
{
        const gchar *title = NULL;
        gchar *message = NULL;
        GsdPowerActionType policy;
        guint timer_id;
        UpDeviceKind kind;

        /* get device properties */
        g_object_get (device,
                      "kind", &kind,
                      NULL);

        if (kind == UP_DEVICE_KIND_BATTERY) {
                /* TRANSLATORS: notification title, the battery of this laptop/tablet/phone is critically low, warning about action happening now */
                title = _("Battery is Empty");

                /* we have to do different warnings depending on the policy */
                policy = manager_critical_action_get (manager);

                if (policy == GSD_POWER_ACTION_HIBERNATE) {
                        /* TRANSLATORS: notification body, the battery of this laptop/tablet/phone is critically low, warning about action about to happen */
                        message = g_strdup (_("This device is about to hibernate"));
                } else if (policy == GSD_POWER_ACTION_SHUTDOWN) {
                        message = g_strdup (_("This device is about to shutdown"));
                }

                /* wait 20 seconds for user-panic */
                timer_id = g_timeout_add_seconds (GSD_STOP_SOUND_DELAY,
                                                  (GSourceFunc) manager_critical_action_stop_sound_cb,
                                                  manager);
                g_source_set_name_by_id (timer_id, "[GsdPowerManager] battery critical-action");

        } else if (kind == UP_DEVICE_KIND_UPS) {
                /* TRANSLATORS: notification title, an Uninterruptible Power Supply (UPS) is critically low, warning about action about to happen */
                title = _("UPS is Empty");

                /* we have to do different warnings depending on the policy */
                policy = manager_critical_action_get (manager);

                if (policy == GSD_POWER_ACTION_HIBERNATE) {
                        /* TRANSLATORS: notification body, an Uninterruptible Power Supply (UPS) is critically low, warning about action about to happen */
                        message = g_strdup (_("This device is about to hibernate"));
                } else if (policy == GSD_POWER_ACTION_SHUTDOWN) {
                        message = g_strdup (_("This device is about to shutdown"));
                }

                /* wait 20 seconds for user-panic */
                timer_id = g_timeout_add_seconds (GSD_STOP_SOUND_DELAY,
                                                  (GSourceFunc) manager_critical_action_stop_sound_cb,
                                                  manager);
                g_source_set_name_by_id (timer_id, "[GsdPowerManager] ups critical-action");
        }

        /* not all types have actions */
        if (title == NULL)
                return;

        /* close any existing notification of this class */
        notify_close_if_showing (&manager->notification_low);

        /* create a new notification */
        create_notification (title, message,
                             "battery-action-symbolic",
                             NOTIFICATION_PRIVACY_SYSTEM,
                             &manager->notification_low);
        notify_notification_set_timeout (manager->notification_low,
                                         NOTIFY_EXPIRES_NEVER);

        /* try to show */
        notify_notification_show (manager->notification_low, NULL);

        /* play the sound, using sounds from the naming spec */
        ca_context_play (ca_gtk_context_get (), 0,
                         CA_PROP_EVENT_ID, "battery-caution",
                         /* TRANSLATORS: this is the sound description */
                         CA_PROP_EVENT_DESCRIPTION, _("Battery is critically low"), NULL);

        g_free (message);
}

static void
engine_device_warning_changed_cb (UpDevice *device, GParamSpec *pspec, GsdPowerManager *manager)
{
        g_autofree char *serial = NULL;
        UpDeviceLevel warning;
        UpDeviceKind kind;

        g_object_get (device,
                      "serial", &serial,
                      "warning-level", &warning,
                      "kind", &kind,
                      NULL);

        if (!engine_device_debounce_warn (manager, kind, warning, serial))
                return;

        if (warning == UP_DEVICE_LEVEL_DISCHARGING) {
                g_debug ("** EMIT: discharging");
                engine_ups_discharging (manager, device);
        } else if (warning == UP_DEVICE_LEVEL_LOW) {
                g_debug ("** EMIT: charge-low");
                engine_charge_low (manager, device);
        } else if (warning == UP_DEVICE_LEVEL_CRITICAL) {
                g_debug ("** EMIT: charge-critical");
                engine_charge_critical (manager, device);
        } else if (warning == UP_DEVICE_LEVEL_ACTION) {
                g_debug ("** EMIT: charge-action");
                engine_charge_action (manager, device);
        } else if (warning == UP_DEVICE_LEVEL_NONE) {
                /* FIXME: this only handles one notification
                 * for the whole system, instead of one per device */
                g_debug ("fully charged or charging, hiding notifications if any");
                play_loop_stop (&manager->critical_alert_timeout_id);
                if (kind != UP_DEVICE_KIND_UPS)
                        notify_close_if_showing (&manager->notification_low);
                else
                        notify_close_if_showing (&manager->notification_ups_discharging);
        }

        if (kind == UP_DEVICE_KIND_BATTERY ||
            kind == UP_DEVICE_KIND_UPS)
                main_battery_or_ups_low_changed (manager, (warning != UP_DEVICE_LEVEL_NONE));
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
                g_warning ("couldn't shutdown using gnome-session: %s",
                           error->message);
                g_error_free (error);
        } else {
                g_variant_unref (result);
        }
}

static void
gnome_session_shutdown (GsdPowerManager *manager)
{
        g_dbus_proxy_call (G_DBUS_PROXY (manager->session),
                           "Shutdown",
                           NULL,
                           G_DBUS_CALL_FLAGS_NONE,
                           -1, NULL,
                           gnome_session_shutdown_cb, NULL);
}

static void
gnome_session_logout_cb (GObject *source_object,
                         GAsyncResult *res,
                         gpointer user_data)
{
        GVariant *result;
        GError *error = NULL;

        result = g_dbus_proxy_call_finish (G_DBUS_PROXY (source_object),
                                           res,
                                           &error);
        if (result == NULL) {
                g_warning ("couldn't log out using gnome-session: %s",
                           error->message);
                g_error_free (error);
        } else {
                g_variant_unref (result);
        }
}

static void
gnome_session_logout (GsdPowerManager *manager,
                      guint            logout_mode)
{
        if (g_getenv ("RUNNING_UNDER_GDM")) {
                g_warning ("Prevented logout from GDM session! This indicates an issue in gsd-power.");
                return;
        }

        g_dbus_proxy_call (G_DBUS_PROXY (manager->session),
                           "Logout",
                           g_variant_new ("(u)", logout_mode),
                           G_DBUS_CALL_FLAGS_NONE,
                           -1, NULL,
                           gnome_session_logout_cb, NULL);
}

static void
dbus_call_log_error (GObject *source_object,
                     GAsyncResult *res,
                     gpointer user_data)
{
        g_autoptr(GVariant) result = NULL;
        g_autoptr(GError) error = NULL;
        const gchar *msg = user_data;

        result = g_dbus_proxy_call_finish (G_DBUS_PROXY (source_object),
                                           res,
                                           &error);
        if (result == NULL)
                g_warning ("%s: %s", msg, error->message);
}

static void
action_poweroff (GsdPowerManager *manager)
{
        if (manager->logind_proxy == NULL) {
                g_warning ("no systemd support");
                return;
        }
        g_dbus_proxy_call (manager->logind_proxy,
                           "PowerOff",
                           g_variant_new ("(b)", FALSE),
                           G_DBUS_CALL_FLAGS_NONE,
                           G_MAXINT,
                           NULL,
                           dbus_call_log_error,
                           "Error calling PowerOff");
}

static void
action_suspend (GsdPowerManager *manager)
{
        if (manager->logind_proxy == NULL) {
                g_warning ("no systemd support");
                return;
        }
        g_dbus_proxy_call (manager->logind_proxy,
                           "Suspend",
                           g_variant_new ("(b)", FALSE),
                           G_DBUS_CALL_FLAGS_NONE,
                           G_MAXINT,
                           NULL,
                           dbus_call_log_error,
                           "Error calling suspend action");
}

static void
action_hibernate (GsdPowerManager *manager)
{
        if (manager->logind_proxy == NULL) {
                g_warning ("no systemd support");
                return;
        }
        g_dbus_proxy_call (manager->logind_proxy,
                           "Hibernate",
                           g_variant_new ("(b)", FALSE),
                           G_DBUS_CALL_FLAGS_NONE,
                           G_MAXINT,
                           NULL,
                           dbus_call_log_error,
                           "Error calling Hibernate");
}


static void
light_claimed_cb (GObject      *source_object,
                  GAsyncResult *res,
                  gpointer      user_data)
{
        GsdPowerManager *manager = user_data;
        g_autoptr(GError) error = NULL;
        g_autoptr(GVariant) result = NULL;

        result = g_dbus_proxy_call_finish (G_DBUS_PROXY (source_object),
                                           res,
                                           &error);
        if (result == NULL) {
                g_warning ("Claiming light sensor failed: %s", error->message);
                return;
        }
        iio_proxy_changed (manager);
}


static void
light_released_cb (GObject      *source_object,
                   GAsyncResult *res,
                   gpointer      user_data)
{
        g_autoptr(GError) error = NULL;
        g_autoptr(GVariant) result = NULL;

        result = g_dbus_proxy_call_finish (G_DBUS_PROXY (source_object),
                                           res,
                                           &error);
        if (result == NULL) {
                g_warning ("Release of light sensors failed: %s", error->message);
                return;
        }
}


static void
iio_proxy_claim_light (GsdPowerManager *manager, gboolean active)
{
        if (manager->iio_proxy == NULL)
                return;
        if (!manager->backlight)
                return;
	if (active && !manager->session_is_active)
		return;

        /* FIXME:
         * Remove when iio-sensor-proxy sends events only to clients instead
         * of all listeners:
         * https://github.com/hadess/iio-sensor-proxy/issues/210 */

        /* disconnect, otherwise callback can be added multiple times */
        g_signal_handlers_disconnect_by_func (manager->iio_proxy,
                                              G_CALLBACK (iio_proxy_changed_cb),
                                              manager);

        if (active)
                g_signal_connect (manager->iio_proxy, "g-properties-changed",
                                  G_CALLBACK (iio_proxy_changed_cb), manager);

        g_dbus_proxy_call (manager->iio_proxy,
                           active ? "ClaimLight" : "ReleaseLight",
                           NULL,
                           G_DBUS_CALL_FLAGS_NONE,
                           -1,
                           manager->cancellable,
                           active ? light_claimed_cb : light_released_cb,
                           manager);
}

typedef enum {
        GSD_POWER_SAVE_MODE_ON = 0,
        GSD_POWER_SAVE_MODE_STANDBY = 1,
        GSD_POWER_SAVE_MODE_SUSPEND = 2,
        GSD_POWER_SAVE_MODE_OFF = 3,
        GSD_POWER_SAVE_MODE_UNKNOWN = -1,
} GsdPowerSaveMode;

static void
set_power_saving_mode (GsdPowerManager  *manager,
                       GsdPowerSaveMode  mode)
{
        GsdDisplayConfig *display_config =
                gnome_settings_bus_get_display_config_proxy ();

        gsd_display_config_set_power_save_mode (display_config, mode);
}

static void
backlight_enable (GsdPowerManager *manager)
{
        iio_proxy_claim_light (manager, TRUE);
        set_power_saving_mode (manager, GSD_POWER_SAVE_MODE_ON);

        g_debug ("TESTSUITE: Unblanked screen");
}

static void
backlight_disable (GsdPowerManager *manager)
{
        iio_proxy_claim_light (manager, FALSE);
        set_power_saving_mode (manager, GSD_POWER_SAVE_MODE_OFF);

        g_debug ("TESTSUITE: Blanked screen");
}

static void
do_power_action_type (GsdPowerManager *manager,
                      GsdPowerActionType action_type)
{
        switch (action_type) {
        case GSD_POWER_ACTION_SUSPEND:
                action_suspend (manager);
                break;
        case GSD_POWER_ACTION_INTERACTIVE:
                gnome_session_shutdown (manager);
                break;
        case GSD_POWER_ACTION_HIBERNATE:
                action_hibernate (manager);
                break;
        case GSD_POWER_ACTION_SHUTDOWN:
                /* this is only used on critically low battery where
                 * hibernate is not available and is marginally better
                 * than just powering down the computer mid-write */
                action_poweroff (manager);
                break;
        case GSD_POWER_ACTION_BLANK:
                backlight_disable (manager);
                break;
        case GSD_POWER_ACTION_NOTHING:
                break;
        case GSD_POWER_ACTION_LOGOUT:
                gnome_session_logout (manager, GSM_MANAGER_LOGOUT_MODE_FORCE);
                break;
        }
}

static GsmInhibitorFlag
get_idle_inhibitors_for_action (GsdPowerActionType action_type)
{
        switch (action_type) {
        case GSD_POWER_ACTION_BLANK:
        case GSD_POWER_ACTION_SHUTDOWN:
        case GSD_POWER_ACTION_INTERACTIVE:
                return GSM_INHIBITOR_FLAG_IDLE;
        case GSD_POWER_ACTION_HIBERNATE:
        case GSD_POWER_ACTION_SUSPEND:
                return GSM_INHIBITOR_FLAG_SUSPEND; /* in addition to idle */
        case GSD_POWER_ACTION_NOTHING:
                return 0;
        case GSD_POWER_ACTION_LOGOUT:
                return GSM_INHIBITOR_FLAG_LOGOUT; /* in addition to idle */
        }
        return 0;
}

static gboolean
is_action_inhibited (GsdPowerManager *manager, GsdPowerActionType action_type)
{
        GsmInhibitorFlag flag;
        gboolean is_inhibited;

        flag = get_idle_inhibitors_for_action (action_type);
        if (!flag)
                return FALSE;
        idle_is_session_inhibited (manager,
                                   flag,
                                   &is_inhibited);
        return is_inhibited;
}

static gboolean
upower_kbd_set_brightness (GsdPowerManager *manager, guint value, GError **error)
{
        GVariant *retval;

        /* same as before */
        if (manager->kbd_brightness_now == value)
                return TRUE;
        if (manager->upower_kbd_proxy == NULL)
                return TRUE;

        /* update h/w value */
        retval = g_dbus_proxy_call_sync (manager->upower_kbd_proxy,
                                         "SetBrightness",
                                         g_variant_new ("(i)", (gint) value),
                                         G_DBUS_CALL_FLAGS_NONE,
                                         -1,
                                         manager->cancellable,
                                         error);
        if (retval == NULL)
                return FALSE;

        /* save new value */
        manager->kbd_brightness_now = value;
        g_variant_unref (retval);
        return TRUE;
}

static int
upower_kbd_toggle (GsdPowerManager *manager,
                   GError **error)
{
        gboolean ret;
        int value = -1;

        if (manager->kbd_brightness_old >= 0) {
                g_debug ("keyboard toggle off");
                ret = upower_kbd_set_brightness (manager,
                                                 manager->kbd_brightness_old,
                                                 error);
                if (ret) {
                        /* succeeded, set to -1 since now no old value */
                        manager->kbd_brightness_old = -1;
                        value = 0;
                }
        } else {
                g_debug ("keyboard toggle on");
                /* save the current value to restore later when untoggling */
                manager->kbd_brightness_old = manager->kbd_brightness_now;
                ret = upower_kbd_set_brightness (manager, 0, error);
                if (!ret) {
                        /* failed, reset back to -1 */
                        manager->kbd_brightness_old = -1;
                } else {
                        value = 0;
                }
        }

        if (ret)
                return value;
        return -1;
}

static gboolean
suspend_on_lid_close (GsdPowerManager *manager)
{
        return !external_monitor_is_connected () || !manager->session_is_active;
}

static gboolean
inhibit_lid_switch_timer_cb (GsdPowerManager *manager)
{
        stop_inhibit_lid_switch_timer (manager);

        if (suspend_on_lid_close (manager)) {
                g_debug ("no external monitors or session inactive for a while; uninhibiting lid close");
                uninhibit_lid_switch (manager);
        }

        /* This is a one shot timer. */
        return G_SOURCE_REMOVE;
}

/* Sets up a timer to be triggered some seconds after closing the laptop lid
 * when the laptop is *not* suspended for some reason.  We'll check conditions
 * again in the timeout handler to see if we can suspend then.
 */
static void
setup_inhibit_lid_switch_timer (GsdPowerManager *manager)
{
        if (manager->inhibit_lid_switch_timer_id != 0) {
                g_debug ("lid close safety timer already set up");
                return;
        }

        g_debug ("setting up lid close safety timer");

        manager->inhibit_lid_switch_timer_id = g_timeout_add_seconds (LID_CLOSE_SAFETY_TIMEOUT,
                                                                            (GSourceFunc) inhibit_lid_switch_timer_cb,
                                                                            manager);
        g_source_set_name_by_id (manager->inhibit_lid_switch_timer_id, "[GsdPowerManager] lid close safety timer");
}

static void
stop_inhibit_lid_switch_timer (GsdPowerManager *manager) {
        if (manager->inhibit_lid_switch_timer_id != 0) {
                g_debug ("stopping lid close safety timer");
                g_source_remove (manager->inhibit_lid_switch_timer_id);
                manager->inhibit_lid_switch_timer_id = 0;
        }
}

static void
restart_inhibit_lid_switch_timer (GsdPowerManager *manager)
{
        stop_inhibit_lid_switch_timer (manager);
        g_debug ("restarting lid close safety timer");
        setup_inhibit_lid_switch_timer (manager);
}

static void
do_lid_open_action (GsdPowerManager *manager)
{
        /* play a sound, using sounds from the naming spec */
        ca_context_play (ca_gtk_context_get (), 0,
                         CA_PROP_EVENT_ID, "lid-open",
                         /* TRANSLATORS: this is the sound description */
                         CA_PROP_EVENT_DESCRIPTION, _("Lid has been opened"),
                         NULL);
}

static void
lock_screensaver (GsdPowerManager *manager)
{
        gboolean do_lock;

        do_lock = g_settings_get_boolean (manager->settings_screensaver,
                                          "lock-enabled");
        if (!do_lock) {
                g_dbus_proxy_call_sync (G_DBUS_PROXY (manager->screensaver_proxy),
                                        "SetActive",
                                        g_variant_new ("(b)", TRUE),
                                        G_DBUS_CALL_FLAGS_NONE,
                                        -1, NULL, NULL);
                return;
        }

        g_dbus_proxy_call_sync (G_DBUS_PROXY (manager->screensaver_proxy),
                                "Lock",
                                NULL,
                                G_DBUS_CALL_FLAGS_NONE,
                                -1, NULL, NULL);
}

static void
do_lid_closed_action (GsdPowerManager *manager)
{
        /* play a sound, using sounds from the naming spec */
        ca_context_play (ca_gtk_context_get (), 0,
                         CA_PROP_EVENT_ID, "lid-close",
                         /* TRANSLATORS: this is the sound description */
                         CA_PROP_EVENT_DESCRIPTION, _("Lid has been closed"),
                         NULL);

        if (suspend_on_lid_close (manager)) {
                gboolean is_inhibited;

                idle_is_session_inhibited (manager,
                                           GSM_INHIBITOR_FLAG_SUSPEND,
                                           &is_inhibited);
                if (is_inhibited) {
                        g_debug ("Suspend is inhibited but lid is closed, locking the screen");
                        /* We put the screensaver on * as we're not suspending,
                         * but the lid is closed */
                        lock_screensaver (manager);
                }
        }
}

static void
lid_state_changed_cb (UpClient *client, GParamSpec *pspec, GsdPowerManager *manager)
{
        gboolean tmp;

        if (!manager->lid_is_present)
                return;

        /* same lid state */
        /* FIXME: https://gitlab.gnome.org/GNOME/gnome-settings-daemon/-/issues/859 */
        G_GNUC_BEGIN_IGNORE_DEPRECATIONS
        tmp = up_client_get_lid_is_closed (manager->up_client);
        G_GNUC_END_IGNORE_DEPRECATIONS
        if (manager->lid_is_closed == tmp)
                return;
        manager->lid_is_closed = tmp;
        g_debug ("up changed: lid is now %s", tmp ? "closed" : "open");

        if (manager->lid_is_closed)
                do_lid_closed_action (manager);
        else
                do_lid_open_action (manager);
}

static const gchar *
idle_mode_to_string (GsdPowerIdleMode mode)
{
        if (mode == GSD_POWER_IDLE_MODE_NORMAL)
                return "normal";
        if (mode == GSD_POWER_IDLE_MODE_DIM)
                return "dim";
        if (mode == GSD_POWER_IDLE_MODE_BLANK)
                return "blank";
        if (mode == GSD_POWER_IDLE_MODE_SLEEP)
                return "sleep";
        return "unknown";
}

static const char *
idle_watch_id_to_string (GsdPowerManager *manager, guint id)
{
        if (id == manager->idle_dim_id)
                return "dim";
        if (id == manager->idle_blank_id)
                return "blank";
        if (id == manager->idle_sleep_id)
                return "sleep";
        if (id == manager->idle_sleep_warning_id)
                return "sleep-warning";
        return NULL;
}

static void
backlight_iface_emit_changed (GsdPowerManager *manager,
                              const char      *interface_name,
                              gint32           value,
                              const char      *source)
{
        GVariant *params;

        /* not yet connected to the bus */
        if (manager->connection == NULL)
                return;

        params = g_variant_new_parsed ("(%s, [{'Brightness', <%i>}], @as [])", interface_name,
                                       value);
        g_dbus_connection_emit_signal (manager->connection,
                                       NULL,
                                       GSD_POWER_DBUS_PATH,
                                       "org.freedesktop.DBus.Properties",
                                       "PropertiesChanged",
                                       params, NULL);

        if (!source)
                return;

        g_dbus_connection_emit_signal (manager->connection,
                                       NULL,
                                       GSD_POWER_DBUS_PATH,
                                       GSD_POWER_DBUS_INTERFACE_KEYBOARD,
                                       "BrightnessChanged",
                                       g_variant_new ("(is)", value, source),
                                       NULL);
}

static void
backlight_notify_brightness_cb (GsdPowerManager *manager, GParamSpec *pspec, GsdBacklight *backlight)
{
        backlight_iface_emit_changed (manager, GSD_POWER_DBUS_INTERFACE_SCREEN,
                                      gsd_backlight_get_brightness (backlight, NULL), NULL);
}

static void
display_backlight_dim (GsdPowerManager *manager,
                       gint idle_percentage)
{
        gint brightness;

        if (!manager->backlight)
                return;

        /* Fetch the current target brightness (not the actual display brightness)
         * and return if it is already lower than the idle percentage. */
        gsd_backlight_get_brightness (manager->backlight, &brightness);
        if (brightness < idle_percentage)
                return;

        manager->pre_dim_brightness = brightness;
        gsd_backlight_set_brightness_async (manager->backlight, idle_percentage, NULL, NULL, NULL);
}

static gboolean
kbd_backlight_dim (GsdPowerManager *manager,
                   gint idle_percentage,
                   GError **error)
{
        gboolean ret;
        gint idle;
        gint max;
        gint now;

        if (manager->upower_kbd_proxy == NULL)
                return TRUE;

        now = manager->kbd_brightness_now;
        max = manager->kbd_brightness_max;
        idle = PERCENTAGE_TO_ABS (0, max, idle_percentage);
        if (idle > now) {
                g_debug ("kbd brightness already now %i/%i, so "
                         "ignoring dim to %i/%i",
                         now, max, idle, max);
                return TRUE;
        }
        ret = upower_kbd_set_brightness (manager, idle, error);
        if (!ret)
                return FALSE;

        /* save for undim */
        manager->kbd_brightness_pre_dim = now;
        return TRUE;
}

static void
upower_kbd_proxy_signal_cb (GDBusProxy  *proxy,
                            const gchar *sender_name,
                            const gchar *signal_name,
                            GVariant    *parameters,
                            gpointer     user_data)
{
        GsdPowerManager *manager = GSD_POWER_MANAGER (user_data);
        gint brightness, percentage;
        const gchar *source;

        if (g_strcmp0 (signal_name, "BrightnessChangedWithSource") != 0)
                return;

        g_variant_get (parameters, "(i&s)", &brightness, &source);

        /* Ignore changes caused by us calling UPower's SetBrightness method,
         * we already call backlight_iface_emit_changed for these after the
         * SetBrightness method call completes. */
        if (g_strcmp0 (source, "external") == 0)
                return;

        manager->kbd_brightness_now = brightness;
        percentage = ABS_TO_PERCENTAGE (0,
                                        manager->kbd_brightness_max,
                                        manager->kbd_brightness_now);
        backlight_iface_emit_changed (manager, GSD_POWER_DBUS_INTERFACE_KEYBOARD, percentage, source);
}

static gboolean
is_session_active (GsdPowerManager *manager)
{
        GVariant *variant;
        gboolean is_session_active = FALSE;

        variant = g_dbus_proxy_get_cached_property (G_DBUS_PROXY (manager->session),
                                                    "SessionIsActive");
        if (variant) {
                is_session_active = g_variant_get_boolean (variant);
                g_variant_unref (variant);
        }

        return is_session_active;
}

static void
idle_set_mode (GsdPowerManager *manager, GsdPowerIdleMode mode)
{
        gboolean ret = FALSE;
        GError *error = NULL;
        gint idle_percentage;
        GsdPowerActionType action_type;

        /* Ignore attempts to set "less idle" modes */
        if (mode <= manager->current_idle_mode &&
            mode != GSD_POWER_IDLE_MODE_NORMAL) {
                g_debug ("Not going to 'less idle' mode %s (current: %s)",
                         idle_mode_to_string (mode),
                         idle_mode_to_string (manager->current_idle_mode));
                return;
        }

        /* ensure we're still on an active console */
        if (!manager->session_is_active) {
                g_debug ("ignoring state transition to %s as inactive",
                         idle_mode_to_string (mode));
                return;
        }

        manager->current_idle_mode = mode;
        g_debug ("Doing a state transition: %s", idle_mode_to_string (mode));

        /* if we're moving to an idle mode, make sure
         * we add a watch to take us back to normal */
        if (mode != GSD_POWER_IDLE_MODE_NORMAL) {
                if (manager->user_active_id < 1) {
                    manager->user_active_id = gnome_idle_monitor_add_user_active_watch (manager->idle_monitor,
                                                                                        idle_became_active_cb,
                                                                                        manager,
                                                                                        NULL);
                    g_debug ("installing idle_became_active_cb to clear sleep warning when transitioning away from normal (%i)",
                             manager->user_active_id);
                }
        }

        /* save current brightness, and set dim level */
        if (mode == GSD_POWER_IDLE_MODE_DIM) {
                /* display backlight */
                idle_percentage = g_settings_get_int (manager->settings,
                                                      "idle-brightness");
                display_backlight_dim (manager, idle_percentage);

                /* keyboard backlight */
                ret = kbd_backlight_dim (manager, idle_percentage, &error);
                if (!ret) {
                        g_warning ("failed to set dim kbd backlight to %i%%: %s",
                                   idle_percentage,
                                   error->message);
                        g_clear_error (&error);
                }

        /* turn off screen and kbd */
        } else if (mode == GSD_POWER_IDLE_MODE_BLANK) {

                backlight_disable (manager);

                /* only toggle keyboard if present and not already toggled */
                if (manager->upower_kbd_proxy &&
                    manager->kbd_brightness_old == -1) {
                        if (upower_kbd_toggle (manager, &error) < 0) {
                                g_warning ("failed to turn the kbd backlight off: %s",
                                           error->message);
                                g_error_free (error);
                        }
                }

        /* sleep */
        } else if (mode == GSD_POWER_IDLE_MODE_SLEEP) {

                if (up_client_get_on_battery (manager->up_client)) {
                        action_type = g_settings_get_enum (manager->settings,
                                                           "sleep-inactive-battery-type");
                } else {
                        action_type = g_settings_get_enum (manager->settings,
                                                           "sleep-inactive-ac-type");
                }
                do_power_action_type (manager, action_type);

        /* turn on screen and restore user-selected brightness level */
        } else if (mode == GSD_POWER_IDLE_MODE_NORMAL) {

                backlight_enable (manager);

                /* reset brightness if we dimmed */
                if (manager->backlight && manager->pre_dim_brightness >= 0) {
                        gsd_backlight_set_brightness_async (manager->backlight,
                                                            manager->pre_dim_brightness,
                                                            NULL, NULL, NULL);
                        /* XXX: Ideally we would do this from the async callback. */
                        manager->pre_dim_brightness = -1;
                }

                /* only toggle keyboard if present and already toggled off */
                if (manager->upower_kbd_proxy &&
                    manager->kbd_brightness_old != -1) {
                        if (upower_kbd_toggle (manager, &error) < 0) {
                                g_warning ("failed to turn the kbd backlight on: %s",
                                           error->message);
                                g_clear_error (&error);
                        }
                }

                /* reset kbd brightness if we dimmed */
                if (manager->kbd_brightness_pre_dim >= 0) {
                        ret = upower_kbd_set_brightness (manager,
                                                         manager->kbd_brightness_pre_dim,
                                                         &error);
                        if (!ret) {
                                g_warning ("failed to restore kbd backlight to %i: %s",
                                           manager->kbd_brightness_pre_dim,
                                           error->message);
                                g_error_free (error);
                        }
                        manager->kbd_brightness_pre_dim = -1;
                }

        }
}

static gboolean
idle_is_session_inhibited (GsdPowerManager  *manager,
                           GsmInhibitorFlag  mask,
                           gboolean         *is_inhibited)
{
        GVariant *variant;
        GsmInhibitorFlag inhibited_actions;

        *is_inhibited = FALSE;

        /* not yet connected to gnome-session */
        if (manager->session == NULL)
                return FALSE;

        variant = g_dbus_proxy_get_cached_property (G_DBUS_PROXY (manager->session),
                                                    "InhibitedActions");
        if (!variant)
                return FALSE;

        inhibited_actions = g_variant_get_uint32 (variant);
        g_variant_unref (variant);

        *is_inhibited = (inhibited_actions & mask);

        return TRUE;
}

static void
clear_idle_watch (GnomeIdleMonitor *monitor,
                  guint            *id)
{
        if (*id == 0)
                return;
        gnome_idle_monitor_remove_watch (monitor, *id);
        *id = 0;
}

static gboolean
is_power_save_active (GsdPowerManager *manager)
{
        /*
         * If we have power-profiles-daemon, then we follow its setting,
         * otherwise we go into power-save mode when the battery is low.
         */
        if (manager->power_profiles_proxy &&
            g_dbus_proxy_get_name_owner (manager->power_profiles_proxy))
                return manager->power_saver_enabled;
        else
                return manager->battery_is_low;
}

static void
idle_configure (GsdPowerManager *manager)
{
        gboolean is_idle_inhibited;
        GsdPowerActionType action_type;
        guint timeout_sleep;
        guint timeout_dim;
        gboolean on_battery;

        if (!idle_is_session_inhibited (manager,
                                        GSM_INHIBITOR_FLAG_IDLE,
                                        &is_idle_inhibited)) {
                /* Session isn't available yet, postpone */
                return;
        }

        /* set up blank callback only when the screensaver is on,
         * as it's what will drive the blank */
        clear_idle_watch (manager->idle_monitor,
                          &manager->idle_blank_id);
        if (manager->screensaver_active) {
                /* The tail is wagging the dog.
                 * The screensaver coming on will blank the screen.
                 * If an event occurs while the screensaver is on,
                 * the aggressive idle watch will handle it */
                guint timeout_blank = SCREENSAVER_TIMEOUT_BLANK;
                g_debug ("setting up blank callback for %is", timeout_blank);
                manager->idle_blank_id = gnome_idle_monitor_add_idle_watch (manager->idle_monitor,
                                                                                  timeout_blank * 1000,
                                                                                  idle_triggered_idle_cb, manager, NULL);
        }

        /* are we inhibited from going idle */
        if (!manager->session_is_active ||
            (is_idle_inhibited && !manager->screensaver_active)) {
                if (is_idle_inhibited && !manager->screensaver_active)
                        g_debug ("inhibited and screensaver not active, so using normal state");
                else
                        g_debug ("inactive, so using normal state");
                idle_set_mode (manager, GSD_POWER_IDLE_MODE_NORMAL);

                clear_idle_watch (manager->idle_monitor,
                                  &manager->idle_sleep_id);
                clear_idle_watch (manager->idle_monitor,
                                  &manager->idle_dim_id);
                clear_idle_watch (manager->idle_monitor,
                                  &manager->idle_sleep_warning_id);
                notify_close_if_showing (&manager->notification_sleep_warning);
                return;
        }

        /* only do the sleep timeout when the session is idle
         * and we aren't inhibited from sleeping (or logging out, etc.) */
        on_battery = up_client_get_on_battery (manager->up_client);
        action_type = g_settings_get_enum (manager->settings, on_battery ?
                                           "sleep-inactive-battery-type" : "sleep-inactive-ac-type");
        timeout_sleep = 0;
        if (!is_action_inhibited (manager, action_type)) {
                gint timeout_sleep_;
                timeout_sleep_ = g_settings_get_int (manager->settings, on_battery ?
                                                     "sleep-inactive-battery-timeout" : "sleep-inactive-ac-timeout");
                timeout_sleep = CLAMP (timeout_sleep_, 0, G_MAXINT);
        }

        clear_idle_watch (manager->idle_monitor,
                          &manager->idle_sleep_id);
        clear_idle_watch (manager->idle_monitor,
                          &manager->idle_sleep_warning_id);

        /* don't do any power saving if we're a VM */
        if (manager->is_virtual_machine &&
            (action_type == GSD_POWER_ACTION_SUSPEND ||
             action_type == GSD_POWER_ACTION_HIBERNATE)) {
                g_debug ("Ignoring sleep timeout with suspend action inside VM");
                timeout_sleep = 0;
        }

        /* don't do any automatic logout if we are in GDM */
        if (g_getenv ("RUNNING_UNDER_GDM") &&
            (action_type == GSD_POWER_ACTION_LOGOUT)) {
                g_debug ("Ignoring sleep timeout with logout action inside GDM");
                timeout_sleep = 0;
        }

        if (timeout_sleep != 0) {
                g_debug ("setting up sleep callback %is", timeout_sleep);

                if (action_type != GSD_POWER_ACTION_NOTHING) {
                        manager->idle_sleep_id = gnome_idle_monitor_add_idle_watch (manager->idle_monitor,
                                                                                          timeout_sleep * 1000,
                                                                                          idle_triggered_idle_cb, manager, NULL);
                }

                if (action_type == GSD_POWER_ACTION_LOGOUT ||
                    action_type == GSD_POWER_ACTION_SUSPEND ||
                    action_type == GSD_POWER_ACTION_HIBERNATE) {
                        guint timeout_sleep_warning_msec;

                        manager->sleep_action_type = action_type;
                        timeout_sleep_warning_msec = timeout_sleep * IDLE_DELAY_TO_IDLE_DIM_MULTIPLIER * 1000;
                        if (timeout_sleep_warning_msec * 1000 < MINIMUM_IDLE_DIM_DELAY) {
                                /* 0 is not a valid idle timeout */
                                timeout_sleep_warning_msec = 1;
                        }

                        g_debug ("setting up sleep warning callback %i msec", timeout_sleep_warning_msec);

                        manager->idle_sleep_warning_id = gnome_idle_monitor_add_idle_watch (manager->idle_monitor,
                                                                                                  timeout_sleep_warning_msec,
                                                                                                  idle_triggered_idle_cb, manager, NULL);
                }
        }

        if (manager->idle_sleep_warning_id == 0)
                notify_close_if_showing (&manager->notification_sleep_warning);

        /* set up dim callback for when the screen lock is not active,
         * but only if we actually want to dim. */
        timeout_dim = 0;
        if (manager->screensaver_active) {
                /* Don't dim when the screen lock is active */
        } else if (is_power_save_active (manager)) {
                /* Try to save power by dimming agressively */
                timeout_dim = SCREENSAVER_TIMEOUT_BLANK;
        } else {
                if (g_settings_get_boolean (manager->settings, "idle-dim")) {
                        timeout_dim = g_settings_get_uint (manager->settings_bus,
                                                           "idle-delay");
                        if (timeout_dim == 0) {
                                timeout_dim = IDLE_DIM_BLANK_DISABLED_MIN;
                        } else {
                                timeout_dim *= IDLE_DELAY_TO_IDLE_DIM_MULTIPLIER;
                                /* Don't bother dimming if the idle-delay is
                                 * too low, we'll do that when we bring down the
                                 * screen lock */
                                if (timeout_dim < MINIMUM_IDLE_DIM_DELAY)
                                        timeout_dim = 0;
                        }
                }
        }

        clear_idle_watch (manager->idle_monitor,
                          &manager->idle_dim_id);

        if (timeout_dim != 0) {
                g_debug ("setting up dim callback for %is", timeout_dim);

                manager->idle_dim_id = gnome_idle_monitor_add_idle_watch (manager->idle_monitor,
                                                                                timeout_dim * 1000,
                                                                                idle_triggered_idle_cb, manager, NULL);
        }
}

static void
hold_profile_cb (GObject      *source_object,
                 GAsyncResult *res,
                 gpointer      user_data)
{
        GsdPowerManager *manager = user_data;
        g_autoptr(GError) error = NULL;
        g_autoptr(GVariant) result = NULL;

        result = g_dbus_proxy_call_finish (G_DBUS_PROXY (source_object),
                                           res,
                                           &error);
        if (result == NULL) {
                g_warning ("Couldn't hold power-saver profile: %s", error->message);
                return;
        }

        if (g_variant_is_of_type (result, G_VARIANT_TYPE ("(u)"))) {
                g_variant_get (result, "(u)", &manager->power_saver_cookie);
                g_debug ("Holding power-saver profile with cookie %u", manager->power_saver_cookie);
        } else {
                g_warning ("Calling HoldProfile() did not return a uint32");
        }
}

static void
enable_power_saver (GsdPowerManager *manager)
{
        if (!manager->power_profiles_proxy)
                return;
        if (!g_settings_get_boolean (manager->settings, "power-saver-profile-on-low-battery"))
                return;

        g_debug ("Starting hold of power-saver profile");

        g_dbus_proxy_call (manager->power_profiles_proxy,
                           "HoldProfile",
                           g_variant_new("(sss)",
                                         "power-saver",
                                         "Power saver profile when low on battery",
                                         GSD_POWER_DBUS_NAME),
                           G_DBUS_CALL_FLAGS_NONE,
                           -1, manager->cancellable, hold_profile_cb, manager);
}

static void
disable_power_saver (GsdPowerManager *manager)
{
        if (!manager->power_profiles_proxy || manager->power_saver_cookie == 0)
                return;

        g_debug ("Releasing power-saver profile");

        g_dbus_proxy_call (manager->power_profiles_proxy,
                           "ReleaseProfile",
                           g_variant_new ("(u)", manager->power_saver_cookie),
                           G_DBUS_CALL_FLAGS_NONE,
                           -1, NULL, dbus_call_log_error, "ReleaseProfile failed");
        manager->power_saver_cookie = 0;
}

static void
main_battery_or_ups_low_changed (GsdPowerManager *manager,
                                 gboolean         is_low)
{
        if (is_low == manager->battery_is_low)
                return;
        manager->battery_is_low = is_low;
        idle_configure (manager);
        if (is_low)
                enable_power_saver (manager);
        else
                disable_power_saver (manager);
}

static gboolean
temporary_unidle_done_cb (GsdPowerManager *manager)
{
        idle_set_mode (manager, manager->previous_idle_mode);
        manager->temporary_unidle_on_ac_id = 0;
        return FALSE;
}

static void
set_temporary_unidle_on_ac (GsdPowerManager *manager,
                            gboolean         enable)
{
        if (!enable) {
                /* Don't automatically go back to the previous idle
                   mode. The caller probably has a better idea of
                   which state to move to when disabling us. */
                if (manager->temporary_unidle_on_ac_id != 0) {
                        g_source_remove (manager->temporary_unidle_on_ac_id);
                        manager->temporary_unidle_on_ac_id = 0;
                }
        } else {
                /* Don't overwrite the previous idle mode when an unidle is
                 * already on-going */
                if (manager->temporary_unidle_on_ac_id != 0) {
                        g_source_remove (manager->temporary_unidle_on_ac_id);
                } else {
                        manager->previous_idle_mode = manager->current_idle_mode;
                        idle_set_mode (manager, GSD_POWER_IDLE_MODE_NORMAL);
                }
                manager->temporary_unidle_on_ac_id = g_timeout_add_seconds (POWER_UP_TIME_ON_AC,
                                                                                  (GSourceFunc) temporary_unidle_done_cb,
                                                                                  manager);
                g_source_set_name_by_id (manager->temporary_unidle_on_ac_id, "[gnome-settings-daemon] temporary_unidle_done_cb");
        }
}

static void
up_client_on_battery_cb (UpClient *client,
                         GParamSpec *pspec,
                         GsdPowerManager *manager)
{
        if (up_client_get_on_battery (manager->up_client)) {
                ca_context_play (ca_gtk_context_get (), 0,
                                 CA_PROP_EVENT_ID, "power-unplug",
                                 /* TRANSLATORS: this is the sound description */
                                 CA_PROP_EVENT_DESCRIPTION, _("On battery power"), NULL);
        } else {
                ca_context_play (ca_gtk_context_get (), 0,
                                 CA_PROP_EVENT_ID, "power-plug",
                                 /* TRANSLATORS: this is the sound description */
                                 CA_PROP_EVENT_DESCRIPTION, _("On AC power"), NULL);

        }

        idle_configure (manager);

        if (manager->lid_is_closed)
                return;

        if (manager->current_idle_mode == GSD_POWER_IDLE_MODE_BLANK ||
            manager->current_idle_mode == GSD_POWER_IDLE_MODE_DIM ||
            manager->temporary_unidle_on_ac_id != 0)
                set_temporary_unidle_on_ac (manager, TRUE);
}

static void
gsd_power_manager_finalize (GObject *object)
{
        GsdPowerManager *manager;

        g_return_if_fail (object != NULL);
        g_return_if_fail (GSD_IS_POWER_MANAGER (object));

        manager = GSD_POWER_MANAGER (object);

        g_return_if_fail (manager != NULL);

        if (manager->cancellable != NULL) {
                g_cancellable_cancel (manager->cancellable);
                g_clear_object (&manager->cancellable);
        }

        G_OBJECT_CLASS (gsd_power_manager_parent_class)->finalize (object);
}

static void
gsd_power_manager_class_init (GsdPowerManagerClass *klass)
{
        GObjectClass *object_class = G_OBJECT_CLASS (klass);
        GApplicationClass *application_class = G_APPLICATION_CLASS (klass);

        object_class->finalize = gsd_power_manager_finalize;

        application_class->startup = gsd_power_manager_startup;
        application_class->shutdown = gsd_power_manager_shutdown;

        notify_init ("gnome-settings-daemon");
}

static void
handle_screensaver_active (GsdPowerManager *manager,
                           GVariant        *parameters)
{
        gboolean active;

        g_variant_get (parameters, "(b)", &active);
        g_debug ("Received screensaver ActiveChanged signal: %d (old: %d)", active, manager->screensaver_active);
        if (manager->screensaver_active != active) {
                manager->screensaver_active = active;
                idle_configure (manager);

                /* Setup blank as soon as the screensaver comes on,
                 * and its fade has finished.
                 *
                 * See also idle_configure() */
                if (active)
                        idle_set_mode (manager, GSD_POWER_IDLE_MODE_BLANK);
        }
}

static void
handle_wake_up_screen (GsdPowerManager *manager)
{
        set_temporary_unidle_on_ac (manager, TRUE);
}

static void
screensaver_signal_cb (GDBusProxy *proxy,
                       const gchar *sender_name,
                       const gchar *signal_name,
                       GVariant *parameters,
                       gpointer user_data)
{
        if (g_strcmp0 (signal_name, "ActiveChanged") == 0)
                handle_screensaver_active (GSD_POWER_MANAGER (user_data), parameters);
        else if (g_strcmp0 (signal_name, "WakeUpScreen") == 0)
                handle_wake_up_screen (GSD_POWER_MANAGER (user_data));
}

static void
power_profiles_proxy_signal_cb (GDBusProxy  *proxy,
                               const gchar *sender_name,
                               const gchar *signal_name,
                               GVariant    *parameters,
                               gpointer     user_data)
{
        GsdPowerManager *manager = GSD_POWER_MANAGER (user_data);

        if (g_strcmp0 (signal_name, "ProfileReleased") != 0)
                return;
        manager->power_saver_cookie = 0;
}

static void
update_active_power_profile (GsdPowerManager *manager)
{
        g_autoptr(GVariant) v = NULL;
        const char *active_profile;
        gboolean power_saver_enabled;

        v = g_dbus_proxy_get_cached_property (manager->power_profiles_proxy, "ActiveProfile");
        if (v) {
                active_profile = g_variant_get_string (v, NULL);
                power_saver_enabled = g_strcmp0 (active_profile, "power-saver") == 0;
                if (power_saver_enabled != manager->power_saver_enabled) {
                        manager->power_saver_enabled = power_saver_enabled;
                        idle_configure (manager);
                }
        } else {
                /* p-p-d might have disappeared from the bus */
                idle_configure (manager);
        }
}

static void
power_profiles_proxy_ready_cb (GObject             *source_object,
                              GAsyncResult        *res,
                              gpointer             user_data)
{
        g_autoptr(GError) error = NULL;
        GsdPowerManager *manager = GSD_POWER_MANAGER (user_data);

        manager->power_profiles_proxy = g_dbus_proxy_new_for_bus_finish (res, &error);
        if (manager->power_profiles_proxy == NULL) {
                g_debug ("Could not connect to power-profiles-daemon: %s", error->message);
                return;
        }

        g_signal_connect_swapped (manager->power_profiles_proxy,
                                  "g-properties-changed",
                                  G_CALLBACK (update_active_power_profile),
                                  manager);
        g_signal_connect (manager->power_profiles_proxy, "g-signal",
                          G_CALLBACK (power_profiles_proxy_signal_cb),
                          manager);

        update_active_power_profile (manager);
}

static int
backlight_get_n_steps (GsdPowerManager *manager)
{
        int step;

        step = BRIGHTNESS_STEP_AMOUNT (manager->kbd_brightness_max);

        return (manager->kbd_brightness_max / step) + 1;
}

static void
power_keyboard_proxy_ready_cb (GObject             *source_object,
                               GAsyncResult        *res,
                               gpointer             user_data)
{
        GVariant *k_now = NULL;
        GVariant *k_max = NULL;
        GVariant *params = NULL;
        GError *error = NULL;
        GsdPowerManager *manager = GSD_POWER_MANAGER (user_data);
        gint percentage;

        manager->upower_kbd_proxy = g_dbus_proxy_new_for_bus_finish (res, &error);
        if (manager->upower_kbd_proxy == NULL) {
                g_warning ("Could not connect to UPower: %s",
                           error->message);
                g_error_free (error);
                goto out;
        }

        g_signal_connect (manager->upower_kbd_proxy, "g-signal",
                          G_CALLBACK (upower_kbd_proxy_signal_cb),
                          manager);

        k_now = g_dbus_proxy_call_sync (manager->upower_kbd_proxy,
                                        "GetBrightness",
                                        NULL,
                                        G_DBUS_CALL_FLAGS_NONE,
                                        -1,
                                        manager->cancellable,
                                        &error);
        if (k_now == NULL) {
                if (error->domain != G_DBUS_ERROR ||
                    error->code != G_DBUS_ERROR_UNKNOWN_METHOD) {
                        g_warning ("Failed to get brightness: %s",
                                   error->message);
                } else {
                        /* Keyboard brightness is not available */
                        g_clear_object (&manager->upower_kbd_proxy);
                }
                g_error_free (error);
                goto out;
        }

        k_max = g_dbus_proxy_call_sync (manager->upower_kbd_proxy,
                                        "GetMaxBrightness",
                                        NULL,
                                        G_DBUS_CALL_FLAGS_NONE,
                                        -1,
                                        manager->cancellable,
                                        &error);
        if (k_max == NULL) {
                g_warning ("Failed to get max brightness: %s", error->message);
                g_error_free (error);
                goto out;
        }

        g_variant_get (k_now, "(i)", &manager->kbd_brightness_now);
        g_variant_get (k_max, "(i)", &manager->kbd_brightness_max);

        /* set brightness to max if not currently set so is something
         * sensible */
        if (manager->kbd_brightness_now < 0) {
                gboolean ret;
                ret = upower_kbd_set_brightness (manager,
                                                 manager->kbd_brightness_max,
                                                 &error);
                if (!ret) {
                        g_warning ("failed to initialize kbd backlight to %i: %s",
                                   manager->kbd_brightness_max,
                                   error->message);
                        g_error_free (error);
                }
        }

        /* Tell the front-end that the brightness changed from
         * its default "-1/no keyboard backlight available" default */
        percentage = ABS_TO_PERCENTAGE (0,
                                        manager->kbd_brightness_max,
                                        manager->kbd_brightness_now);
        backlight_iface_emit_changed (manager, GSD_POWER_DBUS_INTERFACE_KEYBOARD, percentage, "initial value");

        /* Same for "Steps" */
        params = g_variant_new_parsed ("(%s, [{'Steps', <%i>}], @as [])",
                                       GSD_POWER_DBUS_INTERFACE_KEYBOARD, backlight_get_n_steps (manager));
        g_dbus_connection_emit_signal (manager->connection,
                                       NULL,
                                       GSD_POWER_DBUS_PATH,
                                       "org.freedesktop.DBus.Properties",
                                       "PropertiesChanged",
                                       params, NULL);

out:
        if (k_now != NULL)
                g_variant_unref (k_now);
        if (k_max != NULL)
                g_variant_unref (k_max);
}

static void
show_sleep_warning (GsdPowerManager *manager)
{
        /* close any existing notification of this class */
        notify_close_if_showing (&manager->notification_sleep_warning);

        /* create a new notification */
        switch (manager->sleep_action_type) {
        case GSD_POWER_ACTION_LOGOUT:
                create_notification (_("Automatic Logout"), _("You will soon log out because of inactivity"),
                                     NULL, NOTIFICATION_PRIVACY_USER,
                                     &manager->notification_sleep_warning);
                break;
        case GSD_POWER_ACTION_SUSPEND:
                create_notification (_("Automatic Suspend"), _("Suspending soon because of inactivity"),
                                     NULL, NOTIFICATION_PRIVACY_SYSTEM,
                                     &manager->notification_sleep_warning);
                break;
        case GSD_POWER_ACTION_HIBERNATE:
                create_notification (_("Automatic Hibernation"), _("Suspending soon because of inactivity"),
                                     NULL, NOTIFICATION_PRIVACY_SYSTEM,
                                     &manager->notification_sleep_warning);
                break;
        default:
                g_assert_not_reached ();
                break;
        }
        notify_notification_set_timeout (manager->notification_sleep_warning,
                                         NOTIFY_EXPIRES_NEVER);
        notify_notification_set_urgency (manager->notification_sleep_warning,
                                         NOTIFY_URGENCY_CRITICAL);

        notify_notification_show (manager->notification_sleep_warning, NULL);
}

static void
idle_set_mode_no_temp (GsdPowerManager  *manager,
                       GsdPowerIdleMode  mode)
{
        if (manager->temporary_unidle_on_ac_id != 0) {
                manager->previous_idle_mode = mode;
                return;
        }

        idle_set_mode (manager, mode);
}

static void
idle_triggered_idle_cb (GnomeIdleMonitor *monitor,
                        guint             watch_id,
                        gpointer          user_data)
{
        GsdPowerManager *manager = GSD_POWER_MANAGER (user_data);
        const char *id_name;

        id_name = idle_watch_id_to_string (manager, watch_id);
        if (id_name == NULL)
                g_debug ("idletime watch: %i", watch_id);
        else
                g_debug ("idletime watch: %s (%i)", id_name, watch_id);

        if (watch_id == manager->idle_dim_id) {
                idle_set_mode_no_temp (manager, GSD_POWER_IDLE_MODE_DIM);
        } else if (watch_id == manager->idle_blank_id) {
                idle_set_mode_no_temp (manager, GSD_POWER_IDLE_MODE_BLANK);
        } else if (watch_id == manager->idle_sleep_id) {
                idle_set_mode_no_temp (manager, GSD_POWER_IDLE_MODE_SLEEP);
        } else if (watch_id == manager->idle_sleep_warning_id) {
                if (manager->show_sleep_warnings) {
                        show_sleep_warning (manager);
                }
                if (manager->user_active_id < 1) {
                        manager->user_active_id = 
                                gnome_idle_monitor_add_user_active_watch (manager->idle_monitor,
                                                                          idle_became_active_cb,
                                                                          manager,
                                                                          NULL);
                        g_debug ("installing idle_became_active_cb to clear sleep warning on activity (%i)",
                                 manager->user_active_id);
                }
        }
}

static void
idle_became_active_cb (GnomeIdleMonitor *monitor,
                       guint             watch_id,
                       gpointer          user_data)
{
        GsdPowerManager *manager = GSD_POWER_MANAGER (user_data);

        g_debug ("idletime reset (%i)", watch_id);

        set_temporary_unidle_on_ac (manager, FALSE);

        /* close any existing notification about idleness */
        notify_close_if_showing (&manager->notification_sleep_warning);

        idle_set_mode (manager, GSD_POWER_IDLE_MODE_NORMAL);
        manager->user_active_id = 0;
}

static void
ch_backlight_renormalize (GsdPowerManager *manager)
{
        if (manager->ambient_percentage_old < 0)
                return;
        if (manager->ambient_last_absolute < 0)
                return;
        manager->ambient_norm_value = manager->ambient_last_absolute /
                                        (gdouble) manager->ambient_percentage_old;
        manager->ambient_norm_value *= 100.f;
        manager->ambient_norm_required = FALSE;
}

static void
engine_settings_key_changed_cb (GSettings *settings,
                                const gchar *key,
                                GsdPowerManager *manager)
{
        if (g_str_has_prefix (key, "sleep-inactive") ||
            g_str_equal (key, "idle-delay") ||
            g_str_equal (key, "idle-dim")) {
                idle_configure (manager);
                return;
        }
        if (g_str_equal (key, "power-saver-profile-on-low-battery")) {
                if (manager->battery_is_low &&
                    g_settings_get_boolean (settings, key))
                        enable_power_saver (manager);
                else
                        disable_power_saver (manager);
                return;
        }
}

static void
engine_session_properties_changed_cb (GDBusProxy      *session,
                                      GVariant        *changed,
                                      char           **invalidated,
                                      GsdPowerManager *manager)
{
        GVariant *v;

        v = g_variant_lookup_value (changed, "SessionIsActive", G_VARIANT_TYPE_BOOLEAN);
        if (v) {
                gboolean active;

                active = g_variant_get_boolean (v);
                g_debug ("Received session is active change: now %s", active ? "active" : "inactive");
                manager->session_is_active = active;
                /* when doing the fast-user-switch into a new account,
                 * ensure the new account is undimmed and with the backlight on */
                if (active) {
                        idle_set_mode (manager, GSD_POWER_IDLE_MODE_NORMAL);
                        iio_proxy_claim_light (manager, TRUE);
                } else {
                        iio_proxy_claim_light (manager, FALSE);
                }
                g_variant_unref (v);

                sync_lid_inhibitor (manager);
        }

        v = g_variant_lookup_value (changed, "InhibitedActions", G_VARIANT_TYPE_UINT32);
        if (v) {
                g_variant_unref (v);
                g_debug ("Received gnome session inhibitor change");
                idle_configure (manager);
        }
}

static void
inhibit_lid_switch_done (GObject      *source,
                         GAsyncResult *result,
                         gpointer      user_data)
{
        GDBusProxy *proxy = G_DBUS_PROXY (source);
        GsdPowerManager *manager = GSD_POWER_MANAGER (user_data);
        GError *error = NULL;
        GVariant *res;
        GUnixFDList *fd_list = NULL;
        gint idx;

        res = g_dbus_proxy_call_with_unix_fd_list_finish (proxy, &fd_list, result, &error);
        if (res == NULL) {
                g_warning ("Unable to inhibit lid switch: %s", error->message);
                g_error_free (error);
        } else {
                g_variant_get (res, "(h)", &idx);
                manager->inhibit_lid_switch_fd = g_unix_fd_list_get (fd_list, idx, &error);
                if (manager->inhibit_lid_switch_fd == -1) {
                        g_warning ("Failed to receive system inhibitor fd: %s", error->message);
                        g_error_free (error);
                }
                g_debug ("System inhibitor fd is %d", manager->inhibit_lid_switch_fd);
                g_object_unref (fd_list);
                g_variant_unref (res);
        }
}

static void
inhibit_lid_switch (GsdPowerManager *manager)
{
        GVariant *params;

        if (manager->inhibit_lid_switch_taken) {
                g_debug ("already inhibited lid-switch");
                return;
        }
        g_debug ("Adding lid switch system inhibitor");
        manager->inhibit_lid_switch_taken = TRUE;

        params = g_variant_new ("(ssss)",
                                "handle-lid-switch",
                                g_get_user_name (),
                                "External monitor attached or configuration changed recently",
                                "block");
        g_dbus_proxy_call_with_unix_fd_list (manager->logind_proxy,
                                             "Inhibit",
                                             params,
                                             0,
                                             G_MAXINT,
                                             NULL,
                                             NULL,
                                             inhibit_lid_switch_done,
                                             manager);
}

static void
uninhibit_lid_switch (GsdPowerManager *manager)
{
        if (manager->inhibit_lid_switch_fd == -1) {
                g_debug ("no lid-switch inhibitor");
                return;
        }
        g_debug ("Removing lid switch system inhibitor");
        close (manager->inhibit_lid_switch_fd);
        manager->inhibit_lid_switch_fd = -1;
        manager->inhibit_lid_switch_taken = FALSE;
}

static void
inhibit_suspend_done (GObject      *source,
                      GAsyncResult *result,
                      gpointer      user_data)
{
        GDBusProxy *proxy = G_DBUS_PROXY (source);
        GsdPowerManager *manager = GSD_POWER_MANAGER (user_data);
        GError *error = NULL;
        GVariant *res;
        GUnixFDList *fd_list = NULL;
        gint idx;

        res = g_dbus_proxy_call_with_unix_fd_list_finish (proxy, &fd_list, result, &error);
        if (res == NULL) {
                g_warning ("Unable to inhibit suspend: %s", error->message);
                g_error_free (error);
        } else {
                g_variant_get (res, "(h)", &idx);
                manager->inhibit_suspend_fd = g_unix_fd_list_get (fd_list, idx, &error);
                if (manager->inhibit_suspend_fd == -1) {
                        g_warning ("Failed to receive system inhibitor fd: %s", error->message);
                        g_error_free (error);
                }
                g_debug ("System inhibitor fd is %d", manager->inhibit_suspend_fd);
                g_object_unref (fd_list);
                g_variant_unref (res);
        }
}

/* We take a delay inhibitor here, which causes logind to send a
 * PrepareForSleep signal, which gives us a chance to lock the screen
 * and do some other preparations.
 */
static void
inhibit_suspend (GsdPowerManager *manager)
{
        if (manager->inhibit_suspend_taken) {
                g_debug ("already inhibited lid-switch");
                return;
        }
        g_debug ("Adding suspend delay inhibitor");
        manager->inhibit_suspend_taken = TRUE;
        g_dbus_proxy_call_with_unix_fd_list (manager->logind_proxy,
                                             "Inhibit",
                                             g_variant_new ("(ssss)",
                                                            "sleep",
                                                            g_get_user_name (),
                                                            "GNOME needs to lock the screen",
                                                            "delay"),
                                             0,
                                             G_MAXINT,
                                             NULL,
                                             NULL,
                                             inhibit_suspend_done,
                                             manager);
}

static void
uninhibit_suspend (GsdPowerManager *manager)
{
        if (manager->inhibit_suspend_fd == -1) {
                g_debug ("no suspend delay inhibitor");
                return;
        }
        g_debug ("Removing suspend delay inhibitor");
        close (manager->inhibit_suspend_fd);
        manager->inhibit_suspend_fd = -1;
        manager->inhibit_suspend_taken = FALSE;
}

static void
sync_lid_inhibitor (GsdPowerManager *manager)
{
        g_debug ("Syncing lid inhibitor and grabbing it temporarily");

        /* Uninhibiting is done in inhibit_lid_switch_timer_cb,
         * since we want to give users a few seconds when unplugging
         * and replugging an external monitor, not suspend right away.
         */
        inhibit_lid_switch (manager);
        restart_inhibit_lid_switch_timer (manager);
}

static void
has_external_monitor_changed (GsdPowerManager *manager)
{

        g_debug ("Screen configuration changed");

        sync_lid_inhibitor (manager);
}

static void
handle_suspend_actions (GsdPowerManager *manager)
{
        /* close any existing notification about idleness */
        notify_close_if_showing (&manager->notification_sleep_warning);
        backlight_disable (manager);
        uninhibit_suspend (manager);
}

static void
handle_resume_actions (GsdPowerManager *manager)
{
        /* ensure we turn the panel back on after resume */
        backlight_enable (manager);

        /* set up the delay again */
        inhibit_suspend (manager);
}

static void
logind_proxy_signal_cb (GDBusProxy  *proxy,
                        const gchar *sender_name,
                        const gchar *signal_name,
                        GVariant    *parameters,
                        gpointer     user_data)
{
        GsdPowerManager *manager = GSD_POWER_MANAGER (user_data);
        gboolean is_about_to_suspend;

        if (g_strcmp0 (signal_name, "PrepareForSleep") != 0)
                return;
        g_variant_get (parameters, "(b)", &is_about_to_suspend);
        if (is_about_to_suspend) {
                handle_suspend_actions (manager);
        } else {
                handle_resume_actions (manager);
        }
}

static void
iio_proxy_changed (GsdPowerManager *manager)
{
        GVariant *val_has = NULL;
        GVariant *val_als = NULL;
        gdouble brightness;
        gdouble alpha;
        gint64 current_time;
        gint pc;

        /* no display hardware */
        if (!manager->backlight)
                return;

        /* disabled */
        if (!g_settings_get_boolean (manager->settings, "ambient-enabled"))
                return;

        /* get latest results, which do not have to be Lux */
        val_has = g_dbus_proxy_get_cached_property (manager->iio_proxy, "HasAmbientLight");
        if (val_has == NULL || !g_variant_get_boolean (val_has))
                goto out;
        val_als = g_dbus_proxy_get_cached_property (manager->iio_proxy, "LightLevel");
        if (val_als == NULL || g_variant_get_double (val_als) == 0.0)
                goto out;
        manager->ambient_last_absolute = g_variant_get_double (val_als);
        g_debug ("Read last absolute light level: %f", manager->ambient_last_absolute);

        /* the user has asked to renormalize */
        if (manager->ambient_norm_required) {
                g_debug ("Renormalizing light level from old light percentage: %.1f%%",
                         manager->ambient_percentage_old);
                manager->ambient_accumulator = manager->ambient_percentage_old;
                ch_backlight_renormalize (manager);
        }

        /* time-weighted constant for moving average */
        current_time = g_get_monotonic_time();
        if (manager->ambient_last_time)
                alpha = 1.0f / (1.0f + (GSD_AMBIENT_TIME_CONSTANT / (current_time - manager->ambient_last_time)));
        else
                alpha = 0.0f;
        manager->ambient_last_time = current_time;

        /* calculate exponential weighted moving average */
        brightness = manager->ambient_last_absolute * 100.f / manager->ambient_norm_value;
        brightness = MIN (brightness, 100.f);
        brightness = MAX (brightness, 0.f);

        manager->ambient_accumulator = (alpha * brightness) +
                (1.0 - alpha) * manager->ambient_accumulator;

        /* no valid readings yet */
        if (manager->ambient_accumulator < 0.f)
                goto out;

        /* set new value */
        g_debug ("Setting brightness from ambient %.1f%%",
                 manager->ambient_accumulator);
        pc = manager->ambient_accumulator;

        if (manager->backlight)
                gsd_backlight_set_brightness_async (manager->backlight, pc, NULL, NULL, NULL);

        /* Assume setting worked. */
        manager->ambient_percentage_old = pc;
out:
        g_clear_pointer (&val_has, g_variant_unref);
        g_clear_pointer (&val_als, g_variant_unref);
}

static void
iio_proxy_changed_cb (GDBusProxy *proxy,
                      GVariant   *changed_properties,
                      GStrv       invalidated_properties,
                      gpointer    user_data)
{
        iio_proxy_changed ((GsdPowerManager *) user_data);
}

static void
iio_proxy_appeared_cb (GDBusConnection *connection,
                       const gchar *name,
                       const gchar *name_owner,
                       gpointer user_data)
{
        GsdPowerManager *manager = GSD_POWER_MANAGER (user_data);
        manager->iio_proxy =
                g_dbus_proxy_new_for_bus_sync (G_BUS_TYPE_SYSTEM,
                                               0,
                                               NULL,
                                               "net.hadess.SensorProxy",
                                               "/net/hadess/SensorProxy",
                                               "net.hadess.SensorProxy",
                                               NULL,
                                               NULL);
        iio_proxy_claim_light (manager, TRUE);
}

static void
iio_proxy_vanished_cb (GDBusConnection *connection,
                       const gchar *name,
                       gpointer user_data)
{
        GsdPowerManager *manager = GSD_POWER_MANAGER (user_data);
        g_clear_object (&manager->iio_proxy);
}

static gboolean
gsd_power_manager_initable_init (GInitable     *initable,
                                 GCancellable  *cancellable,
                                 GError       **error)
{
        GsdPowerManager *manager = GSD_POWER_MANAGER (initable);

        /* Check whether we have a lid first */
        if (manager->up_client == NULL) {
                manager->up_client = up_client_new_full (manager->cancellable, error);
                if (manager->up_client == NULL) {
                        g_debug ("No upower support, disabling plugin");
                        return FALSE;
                }
        }

        /* Set up the logind proxy */
        if (manager->logind_proxy == NULL) {
                manager->logind_proxy =
                        g_dbus_proxy_new_for_bus_sync (G_BUS_TYPE_SYSTEM,
                                                       0,
                                                       NULL,
                                                       SYSTEMD_DBUS_NAME,
                                                       SYSTEMD_DBUS_PATH,
                                                       SYSTEMD_DBUS_INTERFACE,
                                                       NULL,
                                                       error);
                if (manager->logind_proxy == NULL) {
                        g_debug ("No systemd (logind) support, disabling plugin");
                        return FALSE;
                }
        }

        return TRUE;
}

static void
initable_iface_init (GInitableIface *initable_iface)
{
        initable_iface->init = gsd_power_manager_initable_init;
}

static void
gsd_power_manager_startup (GApplication *app)
{
        GsdPowerManager *manager = GSD_POWER_MANAGER (app);
        g_autoptr (GError) error = NULL;
        g_autofree char *chassis_type = NULL;
        g_debug ("Starting power manager");
        gnome_settings_profile_start (NULL);

        register_manager_dbus (manager);

        /* Check whether we are running in a VM */
        manager->is_virtual_machine = gsd_power_is_hardware_a_vm ();

        /* FIXME: https://gitlab.gnome.org/GNOME/gnome-settings-daemon/-/issues/859 */
        G_GNUC_BEGIN_IGNORE_DEPRECATIONS
        manager->lid_is_present = up_client_get_lid_is_present (manager->up_client);
        if (manager->lid_is_present)
                manager->lid_is_closed = up_client_get_lid_is_closed (manager->up_client);
        G_GNUC_END_IGNORE_DEPRECATIONS

        chassis_type = gnome_settings_get_chassis_type ();
        if (g_strcmp0 (chassis_type, "tablet") == 0 || g_strcmp0 (chassis_type, "handset") == 0) {
                manager->show_sleep_warnings = FALSE;
        } else {
                manager->show_sleep_warnings = TRUE;
        }

        manager->settings = g_settings_new (GSD_POWER_SETTINGS_SCHEMA);
        manager->settings_screensaver = g_settings_new ("org.gnome.desktop.screensaver");
        manager->settings_bus = g_settings_new ("org.gnome.desktop.session");

        /* setup ambient light support */
        manager->iio_proxy_watch_id =
                g_bus_watch_name (G_BUS_TYPE_SYSTEM,
                                  "net.hadess.SensorProxy",
                                  G_BUS_NAME_WATCHER_FLAGS_NONE,
                                  iio_proxy_appeared_cb,
                                  iio_proxy_vanished_cb,
                                  manager, NULL);
        manager->ambient_norm_required = TRUE;
        manager->ambient_accumulator = -1.f;
        manager->ambient_norm_value = -1.f;
        manager->ambient_percentage_old = -1.f;
        manager->ambient_last_absolute = -1.f;
        manager->ambient_last_time = 0;

        manager->backlight = gsd_backlight_new (NULL);

        if (manager->backlight)
                g_signal_connect_object (manager->backlight,
                                         "notify::brightness",
                                         G_CALLBACK (backlight_notify_brightness_cb),
                                         manager, G_CONNECT_SWAPPED);

        /* Set up a delay inhibitor to be informed about suspend attempts */
        g_signal_connect (manager->logind_proxy, "g-signal",
                          G_CALLBACK (logind_proxy_signal_cb),
                          manager);
        inhibit_suspend (manager);

        /* track the active session */
        manager->session = gnome_settings_bus_get_session_proxy ();
        g_signal_connect_object (manager->session, "g-properties-changed",
                                 G_CALLBACK (engine_session_properties_changed_cb),
                                 manager, 0);
        manager->session_is_active = is_session_active (manager);

        /* set up the screens */
        if (manager->lid_is_present) {
                manager->display_config =
                        gnome_settings_bus_get_display_config_proxy ();

                g_signal_connect_swapped (manager->display_config, "notify::has-external-monitor",
                                          G_CALLBACK (has_external_monitor_changed), manager);
                watch_external_monitor ();
                sync_lid_inhibitor (manager);
        }

        manager->screensaver_proxy = gnome_settings_bus_get_screen_saver_proxy ();

        g_signal_connect (manager->screensaver_proxy, "g-signal",
                          G_CALLBACK (screensaver_signal_cb), manager);

        manager->kbd_brightness_old = -1;
        manager->kbd_brightness_pre_dim = -1;
        manager->pre_dim_brightness = -1;
        g_signal_connect (manager->settings, "changed",
                          G_CALLBACK (engine_settings_key_changed_cb), manager);
        g_signal_connect (manager->settings_bus, "changed",
                          G_CALLBACK (engine_settings_key_changed_cb), manager);
        g_signal_connect (manager->up_client, "device-added",
                          G_CALLBACK (engine_device_added_cb), manager);
        g_signal_connect (manager->up_client, "device-removed",
                          G_CALLBACK (engine_device_removed_cb), manager);
        g_signal_connect_after (manager->up_client, "notify::lid-is-closed",
                                G_CALLBACK (lid_state_changed_cb), manager);
        g_signal_connect (manager->up_client, "notify::on-battery",
                          G_CALLBACK (up_client_on_battery_cb), manager);

        /* connect to power-profiles-daemon */
        g_dbus_proxy_new_for_bus (G_BUS_TYPE_SYSTEM,
                                  G_DBUS_PROXY_FLAGS_NONE,
                                  NULL,
                                  PPD_DBUS_NAME,
                                  PPD_DBUS_PATH,
                                  PPD_DBUS_INTERFACE,
                                  manager->cancellable,
                                  power_profiles_proxy_ready_cb,
                                  manager);

        /* connect to UPower for keyboard backlight control */
        manager->kbd_brightness_now = -1;
        g_dbus_proxy_new_for_bus (G_BUS_TYPE_SYSTEM,
                                  G_DBUS_PROXY_FLAGS_DO_NOT_LOAD_PROPERTIES,
                                  NULL,
                                  UPOWER_DBUS_NAME,
                                  UPOWER_DBUS_PATH_KBDBACKLIGHT,
                                  UPOWER_DBUS_INTERFACE_KBDBACKLIGHT,
                                  NULL,
                                  power_keyboard_proxy_ready_cb,
                                  manager);

        manager->devices_array = g_ptr_array_new_with_free_func (g_object_unref);
        manager->devices_notified_ht = g_hash_table_new_full (g_str_hash, g_str_equal,
                                                              g_free, NULL);

        /* create a fake virtual composite battery */
        manager->device_composite = up_client_get_display_device (manager->up_client);
        g_signal_connect (manager->device_composite, "notify::warning-level",
                          G_CALLBACK (engine_device_warning_changed_cb), manager);

        /* create IDLETIME watcher */
        manager->idle_monitor = gnome_idle_monitor_new ();

        /* coldplug the engine */
        engine_coldplug (manager);
        idle_configure (manager);

        /* ensure the default dpms timeouts are cleared */
        backlight_enable (manager);

        if (!gnome_settings_is_wayland ())
                manager->xscreensaver_watchdog_timer_id = gsd_power_enable_screensaver_watchdog ();

        G_APPLICATION_CLASS (gsd_power_manager_parent_class)->startup (app);

        gnome_settings_profile_end (NULL);
}

static void
gsd_power_manager_shutdown (GApplication *app)
{
        GsdPowerManager *manager = GSD_POWER_MANAGER (app);

        g_debug ("Stopping power manager");

        if (manager->inhibit_lid_switch_timer_id != 0) {
                g_source_remove (manager->inhibit_lid_switch_timer_id);
                manager->inhibit_lid_switch_timer_id = 0;
        }

        g_clear_pointer (&manager->introspection_data, g_dbus_node_info_unref);

        if (manager->up_client)
                g_signal_handlers_disconnect_by_data (manager->up_client, manager);
        if (manager->display_config)
                g_signal_handlers_disconnect_by_data (manager->display_config, manager);
        if (manager->power_profiles_proxy)
                g_signal_handlers_disconnect_by_data (manager->power_profiles_proxy, manager);
        if (manager->screensaver_proxy)
                g_signal_handlers_disconnect_by_data (manager->screensaver_proxy, manager);
        if (manager->upower_kbd_proxy)
                g_signal_handlers_disconnect_by_data (manager->upower_kbd_proxy, manager);

        g_clear_object (&manager->session);
        g_clear_object (&manager->settings);
        g_clear_object (&manager->settings_screensaver);
        g_clear_object (&manager->settings_bus);
        g_clear_object (&manager->up_client);
        g_clear_object (&manager->display_config);

        iio_proxy_claim_light (manager, FALSE);
        g_clear_object (&manager->iio_proxy);

        if (manager->inhibit_lid_switch_fd != -1) {
                close (manager->inhibit_lid_switch_fd);
                manager->inhibit_lid_switch_fd = -1;
                manager->inhibit_lid_switch_taken = FALSE;
        }
        if (manager->inhibit_suspend_fd != -1) {
                close (manager->inhibit_suspend_fd);
                manager->inhibit_suspend_fd = -1;
                manager->inhibit_suspend_taken = FALSE;
        }

        g_clear_object (&manager->logind_proxy);

        g_clear_pointer (&manager->devices_array, g_ptr_array_unref);
        g_clear_object (&manager->device_composite);
        g_clear_pointer (&manager->devices_notified_ht, g_hash_table_destroy);

        g_clear_object (&manager->screensaver_proxy);

        disable_power_saver (manager);
        g_clear_object (&manager->power_profiles_proxy);

        play_loop_stop (&manager->critical_alert_timeout_id);

        g_clear_object (&manager->idle_monitor);
        g_clear_object (&manager->upower_kbd_proxy);

        if (manager->xscreensaver_watchdog_timer_id > 0) {
                g_source_remove (manager->xscreensaver_watchdog_timer_id);
                manager->xscreensaver_watchdog_timer_id = 0;
        }

        g_clear_object (&manager->connection);

        g_clear_handle_id (&manager->name_id, g_bus_unown_name);
        g_clear_handle_id (&manager->iio_proxy_watch_id, g_bus_unwatch_name);

        G_APPLICATION_CLASS (gsd_power_manager_parent_class)->shutdown (app);
}

static void
gsd_power_manager_init (GsdPowerManager *manager)
{
        manager->inhibit_lid_switch_fd = -1;
        manager->inhibit_suspend_fd = -1;
        manager->cancellable = g_cancellable_new ();
}

/* returns new level */
static void
handle_method_call_keyboard (GsdPowerManager *manager,
                             const gchar *method_name,
                             GVariant *parameters,
                             GDBusMethodInvocation *invocation)
{
        gint step;
        gint value = -1;
        gboolean ret;
        guint percentage;
        GError *error = NULL;

        if (g_strcmp0 (method_name, "StepUp") == 0) {
                g_debug ("keyboard step up");
                step = BRIGHTNESS_STEP_AMOUNT (manager->kbd_brightness_max);
                value = MIN (manager->kbd_brightness_now + step,
                             manager->kbd_brightness_max);
                ret = upower_kbd_set_brightness (manager, value, &error);

        } else if (g_strcmp0 (method_name, "StepDown") == 0) {
                g_debug ("keyboard step down");
                step = BRIGHTNESS_STEP_AMOUNT (manager->kbd_brightness_max);
                value = MAX (manager->kbd_brightness_now - step, 0);
                ret = upower_kbd_set_brightness (manager, value, &error);

        } else if (g_strcmp0 (method_name, "Toggle") == 0) {
                value = upower_kbd_toggle (manager, &error);
                ret = (value >= 0);

        } else {
                g_assert_not_reached ();
        }

        /* return value */
        if (!ret) {
                g_dbus_method_invocation_take_error (invocation,
                                                     error);
                backlight_iface_emit_changed (manager, GSD_POWER_DBUS_INTERFACE_KEYBOARD, -1, method_name);
        } else {
                percentage = ABS_TO_PERCENTAGE (0,
                                                manager->kbd_brightness_max,
                                                value);
                g_dbus_method_invocation_return_value (invocation,
                                                       g_variant_new ("(i)",
                                                                      percentage));
                backlight_iface_emit_changed (manager, GSD_POWER_DBUS_INTERFACE_KEYBOARD, percentage, method_name);
        }
}

static void
backlight_brightness_step_cb (GObject *object,
                              GAsyncResult *res,
                              gpointer user_data)
{
        GsdBacklight *backlight = GSD_BACKLIGHT (object);
        GDBusMethodInvocation *invocation = G_DBUS_METHOD_INVOCATION (user_data);
        GsdPowerManager *manager;
        GError *error = NULL;
        const char *connector;
        gint brightness;

        manager = g_object_get_data (G_OBJECT (invocation), "gsd-power-manager");
        brightness = gsd_backlight_set_brightness_finish (backlight, res, &error);

        /* ambient brightness no longer valid */
        manager->ambient_percentage_old = brightness;
        manager->ambient_norm_required = TRUE;

        if (error) {
                g_dbus_method_invocation_take_error (invocation,
                                                     error);
        } else {
                connector = gsd_backlight_get_connector (backlight);

                g_dbus_method_invocation_return_value (invocation,
                                                       g_variant_new ("(is)",
                                                                      brightness,
                                                                      connector ? connector : ""));
        }
}

/* Callback */
static void
backlight_brightness_set_cb (GObject *object,
                             GAsyncResult *res,
                             gpointer user_data)
{
        GsdPowerManager *manager = GSD_POWER_MANAGER (user_data);
        GsdBacklight *backlight = GSD_BACKLIGHT (object);
        gint brightness;

        /* Return the invocation. */
        brightness = gsd_backlight_set_brightness_finish (backlight, res, NULL);

        if (brightness >= 0) {
                manager->ambient_percentage_old = brightness;
                manager->ambient_norm_required = TRUE;
        }

        g_object_unref (manager);
}

static void
handle_method_call_screen (GsdPowerManager *manager,
                           const gchar *method_name,
                           GVariant *parameters,
                           GDBusMethodInvocation *invocation)
{
        if (!manager->backlight) {
                g_dbus_method_invocation_return_error_literal (invocation,
                                                               GSD_POWER_MANAGER_ERROR, GSD_POWER_MANAGER_ERROR_NO_BACKLIGHT,
                                                               "No usable backlight could be found!");
                return;
        }

        g_object_set_data_full (G_OBJECT (invocation), "gsd-power-manager", g_object_ref (manager), g_object_unref);

        if (g_strcmp0 (method_name, "StepUp") == 0) {
                g_debug ("screen step up");
                gsd_backlight_step_up_async (manager->backlight, NULL, backlight_brightness_step_cb, invocation);

        } else if (g_strcmp0 (method_name, "StepDown") == 0) {
                g_debug ("screen step down");
                gsd_backlight_step_down_async (manager->backlight, NULL, backlight_brightness_step_cb, invocation);

        } else if (g_strcmp0 (method_name, "Cycle") == 0) {
                g_debug ("screen cycle up");
                gsd_backlight_cycle_up_async (manager->backlight, NULL, backlight_brightness_step_cb, invocation);

        } else {
                g_assert_not_reached ();
        }
}

static void
handle_method_call (GDBusConnection       *connection,
                    const gchar           *sender,
                    const gchar           *object_path,
                    const gchar           *interface_name,
                    const gchar           *method_name,
                    GVariant              *parameters,
                    GDBusMethodInvocation *invocation,
                    gpointer               user_data)
{
        GsdPowerManager *manager = GSD_POWER_MANAGER (user_data);

        /* Check session pointer as a proxy for whether the manager is in the
           start or stop state */
        if (manager->session == NULL) {
                return;
        }

        g_debug ("Calling method '%s.%s' for Power",
                 interface_name, method_name);

        if (g_strcmp0 (interface_name, GSD_POWER_DBUS_INTERFACE_SCREEN) == 0) {
                handle_method_call_screen (manager,
                                           method_name,
                                           parameters,
                                           invocation);
        } else if (g_strcmp0 (interface_name, GSD_POWER_DBUS_INTERFACE_KEYBOARD) == 0) {
                handle_method_call_keyboard (manager,
                                             method_name,
                                             parameters,
                                             invocation);
        } else {
                g_warning ("not recognised interface: %s", interface_name);
        }
}

static GVariant *
handle_get_property_other (GsdPowerManager *manager,
                           const gchar *interface_name,
                           const gchar *property_name,
                           GError **error)
{
        GVariant *retval = NULL;
        gint32 value;


        if (g_strcmp0 (interface_name, GSD_POWER_DBUS_INTERFACE_SCREEN) == 0) {
                if (g_strcmp0 (property_name, "Brightness") != 0) {
                        g_set_error (error, G_DBUS_ERROR, G_DBUS_ERROR_FAILED,
                                     "No such property: %s", property_name);
                        return NULL;
                }

                if (manager->backlight)
                        value = gsd_backlight_get_brightness (manager->backlight, NULL);
                else
                        value = -1;

                retval = g_variant_new_int32 (value);
        } else if (manager->upower_kbd_proxy &&
                   g_strcmp0 (interface_name, GSD_POWER_DBUS_INTERFACE_KEYBOARD) == 0) {
                if (g_strcmp0 (property_name, "Brightness") == 0) {
                        value = ABS_TO_PERCENTAGE (0,
                                                   manager->kbd_brightness_max,
                                                   manager->kbd_brightness_now);
                        retval =  g_variant_new_int32 (value);
                } else if (g_strcmp0 (property_name, "Steps") == 0) {
                        value = backlight_get_n_steps (manager);
                        retval =  g_variant_new_int32 (value);
                }
        }

        if (retval == NULL) {
                g_set_error (error, G_DBUS_ERROR, G_DBUS_ERROR_FAILED,
                             "Failed to get property %s on interface %s",
                             property_name, interface_name);
        }
        return retval;
}

static GVariant *
handle_get_property (GDBusConnection *connection,
                     const gchar *sender,
                     const gchar *object_path,
                     const gchar *interface_name,
                     const gchar *property_name,
                     GError **error, gpointer user_data)
{
        GsdPowerManager *manager = GSD_POWER_MANAGER (user_data);

        /* Check session pointer as a proxy for whether the manager is in the
           start or stop state */
        if (manager->session == NULL) {
                g_set_error_literal (error, G_DBUS_ERROR, G_DBUS_ERROR_FAILED,
                                     "No session");
                return NULL;
        }

        if (g_strcmp0 (interface_name, GSD_POWER_DBUS_INTERFACE_SCREEN) == 0 ||
                   g_strcmp0 (interface_name, GSD_POWER_DBUS_INTERFACE_KEYBOARD) == 0) {
                return handle_get_property_other (manager, interface_name, property_name, error);
        } else {
                g_set_error (error, G_DBUS_ERROR, G_DBUS_ERROR_FAILED,
                             "No such interface: %s", interface_name);
                return NULL;
        }
}

static gboolean
handle_set_property_other (GsdPowerManager *manager,
                           const gchar *interface_name,
                           const gchar *property_name,
                           GVariant *value,
                           GError **error)
{
        gint32 brightness_value;

        if (g_strcmp0 (property_name, "Brightness") != 0) {
                g_set_error (error, G_DBUS_ERROR, G_DBUS_ERROR_FAILED,
                             "No such property: %s", property_name);
                return FALSE;
        }

        if (g_strcmp0 (interface_name, GSD_POWER_DBUS_INTERFACE_SCREEN) == 0) {
                /* To do error reporting we would need to handle the Set call
                 * instead of doing it through set_property.
                 * But none of our DBus API users actually read the result. */
                g_variant_get (value, "i", &brightness_value);
                if (manager->backlight) {
                        gsd_backlight_set_brightness_async (manager->backlight, brightness_value,
                                                            NULL,
                                                            backlight_brightness_set_cb, g_object_ref (manager));
                        return TRUE;
                } else {
                        g_set_error_literal (error, GSD_POWER_MANAGER_ERROR, GSD_POWER_MANAGER_ERROR_NO_BACKLIGHT,
                                             "No usable backlight could be found!");
                        return FALSE;
                }

        } else if (g_strcmp0 (interface_name, GSD_POWER_DBUS_INTERFACE_KEYBOARD) == 0) {
                g_variant_get (value, "i", &brightness_value);
                brightness_value = PERCENTAGE_TO_ABS (0, manager->kbd_brightness_max,
                                                      brightness_value);
                if (upower_kbd_set_brightness (manager, brightness_value, error)) {
                        brightness_value = ABS_TO_PERCENTAGE (0,
                                                              manager->kbd_brightness_max,
                                                              manager->kbd_brightness_now);
                        backlight_iface_emit_changed (manager, GSD_POWER_DBUS_INTERFACE_KEYBOARD, brightness_value, "set property");
                        return TRUE;
                } else {
                        return FALSE;
                }
        }

        g_set_error (error, G_DBUS_ERROR, G_DBUS_ERROR_FAILED,
                     "No such interface: %s", interface_name);
        return FALSE;
}

static gboolean
handle_set_property (GDBusConnection *connection,
                     const gchar *sender,
                     const gchar *object_path,
                     const gchar *interface_name,
                     const gchar *property_name,
                     GVariant *value,
                     GError **error, gpointer user_data)
{
        GsdPowerManager *manager = GSD_POWER_MANAGER (user_data);

        /* Check session pointer as a proxy for whether the manager is in the
           start or stop state */
        if (manager->session == NULL) {
                g_set_error (error, G_DBUS_ERROR, G_DBUS_ERROR_FAILED,
                             "Manager is starting or stopping");
                return FALSE;
        }

        if (g_strcmp0 (interface_name, GSD_POWER_DBUS_INTERFACE_SCREEN) == 0 ||
            g_strcmp0 (interface_name, GSD_POWER_DBUS_INTERFACE_KEYBOARD) == 0) {
                return handle_set_property_other (manager, interface_name, property_name, value, error);
        } else {
                g_set_error (error, G_DBUS_ERROR, G_DBUS_ERROR_FAILED,
                             "No such interface: %s", interface_name);
                return FALSE;
        }
}

static const GDBusInterfaceVTable interface_vtable =
{
        handle_method_call,
        handle_get_property,
        handle_set_property
};

static void
on_bus_gotten (GObject             *source_object,
               GAsyncResult        *res,
               GsdPowerManager     *manager)
{
        GDBusConnection *connection;
        GDBusInterfaceInfo **infos;
        GError *error = NULL;
        guint i;

        connection = g_bus_get_finish (res, &error);
        if (connection == NULL) {
                if (!g_error_matches (error, G_IO_ERROR, G_IO_ERROR_CANCELLED))
                        g_warning ("Could not get session bus: %s", error->message);
                g_error_free (error);
                return;
        }

        manager->connection = connection;

        infos = manager->introspection_data->interfaces;
        for (i = 0; infos[i] != NULL; i++) {
                g_dbus_connection_register_object (connection,
                                                   GSD_POWER_DBUS_PATH,
                                                   infos[i],
                                                   &interface_vtable,
                                                   manager,
                                                   NULL,
                                                   NULL);
        }

        manager->name_id = g_bus_own_name_on_connection (connection,
                                                               GSD_POWER_DBUS_NAME,
                                                               G_BUS_NAME_OWNER_FLAGS_NONE,
                                                               NULL,
                                                               NULL,
                                                               NULL,
                                                               NULL);

        /* queue a signal in case the proxy from gnome-shell was created before we got here
           (likely, considering that to get here we need a reply from gnome-shell)
        */
        if (manager->backlight) {
                manager->ambient_percentage_old = gsd_backlight_get_brightness (manager->backlight, NULL);
                backlight_iface_emit_changed (manager, GSD_POWER_DBUS_INTERFACE_SCREEN,
                                              manager->ambient_percentage_old, NULL);
        } else {
                backlight_iface_emit_changed (manager, GSD_POWER_DBUS_INTERFACE_SCREEN, -1, NULL);
        }
}

static void
register_manager_dbus (GsdPowerManager *manager)
{
        manager->introspection_data = g_dbus_node_info_new_for_xml (introspection_xml, NULL);
        g_assert (manager->introspection_data != NULL);

        g_bus_get (G_BUS_TYPE_SESSION,
                   manager->cancellable,
                   (GAsyncReadyCallback) on_bus_gotten,
                   manager);
}
