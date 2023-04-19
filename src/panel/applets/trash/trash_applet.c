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

#include "trash_applet.h"

#define _GNU_SOURCE

enum {
	PROP_UUID = 1,
	LAST_PROP
};

static GParamSpec *props[LAST_PROP] = {
	NULL,
};

struct _TrashAppletPrivate {
	BudgiePopoverManager *manager;

	gchar *uuid;

	GtkWidget *popover;
	GtkWidget *icon_button;
};

G_DEFINE_DYNAMIC_TYPE_EXTENDED(TrashApplet, trash_applet, BUDGIE_TYPE_APPLET, 0, G_ADD_PRIVATE_DYNAMIC(TrashApplet))

static void trash_empty_cb(TrashPopover *source, gpointer user_data) {
	(void) source;
	TrashApplet *self = user_data;
	GtkWidget *image;

	image = gtk_image_new_from_icon_name("user-trash-symbolic", GTK_ICON_SIZE_MENU);

	gtk_button_set_image(GTK_BUTTON(self->priv->icon_button), image);
}

static void trash_filled_cb(TrashPopover *source, gpointer user_data) {
	(void) source;
	TrashApplet *self = user_data;
	GtkWidget *image;

	image = gtk_image_new_from_icon_name("user-trash-full-symbolic", GTK_ICON_SIZE_MENU);

	gtk_button_set_image(GTK_BUTTON(self->priv->icon_button), image);
}

static void trash_applet_constructed(GObject *object) {
	TrashApplet *self = TRASH_APPLET(object);
	TrashPopover *popover_body;

	// Set our settings schema and prefix
	g_object_set(self,
		"settings-schema", "com.solus-project.trash",
		"settings-prefix", "/com/solus-project/budgie-panel/instance/trash",
		NULL);
	self->settings = budgie_applet_get_applet_settings(BUDGIE_APPLET(self), self->priv->uuid);

	// Create our popover widget
	self->priv->popover = budgie_popover_new(GTK_WIDGET(self->priv->icon_button));
	popover_body = trash_popover_new(self->settings);
	gtk_container_add(GTK_CONTAINER(self->priv->popover), GTK_WIDGET(popover_body));

	g_signal_connect(popover_body, "trash-empty", G_CALLBACK(trash_empty_cb), self);
	g_signal_connect(popover_body, "trash-filled", G_CALLBACK(trash_filled_cb), self);

	G_OBJECT_CLASS(trash_applet_parent_class)->constructed(object);
}

/**
 * Handle cleanup of the applet.
 */
static void trash_applet_finalize(GObject *object) {
	TrashApplet *self;
	TrashAppletPrivate *priv;

	self = TRASH_APPLET(object);
	priv = trash_applet_get_instance_private(self);

	g_free(priv->uuid);

	if (self->settings) {
		g_object_unref(self->settings);
	}

	G_OBJECT_CLASS(trash_applet_parent_class)->finalize(object);
}

static void trash_applet_get_property(GObject *obj, guint prop_id, GValue *val, GParamSpec *spec) {
	TrashApplet *self = TRASH_APPLET(obj);

	switch (prop_id) {
		case PROP_UUID:
			g_value_set_string(val, self->priv->uuid);
			break;
		default:
			G_OBJECT_WARN_INVALID_PROPERTY_ID(obj, prop_id, spec);
			break;
	}
}

static void trash_applet_set_property(GObject *obj, guint prop_id, const GValue *val, GParamSpec *spec) {
	TrashApplet *self = TRASH_APPLET(obj);

	switch (prop_id) {
		case PROP_UUID:
			trash_applet_set_uuid(self, g_value_get_string(val));
			break;
		default:
			G_OBJECT_WARN_INVALID_PROPERTY_ID(obj, prop_id, spec);
			break;
	}
}

static GtkWidget *trash_applet_get_settings_ui(BudgieApplet *base) {
	TrashApplet *self = TRASH_APPLET(base);
	TrashSettings *trash_settings;

	trash_settings = trash_settings_new(self->settings);
	g_object_ref_sink(trash_settings);

	return GTK_WIDGET(trash_settings);
}

static gboolean trash_applet_supports_settings(BudgieApplet *base) {
	(void) base;
	return TRUE;
}

/**
 * Register our popover with the Budgie popover manager.
 */
static void update_popovers(BudgieApplet *base, BudgiePopoverManager *manager) {
	TrashApplet *self = TRASH_APPLET(base);
	budgie_popover_manager_register_popover(manager,
		GTK_WIDGET(self->priv->icon_button),
		BUDGIE_POPOVER(self->priv->popover));
	self->priv->manager = manager;
}

/**
 * Initialize the Trash Applet class.
 */
