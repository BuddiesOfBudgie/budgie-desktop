/*
 * Copyright 2013 Canonical Ltd.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Author: Lars Uebernickel <lars.uebernickel@canonical.com>
 */

#include <gio/gio.h>
#include <string.h>
#include "bus-watch-namespace.h"

typedef struct
{
  guint                     id;
  gchar                    *name_space;
  GBusNameAppearedCallback  appeared_handler;
  GBusNameVanishedCallback  vanished_handler;
  gpointer                  user_data;
  GDestroyNotify            user_data_destroy;

  GDBusConnection          *connection;
  GCancellable             *cancellable;
  GHashTable               *names;
  guint                     subscription_id;
} NamespaceWatcher;

typedef struct
{
  NamespaceWatcher *watcher;
  gchar            *name;
} GetNameOwnerData;

static guint namespace_watcher_next_id;
static GHashTable *namespace_watcher_watchers;

static void
namespace_watcher_stop (gpointer data)
{
  NamespaceWatcher *watcher = data;

  g_cancellable_cancel (watcher->cancellable);
  g_object_unref (watcher->cancellable);

  if (watcher->subscription_id)
    g_dbus_connection_signal_unsubscribe (watcher->connection, watcher->subscription_id);

  if (watcher->vanished_handler)
    {
      GHashTableIter it;
      const gchar *name;

      g_hash_table_iter_init (&it, watcher->names);
      while (g_hash_table_iter_next (&it, (gpointer *) &name, NULL))
        watcher->vanished_handler (watcher->connection, name, watcher->user_data);
    }

  if (watcher->user_data_destroy)
    watcher->user_data_destroy (watcher->user_data);

  if (watcher->connection)
    {
      g_signal_handlers_disconnect_by_func (watcher->connection, namespace_watcher_stop, watcher);
      g_object_unref (watcher->connection);
    }

  g_hash_table_unref (watcher->names);

  g_hash_table_remove (namespace_watcher_watchers, GUINT_TO_POINTER (watcher->id));
  if (g_hash_table_size (namespace_watcher_watchers) == 0)
    g_clear_pointer (&namespace_watcher_watchers, g_hash_table_destroy);

  g_free (watcher);
}

static void
namespace_watcher_name_appeared (NamespaceWatcher *watcher,
                                 const gchar      *name,
                                 const gchar      *owner)
{
  /* There's a race between NameOwnerChanged signals arriving and the
   * ListNames/GetNameOwner sequence returning, so this function might
   * be called more than once for the same name. To ensure that
   * appeared_handler is only called once for each name, it is only
   * called when inserting the name into watcher->names (each name is
   * only inserted once there).
   */
  if (g_hash_table_contains (watcher->names, name))
    return;

  g_hash_table_add (watcher->names, g_strdup (name));

  if (watcher->appeared_handler)
    watcher->appeared_handler (watcher->connection, name, owner, watcher->user_data);
}

static void
namespace_watcher_name_vanished (NamespaceWatcher *watcher,
                                 const gchar      *name)
{
  if (g_hash_table_remove (watcher->names, name) && watcher->vanished_handler)
    watcher->vanished_handler (watcher->connection, name, watcher->user_data);
}

static gboolean
dbus_name_has_namespace (const gchar *name,
                         const gchar *name_space)
{
  gint len_name;
  gint len_namespace;

  len_name = strlen (name);
  len_namespace = strlen (name_space);

  if (len_name < len_namespace)
    return FALSE;

  if (memcmp (name_space, name, len_namespace) != 0)
    return FALSE;

  return len_namespace == len_name || name[len_namespace] == '.';
}

static void
name_owner_changed (GDBusConnection *connection,
                    const gchar     *sender_name,
                    const gchar     *object_path,
                    const gchar     *interface_name,
                    const gchar     *signal_name,
                    GVariant        *parameters,
                    gpointer         user_data)
{
  NamespaceWatcher *watcher = user_data;
  const gchar *name;
  const gchar *old_owner;
  const gchar *new_owner;

  g_variant_get (parameters, "(&s&s&s)", &name, &old_owner, &new_owner);

  if (old_owner[0] != '\0')
    namespace_watcher_name_vanished (watcher, name);

  if (new_owner[0] != '\0')
    namespace_watcher_name_appeared (watcher, name, new_owner);
}

static void
got_name_owner (GObject      *object,
                GAsyncResult *result,
                gpointer      user_data)
{
  GetNameOwnerData *data = user_data;
  GError *error = NULL;
  GVariant *reply;
  const gchar *owner;

  reply = g_dbus_connection_call_finish (G_DBUS_CONNECTION (object), result, &error);

  if (g_error_matches (error, G_IO_ERROR, G_IO_ERROR_CANCELLED))
    {
      g_error_free (error);
      goto out;
    }

  if (reply == NULL)
    {
      if (!g_error_matches (error, G_DBUS_ERROR, G_DBUS_ERROR_NAME_HAS_NO_OWNER))
        g_warning ("bus_watch_namespace: error calling org.freedesktop.DBus.GetNameOwner: %s", error->message);
      g_error_free (error);
      goto out;
    }

  g_variant_get (reply, "(&s)", &owner);
  namespace_watcher_name_appeared (data->watcher, data->name, owner);

  g_variant_unref (reply);

out:
  g_free (data->name);
  g_free (data);
}

