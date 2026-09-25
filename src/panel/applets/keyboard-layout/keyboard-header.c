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

#include "keyboard-header.h"

#include <gio-unix-2.0/gio/gdesktopappinfo.h>

struct _KeyboardHeader {
	GtkBox parent_instance;

	GtkWidget* label;
	GtkWidget* button;
};

G_DEFINE_FINAL_TYPE(KeyboardHeader, keyboard_header, GTK_TYPE_BOX)

/******************************************************************************
 * Callbacks
 *****************************************************************************/

static void keyboard_header_button_clicked_cb(G_GNUC_UNUSED GtkButton* button, G_GNUC_UNUSED gpointer user_data) {
	g_autoptr(GDesktopAppInfo) app_info = NULL;
	g_autoptr(GError) error = NULL;

	app_info = g_desktop_app_info_new("budgie-keyboard-panel.desktop");

	if G_UNLIKELY (!G_IS_APP_INFO(app_info)) {
		return;
	}

	if (!g_app_info_launch(G_APP_INFO(app_info), NULL, NULL, &error)) {
		g_critical("Unable to launch keyboard settings: %s", error->message);
	}
}

/******************************************************************************
 * GObject
 *****************************************************************************/

static void keyboard_header_class_init(KeyboardHeaderClass* klass) {
	GtkWidgetClass* widget_class = GTK_WIDGET_CLASS(klass);

	gtk_widget_class_set_template_from_resource(widget_class, "/org/budgie-desktop/keyboard-layout/keyboard-header.ui");
	gtk_widget_class_bind_template_child(widget_class, KeyboardHeader, label);
	gtk_widget_class_bind_template_child(widget_class, KeyboardHeader, button);

	gtk_widget_class_bind_template_callback(widget_class, keyboard_header_button_clicked_cb);
}

static void keyboard_header_init(KeyboardHeader* self) {
	gtk_widget_init_template(GTK_WIDGET(self));
}