static void trash_applet_class_init(TrashAppletClass *klass) {
	GObjectClass *class;
	BudgieAppletClass *budgie_class;

	class = G_OBJECT_CLASS(klass);
	budgie_class = BUDGIE_APPLET_CLASS(klass);

	class->constructed = trash_applet_constructed;
	class->finalize = trash_applet_finalize;
	class->get_property = trash_applet_get_property;
	class->set_property = trash_applet_set_property;

	budgie_class->update_popovers = update_popovers;
	budgie_class->supports_settings = trash_applet_supports_settings;
	budgie_class->get_settings_ui = trash_applet_get_settings_ui;

	/**
	 * TrashApplet:uuid:
	 *
	 * The UUID for the applet.
	 *
	 * The UUID is used to get the per-instance settings for the applet.
	 */
	props[PROP_UUID] = g_param_spec_string(
		"uuid",
		"uuid",
		"The applet's UUID",
		NULL,
		G_PARAM_CONSTRUCT_ONLY | G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS);

	g_object_class_install_properties(class, LAST_PROP, props);
}

/**
 * Handle cleanup of the applet class.
 */
static void trash_applet_class_finalize(__budgie_unused__ TrashAppletClass *klass) {
	notify_uninit();
}

static void toggle_popover(__budgie_unused__ GtkButton *sender, TrashApplet *self) {
	if (gtk_widget_is_visible(self->priv->popover)) {
		gtk_widget_hide(self->priv->popover);
	} else {
		budgie_popover_manager_show_popover(self->priv->manager, GTK_WIDGET(self->priv->icon_button));
	}
}

static void drag_data_received(
	__budgie_unused__ TrashApplet *self,
	GdkDragContext *context,
	__budgie_unused__ gint x,
	__budgie_unused__ gint y,
	GtkSelectionData *data,
	guint info,
	guint time) {
	g_return_if_fail(info == 0);

	g_autofree gchar *uri = g_strdup((gchar *) gtk_selection_data_get_data(data));
	g_autofree gchar *unescaped = NULL;
	g_autoptr(GFile) file = NULL;
	g_autoptr(GError) err = NULL;

	if (g_str_has_prefix(uri, "file://")) {
		unescaped = g_uri_unescape_string(uri, NULL);
		g_strstrip(unescaped); // Make sure there's nothing silly like a trailing newline
		file = g_file_new_for_uri(unescaped);

		if (!g_file_trash(file, NULL, &err)) {
			trash_notify_try_send("Error Trashing File", err->message, "dialog-error-symbolic");
			g_critical("%s:%d: Error moving file to trash: %s", __BASE_FILE__, __LINE__, err->message);
			return;
		}
	}

	gtk_drag_finish(context, TRUE, TRUE, time);
}

/**
 * Initialization of basic UI elements and loads our CSS
 * style stuff.
 */
static void trash_applet_init(TrashApplet *self) {
	GtkStyleContext *button_style;

	// Create our 'private' struct
	self->priv = trash_applet_get_instance_private(self);

	// Create our panel widget
	self->priv->icon_button = gtk_button_new_from_icon_name("user-trash-symbolic", GTK_ICON_SIZE_MENU);
	gtk_widget_set_tooltip_text(self->priv->icon_button, "Trash");

	g_signal_connect(self->priv->icon_button, "clicked", G_CALLBACK(toggle_popover), self);

	button_style = gtk_widget_get_style_context(self->priv->icon_button);
	gtk_style_context_add_class(button_style, GTK_STYLE_CLASS_FLAT);
	gtk_style_context_remove_class(button_style, GTK_STYLE_CLASS_BUTTON);

	gtk_container_add(GTK_CONTAINER(self), GTK_WIDGET(self->priv->icon_button));

	gtk_widget_show_all(GTK_WIDGET(self));

	// Register notifications
	notify_init("org.buddiesofbudgie.budgie-desktop.trash-applet");

	// Setup drag and drop to trash files
	gtk_drag_dest_set(GTK_WIDGET(self),
		GTK_DEST_DEFAULT_ALL,
		gtk_target_entry_new("text/uri-list", 0, 0),
		1,
		GDK_ACTION_COPY);

	g_signal_connect_object(self, "drag-data-received", G_CALLBACK(drag_data_received), self, 0);
}

/**
 * trash_applet_init_gtype:
 * @module: a #GTypeModule
 *
 * Initializes and registers the #GType for a #TrashApplet object.
 */
void trash_applet_init_gtype(GTypeModule *module) {
	trash_applet_register_type(module);
}

/**
 * trash_applet_new:
 * @uuid: a UUID
 *
 * Creates a new #TrashApplet object.
 *
 * Returns: a new #TrashApplet object
 */
TrashApplet *trash_applet_new(const gchar *uuid) {
	return g_object_new(TRASH_TYPE_APPLET, "uuid", uuid, NULL);
}

/**
 * trash_applet_get_uuid:
 * @self: a #TrashApplet
 *
 * Get the UUID of @self.
 *
 * Returns: (type gchar *) (transfer full): the UUID
 */
gchar *trash_applet_get_uuid(TrashApplet *self) {
	g_return_val_if_fail(TRASH_IS_APPLET(self), NULL);

	return g_strdup(self->priv->uuid);
}

/**
 * trash_applet_set_uuid:
 * @self: a #TrashApplet
 * @value: (transfer full): a UUID
 *
 * Set the UUID for this applet instance.
 */
void trash_applet_set_uuid(TrashApplet *self, const gchar *value) {
	g_return_if_fail(TRASH_IS_APPLET(self));
	g_return_if_fail(value != NULL);

	if (self->priv->uuid) {
		g_free(self->priv->uuid);
	}

	self->priv->uuid = g_strdup(value);
}
