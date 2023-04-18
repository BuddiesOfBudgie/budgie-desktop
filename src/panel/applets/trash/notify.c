/*
 * This file is part of budgie-desktop
 *
 * Copyright © Budgie Desktop Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#include "notify.h"

static gpointer notify_send(gpointer data) {
	NotifyNotification *noti = data;
	gboolean success;
	g_autoptr(GError) error = NULL;

	success = notify_notification_show(noti, &error);

	if (!success) {
		g_critical("Error sending notification: %s", error->message);
	}

	g_object_unref(noti);

	return NULL;
}

/**
 * trash_notify_try_send:
 * @summary: (transfer none): the notification summary
 * @body: (transfer none): the notification body
 * @icon_name: (transfer none): the icon to use for the notification
 *
 * Tries to send a notification to the user.
 *
 * If no @icon_name is passed to the function, a default icon
 * will be used.
 *
 * A thread will be spawned so that the notification will actually
 * be shown by Budgie without timing out (and locking up the system)
 * until it times out.
 */
void trash_notify_try_send(gchar *summary, gchar *body, gchar *icon_name) {
	NotifyNotification *notification;
	GThread *thread;
	g_autoptr(GError) error = NULL;

	notification = notify_notification_new(summary, body, icon_name ? icon_name : "user-trash-symbolic");
	notify_notification_set_app_name(notification, "Budgie Trash Applet");
	notify_notification_set_urgency(notification, NOTIFY_URGENCY_NORMAL);
	notify_notification_set_timeout(notification, 5000);

	thread = g_thread_try_new("trash-notify-thread", notify_send, notification, &error);

	if (!thread) {
		g_critical("Failed to spawn thread for sending a notification: %s", error->message);
		return;
	}

	g_thread_unref(thread);
}
