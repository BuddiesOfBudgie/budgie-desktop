/*
 * Copyright © 2013 Intel Corporation.
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms and conditions of the GNU Lesser General Public License,
 * version 2.1, as published by the Free Software Foundation.
 *
 * This program is distributed in the hope it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, see <http://www.gnu.org/licenses>
 *
 * Author: Michael Wood <michael.g.wood@intel.com>
 */

#include "mpris-controller.h"
#include "bus-watch-namespace.h"
#include <gio/gio.h>

enum {
  PROP_0,
  PROP_HAS_ACTIVE_PLAYER
};

struct _MprisController
{
  GObject parent;

  GCancellable *cancellable;
  GDBusProxy *mpris_client_proxy;
  guint namespace_watcher_id;
  GSList *other_proxies;
};

G_DEFINE_TYPE (MprisController, mpris_controller, G_TYPE_OBJECT)

static void
mpris_controller_dispose (GObject *object)
{
  MprisController *self = MPRIS_CONTROLLER (object);

  g_clear_object (&self->cancellable);
  g_clear_object (&self->mpris_client_proxy);

  if (self->namespace_watcher_id)
    {
      bus_unwatch_namespace (self->namespace_watcher_id);
      self->namespace_watcher_id = 0;
    }

  g_slist_free_full (g_steal_pointer (&self->other_proxies), g_object_unref);

  G_OBJECT_CLASS (mpris_controller_parent_class)->dispose (object);
}

static void
mpris_proxy_call_done (GObject      *object,
                       GAsyncResult *res,
                       gpointer      user_data)
{
  GError *error = NULL;
  GVariant *ret;

  if (!(ret = g_dbus_proxy_call_finish (G_DBUS_PROXY (object), res, &error)))
    {
      if (!g_error_matches (error, G_IO_ERROR, G_IO_ERROR_CANCELLED))
        g_warning ("Error calling method %s", error->message);
      g_clear_error (&error);
      return;
    }
  g_variant_unref (ret);
}

gboolean
mpris_controller_key (MprisController *self, const gchar *key)
{
  g_return_val_if_fail (MPRIS_IS_CONTROLLER (self), FALSE);
  g_return_val_if_fail (key != NULL, FALSE);

  if (!self->mpris_client_proxy)
    return FALSE;

  if (g_strcmp0 (key, "Play") == 0)
    key = "PlayPause";

  g_debug ("calling %s over dbus to mpris client %s",
           key, g_dbus_proxy_get_name (self->mpris_client_proxy));
  g_dbus_proxy_call (self->mpris_client_proxy,
                     key, NULL, 0, -1, self->cancellable,
                     mpris_proxy_call_done,
                     NULL);
  return TRUE;
}

gboolean
mpris_controller_seek (MprisController *self, gint64 offset)
{
  g_return_val_if_fail (MPRIS_IS_CONTROLLER (self), FALSE);

  if (!self->mpris_client_proxy)
    return FALSE;

  g_debug ("calling Seek over dbus to mpris client %s",
           g_dbus_proxy_get_name (self->mpris_client_proxy));
  g_dbus_proxy_call (self->mpris_client_proxy,
                     "Seek", g_variant_new ("(x)", offset, NULL),
                     G_DBUS_CALL_FLAGS_NONE, -1, self->cancellable,
                     mpris_proxy_call_done,
                     NULL);
  return TRUE;
}

static GDBusProxy *
get_props_proxy (GDBusProxy   *proxy,
                 GCancellable *cancellable)
{
  GDBusProxy *props = NULL;
  g_autoptr(GError) error = NULL;

  g_return_val_if_fail (proxy != NULL, NULL);

  props = g_dbus_proxy_new_sync (g_dbus_proxy_get_connection (proxy),
                                 G_DBUS_PROXY_FLAGS_DO_NOT_AUTO_START | G_DBUS_PROXY_FLAGS_DO_NOT_CONNECT_SIGNALS | G_DBUS_PROXY_FLAGS_DO_NOT_LOAD_PROPERTIES,
                                 NULL,
                                 g_dbus_proxy_get_name (proxy),
                                 g_dbus_proxy_get_object_path (proxy),
                                 "org.freedesktop.DBus.Properties",
                                 cancellable,
                                 &error);
  if (!props) {
    g_debug ("Could not get properties proxy for %s: %s",
             g_dbus_proxy_get_interface_name (proxy),
             error->message);
    return NULL;
  }

  return props;
}

