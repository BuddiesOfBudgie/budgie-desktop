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

#include "keyboard-applet.h"

#include "input-source.h"
#include "keyboard-popover.h"
#include "locale-manager.h"
#include "org.freedesktop.locale1.h"

#define _GNU_SOURCE

typedef enum {
	PROP_UUID = 1,
} KeyboardAppletProps;

static GParamSpec* properties[PROP_UUID + 1] = {
	NULL,
};

struct _KeyboardAppletPrivate {
	BudgiePopoverManager* popover_manager;
	KeyboardLocaleManager* locale_manager;

	gchar* uuid;

	KeyboardPopover* popover;
	GtkWidget* event_box;
	GtkWidget* event_box_stack;

	GCancellable* set_layout_cancellable;
};

G_DEFINE_DYNAMIC_TYPE_EXTENDED(KeyboardApplet, keyboard_applet, BUDGIE_TYPE_APPLET, 0, G_ADD_PRIVATE_DYNAMIC(KeyboardApplet))

/******************************************************************************
 * Callbacks
 *****************************************************************************/

static gboolean
keyboard_applet_event_box_press_cb(GtkWidget* event_button, GdkEventButton* event, gpointer user_data) {
	KeyboardApplet* self = KEYBOARD_APPLET(user_data);
	KeyboardAppletPrivate* priv;

	priv = keyboard_applet_get_instance_private(self);

	switch (event->button) {
		case 1: /* Toggle popover on left-click */
			if (gtk_widget_is_visible(priv->popover)) {
				gtk_widget_hide(priv->popover);
			} else {
				budgie_popover_manager_show_popover(priv->popover_manager, event_button);
			}
			return GDK_EVENT_STOP;
			break;
		default:
			return GDK_EVENT_PROPAGATE;
	}

	return GDK_EVENT_PROPAGATE;
}

static void keyboard_applet_keymap_set_cb(KeyboardLocale1Proxy* proxy, GAsyncResult* result, gpointer user_data) {
	KeyboardApplet* self = KEYBOARD_APPLET(user_data);
	KeyboardAppletPrivate* priv;
	gboolean success = FALSE;
	g_autoptr(GError) error = NULL;

	priv = keyboard_applet_get_instance_private(self);

	success = keyboard_locale1_call_set_x11_keyboard_finish(proxy, result, &error);

	if (!success) {
		g_warning("Unable to set keymap: %s", error->message);
		g_clear_object(&priv->set_layout_cancellable);
		return;
	}

	g_clear_object(&priv->set_layout_cancellable);
}

static void
keyboard_applet_layout_selected_cb(G_GNUC_UNUSED KeyboardPopover* popover, KeyboardInputSource* source, gpointer user_data) {
	KeyboardApplet* self = KEYBOARD_APPLET(user_data);
	KeyboardAppletPrivate* priv;
	gchar* layout = NULL;
	gchar* variant = NULL;
	gchar* options = NULL;
	KeyboardLocale1Proxy* proxy = NULL;

	if (source == NULL) {
		return;
	}

	priv = keyboard_applet_get_instance_private(self);

	if (priv->set_layout_cancellable != NULL) {
		g_debug("Keyboard layout setting already in progress");
		return;
	}

	proxy = keyboard_locale_manager_get_proxy(priv->locale_manager);
	layout = keyboard_input_source_get_layout(source);
	variant = keyboard_input_source_get_variant(source);

	if (keyboard_input_source_has_options(source)) {
		options = keyboard_input_source_get_options(source);
	} else {
		options = "";
	}

	priv->set_layout_cancellable = g_cancellable_new();

	keyboard_locale1_call_set_x11_keyboard(
		proxy,
		layout,
		"", /* model */
		variant,
		options,
		TRUE,  /* convert */
		FALSE, /* interactive */
		priv->set_layout_cancellable,
		(GAsyncReadyCallback) keyboard_applet_keymap_set_cb,
		user_data);
}

static void
keyboard_applet_current_input_changed_cb(KeyboardLocaleManager* manager, GParamSpec* pspec, gpointer user_data) {
	KeyboardApplet* self = KEYBOARD_APPLET(user_data);
	KeyboardAppletPrivate* priv;
	KeyboardInputSource* source = NULL;

	g_return_if_fail(KEYBOARD_IS_APPLET(self));

	priv = keyboard_applet_get_instance_private(self);

	if (g_str_equal(pspec->name, "current-source")) {
		source = keyboard_locale_manager_get_current_input_source(manager);

		keyboard_popover_set_current_source(priv->popover, source);
	}
}

/******************************************************************************
 * GObject
 *****************************************************************************/

static gboolean keyboard_applet_supports_settings(BudgieApplet* base) {
	return FALSE;
}

static void keyboard_applet_update_popovers(BudgieApplet* base, BudgiePopoverManager* manager) {
	KeyboardApplet* self = KEYBOARD_APPLET(base);
	KeyboardAppletPrivate* priv;

	priv = keyboard_applet_get_instance_private(self);

	budgie_popover_manager_register_popover(
		manager,
		priv->event_box,
		priv->popover);

	priv->popover_manager = manager;
}

static void keyboard_applet_dispose(GObject* object) {
	KeyboardApplet* self;
	KeyboardAppletPrivate* priv;

	self = KEYBOARD_APPLET(object);
	priv = keyboard_applet_get_instance_private(self);

	g_cancellable_cancel(priv->set_layout_cancellable);

	g_clear_object(&priv->locale_manager);
	g_clear_pointer(&priv->uuid, g_free);

	G_OBJECT_CLASS(keyboard_applet_parent_class)->dispose(object);
}

