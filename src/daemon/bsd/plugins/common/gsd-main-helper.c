/**
 * Create a gnome-settings-daemon helper easily
 *
 * #include "gsd-main-helper.h"
 * #include "gsd-media-keys-manager.h"
 *
 * int
 * main (int argc, char **argv)
 * {
 *         return gsd_main_helper (GSD_TYPE_MEDIA_KEYS_MANAGER, argc, argv);
 * }
 */

#include "config.h"

#include "gsd-main-helper.h"

#include <stdlib.h>
#include <stdio.h>
#include <locale.h>

#include <glib-unix.h>
#include <glib/gi18n.h>
#ifdef USE_GTK
#include <gtk/gtk.h>
#endif

#include "gnome-settings-bus.h"

#ifdef USE_GTK
#include "gsd-resources.h"
#endif

#ifndef PLUGIN_NAME
#error Include PLUGIN_CFLAGS in the daemon s CFLAGS
#endif /* !PLUGIN_NAME */

#ifndef PLUGIN_DBUS_NAME
#error Include PLUGIN_DBUS_NAME in the daemon s CFLAGS
#endif /* !PLUGIN_DBUS_NAME */

#define GNOME_SESSION_DBUS_NAME                     "org.gnome.SessionManager"
#define GNOME_SESSION_CLIENT_PRIVATE_DBUS_INTERFACE "org.gnome.SessionManager.ClientPrivate"

static int timeout = -1;
static char *dummy_name = NULL;
static gboolean verbose = FALSE;

static GOptionEntry entries[] = {
        { "exit-time", 0, 0, G_OPTION_ARG_INT, &timeout, "Exit after n seconds time", NULL },
        { "dummy-name", 0, 0, G_OPTION_ARG_STRING, &dummy_name, "Name when using the dummy daemon", NULL },
        { "verbose", 'v', 0, G_OPTION_ARG_NONE, &verbose, "Verbose", NULL },
        {NULL}
};

static void
on_activate (GApplication *manager)
{
        g_debug ("Daemon activated");
}

static void
register_activate (GApplication *manager)
{
        g_signal_connect (manager, "activate", G_CALLBACK (on_activate), NULL);
}

static void
register_timeout (GApplication *manager)
{
        if (timeout > 0) {
                guint id;
                id = g_timeout_add_seconds (timeout, (GSourceFunc) g_application_release, manager);
                g_source_set_name_by_id (id, "[gnome-settings-daemon] g_application_release");
        }
}

static gboolean
handle_sigterm (gpointer user_data)
{
  GApplication *manager = user_data;

  g_debug ("Got SIGTERM; shutting down ...");

  g_application_release (manager);

  return G_SOURCE_REMOVE;
}

static void
install_signal_handler (GApplication *manager)
{
  g_autoptr (GSource) source = NULL;

  source = g_unix_signal_source_new (SIGTERM);

  g_source_set_callback (source, handle_sigterm, manager, NULL);
  g_source_attach (source, NULL);
}

static void
respond_to_end_session (GDBusProxy *proxy)
{
        /* we must answer with "EndSessionResponse" */
        g_dbus_proxy_call (proxy, "EndSessionResponse",
                           g_variant_new ("(bs)", TRUE, ""),
                           G_DBUS_CALL_FLAGS_NONE,
                           -1, NULL, NULL, NULL);
}

static void
client_proxy_signal_cb (GDBusProxy *proxy,
                        gchar *sender_name,
                        gchar *signal_name,
                        GVariant *parameters,
                        gpointer user_data)
{
        GApplication *manager = user_data;

        if (g_strcmp0 (signal_name, "QueryEndSession") == 0) {
                g_debug ("Got QueryEndSession signal");
                respond_to_end_session (proxy);
        } else if (g_strcmp0 (signal_name, "EndSession") == 0) {
                g_debug ("Got EndSession signal");
                respond_to_end_session (proxy);
        } else if (g_strcmp0 (signal_name, "Stop") == 0) {
                g_debug ("Got Stop signal");
                g_application_release (manager);
        }
}

static void
on_client_registered (GObject             *source_object,
                      GAsyncResult        *res,
                      gpointer             user_data)
{
        GVariant *variant;
        GDBusProxy *client_proxy;
        GError *error = NULL;
        gchar *object_path = NULL;

        variant = g_dbus_proxy_call_finish (G_DBUS_PROXY (source_object), res, &error);
        if (!variant) {
                g_warning ("Unable to register client: %s", error->message);
                g_error_free (error);
                return;
        }

        g_variant_get (variant, "(o)", &object_path);

        g_debug ("Registered client at path %s", object_path);

        client_proxy = g_dbus_proxy_new_for_bus_sync (G_BUS_TYPE_SESSION, 0, NULL,
                                                      GNOME_SESSION_DBUS_NAME,
                                                      object_path,
                                                      GNOME_SESSION_CLIENT_PRIVATE_DBUS_INTERFACE,
                                                      NULL,
                                                      &error);
        if (!client_proxy) {
                g_warning ("Unable to get the session client proxy: %s", error->message);
                g_error_free (error);
                return;
        }

        g_signal_connect (client_proxy, "g-signal",
                          G_CALLBACK (client_proxy_signal_cb), user_data);

        g_free (object_path);
        g_variant_unref (variant);
}