gboolean
mpris_controller_toggle (MprisController *self, const gchar *property)
{
  g_return_val_if_fail (MPRIS_IS_CONTROLLER (self), FALSE);
  g_return_val_if_fail (property != NULL, FALSE);

  if (!self->mpris_client_proxy)
    return FALSE;

  if (g_str_equal (property, "LoopStatus")) {
    g_autoptr(GDBusProxy) props = NULL;
    g_autoptr(GVariant) loop_status;
    const gchar *status_str, *new_status;

    loop_status = g_dbus_proxy_get_cached_property (self->mpris_client_proxy, "LoopStatus");
    if (!loop_status)
      return FALSE;
    if (!g_variant_is_of_type (loop_status, G_VARIANT_TYPE_STRING))
      return FALSE;
    status_str = g_variant_get_string (loop_status, NULL);
    if (g_str_equal (status_str, "Playlist"))
      new_status = "None";
    else
      new_status = "Playlist";

    props = get_props_proxy (self->mpris_client_proxy, self->cancellable);
    if (!props)
      return FALSE;
    g_dbus_proxy_call (props,
                       "Set",
                       g_variant_new_parsed ("('org.mpris.MediaPlayer2.Player', 'LoopStatus', %v)",
                                             g_variant_new_string (new_status)),
                       G_DBUS_CALL_FLAGS_NONE,
                       -1,
                       self->cancellable,
                       mpris_proxy_call_done, NULL);
  } else if (g_str_equal (property, "Shuffle")) {
    g_autoptr(GDBusProxy) props = NULL;
    g_autoptr(GVariant) shuffle_status;
    gboolean status;

    shuffle_status = g_dbus_proxy_get_cached_property (self->mpris_client_proxy, "Shuffle");
    if (!shuffle_status)
      return FALSE;
    if (!g_variant_is_of_type (shuffle_status, G_VARIANT_TYPE_BOOLEAN))
      return FALSE;
    status = g_variant_get_boolean (shuffle_status);

    props = get_props_proxy (self->mpris_client_proxy, self->cancellable);
    if (!props)
      return FALSE;
    g_dbus_proxy_call (props,
                       "Set",
                       g_variant_new_parsed ("('org.mpris.MediaPlayer2.Player', 'Shuffle', %v)",
                                             g_variant_new_boolean (!status)),
                       G_DBUS_CALL_FLAGS_NONE,
                       -1,
                       self->cancellable,
                       mpris_proxy_call_done, NULL);
  }

  g_debug ("Unhandled toggle property '%s'", property);

  return TRUE;
}

static gboolean
mpris_client_is_playing (GDBusProxy *proxy)
{
  g_autoptr(GVariant) playback_status;
  const gchar *status_str;

  playback_status = g_dbus_proxy_get_cached_property (proxy, "PlaybackStatus");
  if (!playback_status)
    return FALSE;

  if (!g_variant_is_of_type (playback_status, G_VARIANT_TYPE_STRING))
    return FALSE;

  status_str = g_variant_get_string (playback_status, NULL);
  return g_strcmp0 (status_str, "Playing") == 0;
}

static void
mpris_client_notify_name_owner_cb (GDBusProxy      *proxy,
                                   GParamSpec      *pspec,
                                   MprisController *self)
{
  g_autofree gchar *name_owner = NULL;
  GSList *first;

  /* Owner changed, but the proxy is still valid. */
  name_owner = g_dbus_proxy_get_name_owner (proxy);
  if (name_owner)
    return;

  if (proxy == self->mpris_client_proxy)
    {
      g_debug ("Clearing the current MPRIS client proxy");
      g_clear_object (&self->mpris_client_proxy);

      if ((first = self->other_proxies))
        {
          self->mpris_client_proxy = first->data;
          self->other_proxies = first->next;
          g_slist_free_1 (first);

          g_debug ("Falling back to MPRIS client %s",
                   g_dbus_proxy_get_name (self->mpris_client_proxy));
        }
      else
        {
          g_object_notify (G_OBJECT (self), "has-active-player");
        }
    }
  else
    {
      g_debug ("Forgetting MPRIS client %s", g_dbus_proxy_get_name (proxy));
      self->other_proxies = g_slist_remove (self->other_proxies, proxy);
      g_object_unref (proxy);
    }
}

static void
mpris_client_properties_changed_cb (GDBusProxy *proxy,
                                    GVariant   *changed_properties,
                                    GStrv       invalidated_properties,
                                    gpointer    user_data)
{
  MprisController *self = MPRIS_CONTROLLER (user_data);
  GDBusProxy *current_proxy;

  current_proxy = self->mpris_client_proxy;
  if (current_proxy == proxy)
    return;

  if (current_proxy && mpris_client_is_playing (current_proxy))
    return;

  if (mpris_client_is_playing (proxy))
    {
      g_debug ("Switching to MPRIS client %s because it is playing",
               g_dbus_proxy_get_name (proxy));

      self->other_proxies = g_slist_remove (self->other_proxies, proxy);

      if (current_proxy)
        self->other_proxies = g_slist_prepend (self->other_proxies, current_proxy);

      self->mpris_client_proxy = proxy;

      if (!current_proxy)
        g_object_notify (user_data, "has-active-player");
    }
}