static void keyboard_applet_get_property(GObject* obj, guint prop_id, GValue* val, GParamSpec* spec) {
	KeyboardApplet* self = KEYBOARD_APPLET(obj);

	switch ((KeyboardAppletProps) prop_id) {
		case PROP_UUID:
			g_value_set_string(val, keyboard_applet_get_uuid(self));
			break;
	}
}

static void keyboard_applet_set_property(GObject* obj, guint prop_id, const GValue* val, GParamSpec* spec) {
	KeyboardApplet* self = KEYBOARD_APPLET(obj);

	switch ((KeyboardAppletProps) prop_id) {
		case PROP_UUID:
			keyboard_applet_set_uuid(self, g_value_get_string(val));
			break;
	}
}

static void keyboard_applet_class_finalize(G_GNUC_UNUSED KeyboardAppletClass* klass) {}

static void keyboard_applet_class_init(KeyboardAppletClass* klass) {
	GObjectClass* class;
	BudgieAppletClass* applet_class;

	class = G_OBJECT_CLASS(klass);
	applet_class = BUDGIE_APPLET_CLASS(klass);

	class->dispose = keyboard_applet_dispose;
	class->get_property = keyboard_applet_get_property;
	class->set_property = keyboard_applet_set_property;

	applet_class->update_popovers = keyboard_applet_update_popovers;
	applet_class->supports_settings = keyboard_applet_supports_settings;

	/**
	 * KeyboardApplet:uuid:
	 *
	 * The UUID for the applet.
	 *
	 * The UUID is used to get the per-instance settings for the applet.
	 */
	properties[PROP_UUID] = g_param_spec_string(
		"uuid",
		NULL,
		NULL,
		NULL,
		G_PARAM_CONSTRUCT_ONLY | G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS);

	g_object_class_install_properties(class, G_N_ELEMENTS(properties), properties);
}

static void keyboard_applet_init(KeyboardApplet* self) {
	KeyboardAppletPrivate* priv;
	GtkWidget* event_box_content;
	GtkWidget* event_box_image;
	GtkStyleContext* style_context;
	GListStore* model = NULL;

	priv = keyboard_applet_get_instance_private(self);

	self->priv = priv;

	style_context = gtk_widget_get_style_context(GTK_WIDGET(self));
	gtk_style_context_add_class(style_context, "keyboard-indicator");

	/* Panel widget UI */
	event_box_image = gtk_image_new_from_icon_name("input-keyboard-symbolic", GTK_ICON_SIZE_MENU);
	priv->event_box_stack = gtk_stack_new();
	gtk_stack_set_transition_type(GTK_STACK(priv->event_box_stack), GTK_STACK_TRANSITION_TYPE_SLIDE_UP_DOWN);

	event_box_content = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
	gtk_box_pack_start(GTK_BOX(event_box_content), event_box_image, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(event_box_content), priv->event_box_stack, FALSE, FALSE, 0);

	priv->event_box = gtk_event_box_new();
	g_signal_connect(priv->event_box, "button-press-event", G_CALLBACK(keyboard_applet_event_box_press_cb), self);

	gtk_container_add(GTK_CONTAINER(priv->event_box), event_box_content);
	gtk_container_add(GTK_CONTAINER(self), priv->event_box);

	/* Keyboard popover */
	priv->locale_manager = keyboard_locale_manager_new();

	model = keyboard_locale_manager_get_model(priv->locale_manager);

	priv->popover = keyboard_popover_new(GTK_WIDGET(priv->event_box), model);
	g_signal_connect(priv->popover, "layout-selected", keyboard_applet_layout_selected_cb, self);

	g_signal_connect_object(priv->locale_manager, "notify::current-source", G_CALLBACK(keyboard_applet_current_input_changed_cb), self, G_CONNECT_DEFAULT);
	keyboard_locale_manager_start(priv->locale_manager);

	gtk_widget_show_all(GTK_WIDGET(self));
}

/******************************************************************************
 * Public API
 *****************************************************************************/

void keyboard_applet_init_gtype(GTypeModule* module) {
	keyboard_applet_register_type(module);
}

/**
 * keyboard_applet_new:
 * @uuid: a UUID
 *
 * Creates a new #KeyboardApplet object.
 *
 * Returns: (transfer full): A new #KeyboardApplet object
 */
KeyboardApplet* keyboard_applet_new(const gchar* uuid) {
	return g_object_new(KEYBOARD_TYPE_APPLET, "uuid", uuid, NULL);
}

/**
 * keyboard_applet_get_uuid:
 * @self: a #KeyboardApplet
 *
 * Get the UUID of @self.
 *
 * Returns: (type gchar *) (transfer full): The UUID
 */
gchar* keyboard_applet_get_uuid(KeyboardApplet* self) {
	KeyboardAppletPrivate* priv;

	g_return_val_if_fail(KEYBOARD_IS_APPLET(self), NULL);

	priv = keyboard_applet_get_instance_private(self);

	return g_strdup(priv->uuid);
}

/**
 * keyboard_applet_set_uuid:
 * @self: a #KeyboardApplet
 * @value: (transfer full): a UUID
 *
 * Set the UUID for this applet instance.
 */
void keyboard_applet_set_uuid(KeyboardApplet* self, const gchar* uuid) {
	KeyboardAppletPrivate* priv;

	g_return_if_fail(KEYBOARD_IS_APPLET(self));
	g_return_if_fail(uuid != NULL);

	priv = keyboard_applet_get_instance_private(self);

	if (g_set_str(&priv->uuid, uuid)) {
		g_object_notify_by_pspec(G_OBJECT(self), properties[PROP_UUID]);
	}
}