static void
names_listed (GObject      *object,
              GAsyncResult *result,
              gpointer      user_data)
{
  NamespaceWatcher *watcher;
  GError *error = NULL;
  GVariant *reply;
  GVariantIter *iter;
  const gchar *name;

  reply = g_dbus_connection_call_finish (G_DBUS_CONNECTION (object), result, &error);

  if (g_error_matches (error, G_IO_ERROR, G_IO_ERROR_CANCELLED))
    {
      g_error_free (error);
      return;
    }

  watcher = user_data;

  if (reply == NULL)
    {
      g_warning ("bus_watch_namespace: error calling org.freedesktop.DBus.ListNames: %s", error->message);
      g_error_free (error);
      return;
    }

  g_variant_get (reply, "(as)", &iter);
  while (g_variant_iter_next (iter, "&s", &name))
    {
      if (dbus_name_has_namespace (name, watcher->name_space))
        {
          GetNameOwnerData *data = g_new (GetNameOwnerData, 1);
          data->watcher = watcher;
          data->name = g_strdup (name);
          g_dbus_connection_call (watcher->connection, "org.freedesktop.DBus", "/",
                                  "org.freedesktop.DBus", "GetNameOwner",
                                  g_variant_new ("(s)", name), G_VARIANT_TYPE ("(s)"),
                                  G_DBUS_CALL_FLAGS_NONE, -1, watcher->cancellable,
                                  got_name_owner, data);
        }
    }

  g_variant_iter_free (iter);
  g_variant_unref (reply);
}

static void
connection_closed (GDBusConnection *connection,
                   gboolean         remote_peer_vanished,
                   GError          *error,
                   gpointer         user_data)
{
  NamespaceWatcher *watcher = user_data;

  namespace_watcher_stop (watcher);
}

static void
got_bus (GObject      *object,
         GAsyncResult *result,
         gpointer      user_data)
{
  GDBusConnection *connection;
  NamespaceWatcher *watcher;
  GError *error = NULL;

  connection = g_bus_get_finish (result, &error);

  if (g_error_matches (error, G_IO_ERROR, G_IO_ERROR_CANCELLED))
    {
      g_error_free (error);
      return;
    }

  watcher = user_data;

  if (connection == NULL)
    {
      namespace_watcher_stop (watcher);
      return;
    }

  watcher->connection = connection;
  g_signal_connect (watcher->connection, "closed", G_CALLBACK (connection_closed), watcher);

  watcher->subscription_id =
    g_dbus_connection_signal_subscribe (watcher->connection, "org.freedesktop.DBus",
                                        "org.freedesktop.DBus", "NameOwnerChanged", "/org/freedesktop/DBus",
                                        watcher->name_space, G_DBUS_SIGNAL_FLAGS_MATCH_ARG0_NAMESPACE,
                                        name_owner_changed, watcher, NULL);

  g_dbus_connection_call (watcher->connection, "org.freedesktop.DBus", "/",
                          "org.freedesktop.DBus", "ListNames", NULL, G_VARIANT_TYPE ("(as)"),
                          G_DBUS_CALL_FLAGS_NONE, -1, watcher->cancellable,
                          names_listed, watcher);
}

guint
bus_watch_namespace (GBusType                  bus_type,
                     const gchar              *name_space,
                     GBusNameAppearedCallback  appeared_handler,
                     GBusNameVanishedCallback  vanished_handler,
                     gpointer                  user_data,
                     GDestroyNotify            user_data_destroy)
{
  NamespaceWatcher *watcher;

  /* same rules for interfaces and well-known names */
  g_return_val_if_fail (name_space != NULL && g_dbus_is_interface_name (name_space), 0);
  g_return_val_if_fail (appeared_handler || vanished_handler, 0);

  watcher = g_new0 (NamespaceWatcher, 1);
  watcher->id = namespace_watcher_next_id++;
  watcher->name_space = g_strdup (name_space);
  watcher->appeared_handler = appeared_handler;
  watcher->vanished_handler = vanished_handler;
  watcher->user_data = user_data;
  watcher->user_data_destroy = user_data_destroy;
  watcher->cancellable = g_cancellable_new ();;
  watcher->names = g_hash_table_new_full (g_str_hash, g_str_equal, g_free, NULL);

  if (namespace_watcher_watchers == NULL)
    namespace_watcher_watchers = g_hash_table_new (g_direct_hash, g_direct_equal);
  g_hash_table_insert (namespace_watcher_watchers, GUINT_TO_POINTER (watcher->id), watcher);

  g_bus_get (bus_type, watcher->cancellable, got_bus, watcher);

  return watcher->id;
}

void
bus_unwatch_namespace (guint id)
{
  /* namespace_watcher_stop() might have already removed the watcher
   * with @id in the case of a connection error. Thus, this function
   * doesn't warn when @id is absent from the hash table.
   */

  if (namespace_watcher_watchers)
    {
      NamespaceWatcher *watcher;

      watcher = g_hash_table_lookup (namespace_watcher_watchers, GUINT_TO_POINTER (id));
      if (watcher)
        {
          /* make sure vanished() is not called as a result of this function */
          g_hash_table_remove_all (watcher->names);

          namespace_watcher_stop (watcher);
        }
    }
}