static void
register_with_gnome_session (GApplication *manager)
{
	GDBusProxy *proxy;
	const char *startup_id;

	proxy = G_DBUS_PROXY (gnome_settings_bus_get_session_proxy ());
	startup_id = g_getenv ("DESKTOP_AUTOSTART_ID");
	g_dbus_proxy_call (proxy,
			   "RegisterClient",
			   g_variant_new ("(ss)", dummy_name ? dummy_name : PLUGIN_NAME, startup_id ? startup_id : ""),
			   G_DBUS_CALL_FLAGS_NONE,
			   -1,
			   NULL,
			   (GAsyncReadyCallback) on_client_registered,
			   manager);

	/* DESKTOP_AUTOSTART_ID must not leak into child processes, because
	 * it can't be reused. Child processes will not know whether this is
	 * a genuine value or erroneous already-used value. */
	g_unsetenv ("DESKTOP_AUTOSTART_ID");
}

#ifdef USE_GTK
static void
set_empty_gtk_theme (gboolean set)
{
        static char *old_gtk_theme = NULL;

        if (set) {
                /* Override GTK_THEME to reduce overhead of CSS engine. By using
                 * GTK_THEME environment variable, GtkSettings is not allowed to
                 * initially parse the Adwaita theme.
                 *
                 * https://bugzilla.gnome.org/show_bug.cgi?id=780555 */
                old_gtk_theme = g_strdup (g_getenv ("GTK_THEME"));
                g_setenv ("GTK_THEME", "Disabled", TRUE);
        } else {
                /* GtkSettings has loaded, so we can drop GTK_THEME used to initialize
                 * our internal theme. Only the main thread accesses the GTK_THEME
                 * environment variable, so this is safe to release. */
                if (old_gtk_theme != NULL)
                        g_setenv ("GTK_THEME", old_gtk_theme, TRUE);
                else
                        g_unsetenv ("GTK_THEME");
        }
}
#endif

static int
start (GApplication  *manager,
       int            argc,
       char         **argv)
{
        g_autoptr (GError) error = NULL;

        if (G_IS_INITABLE (manager) &&
            !g_initable_init (G_INITABLE (manager), NULL, &error)) {
                g_printerr ("Failed to start: %s\n", error->message);
                exit (1);
        }

        g_application_hold (manager);

        return g_application_run (manager, argc, argv);
}

int
gsd_main_helper (GType        manager_type,
                 int          argc,
                 char       **argv)
{
        g_autoptr (GError) error = NULL;
        g_autoptr (GOptionContext) context = NULL;
        g_autoptr (GApplication) manager = NULL;

        bindtextdomain (GETTEXT_PACKAGE, GNOME_SETTINGS_LOCALEDIR);
        bind_textdomain_codeset (GETTEXT_PACKAGE, "UTF-8");
        textdomain (GETTEXT_PACKAGE);
        setlocale (LC_ALL, "");

#ifdef USE_GTK
        /* Ensure we don't lose resources during linkage */
        g_resources_register (gsd_get_resource ());

        set_empty_gtk_theme (TRUE);

        if (! gtk_init_with_args (&argc, &argv, PLUGIN_NAME, entries, NULL, &error)) {
                if (error != NULL) {
                        g_printerr ("%s\n", error->message);
                }
                exit (1);
        }

        set_empty_gtk_theme (FALSE);
#else
        context = g_option_context_new (NULL);
        g_option_context_add_main_entries (context, entries, GETTEXT_PACKAGE);
        if (!g_option_context_parse (context, &argc, &argv, &error)) {
                g_printerr ("%s\n", error->message);
                exit (1);
        }
#endif

        if (verbose) {
                g_setenv ("G_MESSAGES_DEBUG", "all", TRUE);
                /* Work around GLib not flushing the output for us by explicitly
                 * setting buffering to a sane behaviour. This is important
                 * during testing when the output is not going to a TTY and
                 * we are reading messages from g_debug on stdout.
                 *
                 * See also
                 *  https://bugzilla.gnome.org/show_bug.cgi?id=792432
                 */
                setlinebuf (stdout);
        }

        manager = g_object_new (manager_type,
                                "application-id", PLUGIN_DBUS_NAME,
                                NULL);

        register_activate (manager);
        register_timeout (manager);
        install_signal_handler (manager);
        register_with_gnome_session (manager);

        return start (manager, argc, argv);
}