static void
mpris_proxy_ready_cb (GObject      *object,
                      GAsyncResult *res,
                      gpointer      user_data)
{
  MprisController *self = MPRIS_CONTROLLER (user_data);
  GError *error = NULL;
  GDBusProxy *proxy;
  const gchar *name;

  proxy = g_dbus_proxy_new_for_bus_finish (res, &error);

  if (!proxy)
    {
      if (!g_error_matches (error, G_IO_ERROR, G_IO_ERROR_CANCELLED))
        g_warning ("Error connecting to MPRIS interface: %s", error->message);
      g_clear_error (&error);
      return;
    }

  g_signal_connect (proxy, "notify::g-name-owner",
                    G_CALLBACK (mpris_client_notify_name_owner_cb), user_data);

  g_signal_connect (proxy, "g-properties-changed",
                    G_CALLBACK (mpris_client_properties_changed_cb), user_data);

  name = g_dbus_proxy_get_name (proxy);

  if (self->mpris_client_proxy)
    {
      if (mpris_client_is_playing (self->mpris_client_proxy))
        {
          g_debug ("Remembering %s for later because the current MPRIS client is playing",
                   name);
          self->other_proxies = g_slist_prepend (self->other_proxies, proxy);
          return;
        }

      g_debug ("Remembering the current MPRIS client for later");
      self->other_proxies =
        g_slist_prepend (self->other_proxies, self->mpris_client_proxy);
    }

  g_debug ("Switching to MPRIS client %s because it just appeared", name);

  self->mpris_client_proxy = proxy;

  g_object_notify (user_data, "has-active-player");
}

static void
start_mpris_proxy (MprisController *self, const gchar *name)
{
  g_debug ("Creating proxy for %s", name);
  g_dbus_proxy_new_for_bus (G_BUS_TYPE_SESSION,
                            0,
                            NULL,
                            name,
                            "/org/mpris/MediaPlayer2",
                            "org.mpris.MediaPlayer2.Player",
                            self->cancellable,
                            mpris_proxy_ready_cb,
                            self);
}

static void
mpris_player_appeared (GDBusConnection *connection,
                       const gchar     *name,
                       const gchar     *name_owner,
                       gpointer         user_data)
{
  start_mpris_proxy (MPRIS_CONTROLLER (user_data), name);
}

static void
mpris_controller_constructed (GObject *object)
{
  MprisController *self = MPRIS_CONTROLLER (object);

  self->namespace_watcher_id = bus_watch_namespace (G_BUS_TYPE_SESSION,
                                                    "org.mpris.MediaPlayer2",
                                                    mpris_player_appeared,
                                                    NULL,
                                                    MPRIS_CONTROLLER (object),
                                                    NULL);
}

static void
mpris_controller_get_property (GObject    *object,
                               guint       prop_id,
                               GValue     *value,
                               GParamSpec *pspec)
{
  MprisController *self = MPRIS_CONTROLLER (object);

  switch (prop_id) {
  case PROP_HAS_ACTIVE_PLAYER:
    g_value_set_boolean (value,
                         mpris_controller_get_has_active_player (self));
    break;
  default:
    G_OBJECT_WARN_INVALID_PROPERTY_ID (object, prop_id, pspec);
    break;
  }
}

static void
mpris_controller_class_init (MprisControllerClass *klass)
{
  GObjectClass *object_class = G_OBJECT_CLASS (klass);

  object_class->constructed = mpris_controller_constructed;
  object_class->dispose = mpris_controller_dispose;
  object_class->get_property = mpris_controller_get_property;

  g_object_class_install_property (object_class,
                                   PROP_HAS_ACTIVE_PLAYER,
                                   g_param_spec_boolean ("has-active-player",
                                                         NULL,
                                                         NULL,
                                                         FALSE,
                                                         G_PARAM_READABLE));
}

static void
mpris_controller_init (MprisController *self)
{
}

gboolean
mpris_controller_get_has_active_player (MprisController *controller)
{
  g_return_val_if_fail (MPRIS_IS_CONTROLLER (controller), FALSE);

  return (controller->mpris_client_proxy != NULL);
}

MprisController *
mpris_controller_new (void)
{
  return g_object_new (MPRIS_TYPE_CONTROLLER, NULL);
}
