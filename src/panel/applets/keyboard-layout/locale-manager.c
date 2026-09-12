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

#include "locale-manager.h"

#include <libgnome-desktop/gnome-languages.h>
#include <libgnome-desktop/gnome-xkb-info.h>

#include "input-source.h"
#include "org.freedesktop.locale1.h"

#define _GNU_SOURCE

#define INPUT_SOURCES_SCHEMA "org.gnome.desktop.input-sources"
#define KEY_SOURCES "sources"

#define KEY_LAYOUT "X11Layout"
#define KEY_OPTIONS "X11Options"
#define KEY_VARIANT "X11Variant"

#define ORG_FREEDESKTOP_LOCALE1_DBUS_PATH "/org/freedesktop/locale1"
#define ORG_FREEDESKTOP_LOCALE1_DBUS_NAME "org.freedesktop.locale1"
#define ORG_FREEDESKTOP_LOCALE1_DBUS_IFACE "org.freedesktop.locale1"

typedef enum {
	PROP_CURRENT_SOURCE = 1,
} KeyboardLocaleManagerProps;

static GParamSpec* properties[PROP_CURRENT_SOURCE + 1] = {
	NULL,
};

struct _KeyboardLocaleManager {
	GObject parent_instance;

	GSettings* input_settings;
	GnomeXkbInfo* xkb_info;

	KeyboardLocale1* proxy;

	KeyboardInputSource* current_input_source;

	GListStore* model;
};

G_DEFINE_FINAL_TYPE(KeyboardLocaleManager, keyboard_locale_manager, G_TYPE_OBJECT)

/******************************************************************************
 * Helpers
 *****************************************************************************/

static KeyboardInputSource* keyboard_locale_manager_get_fallback_source(KeyboardLocaleManager* self) {
	KeyboardInputSource* source;
	gchar* type = NULL;
	gchar* id = NULL;
	gchar* layout = NULL;
	gchar* variant = NULL;
	gchar* display_name = NULL;
	gchar* short_name = NULL;
	gchar* locale = NULL;
	gchar* options = NULL;
	gchar** languages = NULL;

	g_return_val_if_fail(KEYBOARD_IS_LOCALE_MANAGER(self), NULL);

	languages = g_get_language_names();

	if (languages && g_strv_length(languages) > 0) {
		locale = g_strdup(languages[0]);
	}

	if (!locale || !g_strstr_len(locale, -1, "_")) {
		locale = "en_US";
	}

	if (!gnome_get_input_source_from_locale(locale, &type, &id)) {
		gnome_get_input_source_from_locale("en_US", &type, &id);
	}

	if (!id) {
		g_critical("Unable to get input source from locale");
		return NULL;
	}

	if (!gnome_xkb_info_get_layout_info(self->xkb_info, id, &display_name, &short_name, &layout, &variant)) {
		layout = "us";
		variant = "";
	}

	options = "";
	source = keyboard_input_source_new_full(id, 0, display_name, short_name, layout, variant, options, TRUE);

	return source;
}

static void keyboard_locale_manager_update_sources(KeyboardLocaleManager* self) {
	GList* sources = NULL;
	KeyboardInputSource* fallback_source = NULL;
	GVariant* value;
	guint i;

	g_return_if_fail(KEYBOARD_IS_LOCALE_MANAGER(self));

	g_list_store_remove_all(self->model);

	value = g_settings_get_value(self->input_settings, KEY_SOURCES);

	// Iterate over the configured layouts, and create
	// input sources from them.
	for (i = 0; i < g_variant_n_children(value); i++) {
		KeyboardInputSource* source;
		g_autofree gchar* id = NULL;
		g_autofree gchar* type = NULL;
		gchar** split = NULL;
		gchar* language = NULL;
		gchar* display_name = NULL;
		gchar* short_name = NULL;
		gchar* layout = NULL;
		gchar* variant = NULL;
		gchar* options = NULL;

		g_variant_get_child(value, i, "(ss)", &id, &type, NULL);

		if (g_str_equal(id, "xkb")) {
			// Split the language from the options
			split = g_strsplit(type, "+", -1);
			language = split[0];
			options = "";

			// Get the layout info for this language
			if (!gnome_xkb_info_get_layout_info(self->xkb_info, language, &display_name, &short_name, &layout, &variant)) {
				g_warning("Could not get layout info for language '%s'", language);
				continue;
			}

			// Check if this layout has options we need to set
			if (g_strv_length(split) == 2) {
				options = split[1];
			}

			source = keyboard_input_source_new_full(type, i, display_name, short_name, layout, variant, options, TRUE);
		} else {
			source = keyboard_input_source_new(type, i, FALSE);
		}

		g_list_store_insert_sorted(self->model, source, (GCompareDataFunc) keyboard_input_source_compare, NULL);

		g_strfreev(split);
	}

	// If there are no valid sources, add a fallback source.
	if (g_list_model_get_n_items(G_LIST_MODEL(self->model)) == 0) {
		fallback_source = keyboard_locale_manager_get_fallback_source(self);

		if (!KEYBOARD_IS_INPUT_SOURCE(fallback_source)) {
			g_warning("Unable to get fallback input source");
			return;
		}

		g_list_store_insert_sorted(self->model, fallback_source, (GCompareDataFunc) keyboard_input_source_compare, NULL);
	}
}

static KeyboardInputSource*
keyboard_locale_manager_find_current_input_source(
	KeyboardLocaleManager* self,
	const gchar* current_layout,
	const gchar* current_options,
	const gchar* current_variant) {
	KeyboardInputSource* source = NULL;
	guint i = 0;
	g_autofree gchar* layout = NULL;
	g_autofree gchar* options = NULL;
	g_autofree gchar* variant = NULL;

	g_return_val_if_fail(KEYBOARD_IS_LOCALE_MANAGER(self), NULL);

	while ((source = g_list_model_get_item(G_LIST_MODEL(self->model), i)) != NULL) {
		i++;

		if (!KEYBOARD_IS_INPUT_SOURCE(source)) {
			continue;
		}

		layout = keyboard_input_source_get_layout(source);
		options = keyboard_input_source_get_options(source);
		variant = keyboard_input_source_get_variant(source);

		if (g_str_equal(layout, current_layout) &&
			g_str_equal(options, current_options) &&
			g_str_equal(variant, current_variant)) {
			// We found our match
			break;
		}
	}

	return source;
}

/******************************************************************************
 * Callbacks
 *****************************************************************************/

static void keyboard_locale_manager_settings_changed_cb(G_GNUC_UNUSED GSettings* settings, gchar* key, gpointer user_data) {
	KeyboardLocaleManager* self = KEYBOARD_LOCALE_MANAGER(user_data);
	KeyboardInputSource* source = NULL;
	g_autofree gchar* layout = NULL;
	g_autofree gchar* options = NULL;
	g_autofree gchar* variant = NULL;

	if (!g_str_equal(key, KEY_SOURCES)) {
		return;
	}

	keyboard_locale_manager_update_sources(self);

	layout = keyboard_locale1_dup_x11_layout(self->proxy);
	options = keyboard_locale1_dup_x11_options(self->proxy);
	variant = keyboard_locale1_dup_x11_variant(self->proxy);
	source = keyboard_locale_manager_find_current_input_source(self, layout, options, variant);

	keyboard_locale_manager_set_current_input_source(self, source);
}

static void
keyboard_locale_manager_properties_changed_cb(
	G_GNUC_UNUSED GDBusProxy* proxy,
	GVariant* changed_properties,
	G_GNUC_UNUSED const gchar* const* invalidated_properties,
	gpointer user_data) {
	KeyboardLocaleManager* self = KEYBOARD_LOCALE_MANAGER(user_data);
	GVariantIter iter;
	GVariant* entry;
	KeyboardInputSource* source;

	gchar* current_layout = "";
	gchar* current_options = "";
	gchar* current_variant = "";

	g_variant_iter_init(&iter, changed_properties);

	while ((entry = g_variant_iter_next_value(&iter)) != NULL) {
		const gchar* key;
		GVariant* value;

		g_variant_get(entry, "{&sv}", &key, &value);

		if (g_str_equal(key, KEY_LAYOUT)) {
			current_layout = g_variant_get_string(value, NULL);
		} else if (g_str_equal(key, KEY_OPTIONS)) {
			current_options = g_variant_get_string(value, NULL);
		} else if (g_str_equal(key, KEY_VARIANT)) {
			current_variant = g_variant_get_string(value, NULL);
		}

		g_variant_unref(value);
		g_variant_unref(entry);
	}

	source = keyboard_locale_manager_find_current_input_source(self, current_layout, current_options, current_variant);

	keyboard_locale_manager_set_current_input_source(self, source);
}

/******************************************************************************
 * GObject
 *****************************************************************************/

static void keyboard_locale_manager_dispose(GObject* object) {
	KeyboardLocaleManager* self = KEYBOARD_LOCALE_MANAGER(object);

	g_clear_object(&self->input_settings);
	g_clear_object(&self->xkb_info);
	g_clear_object(&self->proxy);
	g_clear_object(&self->current_input_source);
	g_clear_object(&self->model);

	G_OBJECT_CLASS(keyboard_locale_manager_parent_class)->dispose(object);
}

static void keyboard_locale_manager_get_property(GObject* object, guint property_id, GValue* value, GParamSpec* spec) {
	KeyboardLocaleManager* self = KEYBOARD_LOCALE_MANAGER(object);

	switch ((KeyboardLocaleManagerProps) property_id) {
		case PROP_CURRENT_SOURCE:
			g_value_set_object(value, keyboard_locale_manager_get_current_input_source(self));
			break;
	}
}

static void keyboard_locale_manager_set_property(GObject* object, guint property_id, const GValue* value, GParamSpec* spec) {
	KeyboardLocaleManager* self = KEYBOARD_LOCALE_MANAGER(object);

	switch ((KeyboardLocaleManagerProps) property_id) {
		case PROP_CURRENT_SOURCE:
			keyboard_locale_manager_set_current_input_source(self, g_value_get_object(value));
			break;
	}
}

static void keyboard_locale_manager_class_init(KeyboardLocaleManagerClass* klass) {
	GObjectClass* class = G_OBJECT_CLASS(klass);

	class->dispose = keyboard_locale_manager_dispose;
	class->get_property = keyboard_locale_manager_get_property;
	class->set_property = keyboard_locale_manager_set_property;

	properties[PROP_CURRENT_SOURCE] = g_param_spec_object(
		"current-source",
		NULL,
		NULL,
		KEYBOARD_TYPE_INPUT_SOURCE,
		G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS);

	g_object_class_install_properties(class, G_N_ELEMENTS(properties), properties);
}

static void keyboard_locale_manager_init(KeyboardLocaleManager* self) {
	self->current_input_source = NULL;
	self->proxy = NULL;
	self->model = g_list_store_new(KEYBOARD_TYPE_INPUT_SOURCE);
	self->xkb_info = gnome_xkb_info_new();
	GSettings* input_settings;

	input_settings = g_settings_new(INPUT_SOURCES_SCHEMA);
	g_signal_connect(input_settings, "changed::" KEY_SOURCES, keyboard_locale_manager_settings_changed_cb, self);

	self->input_settings = input_settings;

	keyboard_locale_manager_update_sources(self);
}

/******************************************************************************
 * Public API
 *****************************************************************************/

/**
 * keyboard_locale_manager_new:
 *
 * Creates a new #KeyboardLocaleManager.
 *
 * Returns: (transfer full): A new #KeyboardLocaleManager
 */
KeyboardLocaleManager* keyboard_locale_manager_new(void) {
	return g_object_new(KEYBOARD_TYPE_LOCALE_MANAGER, NULL);
}

/**
 * keyboard_locale_manager_start:
 * @self: a #KeyboardLocaleManager
 *
 * Sets up the org.freedesktop.Locale1 D-Bus proxy, finds the current input
 * source, and starts watching for property changes on the D-Bus interface.
 */
void keyboard_locale_manager_start(KeyboardLocaleManager* self) {
	KeyboardLocale1* proxy = NULL;
	g_autoptr(GError) error = NULL;
	g_autofree gchar* current_layout = NULL;
	g_autofree gchar* current_options = NULL;
	g_autofree gchar* current_variant = NULL;
	KeyboardInputSource* current_source = NULL;

	g_return_if_fail(KEYBOARD_IS_LOCALE_MANAGER(self));

	proxy = keyboard_locale1_proxy_new_for_bus_sync(
		G_BUS_TYPE_SYSTEM,
		G_DBUS_PROXY_FLAGS_NONE,
		ORG_FREEDESKTOP_LOCALE1_DBUS_NAME,
		ORG_FREEDESKTOP_LOCALE1_DBUS_PATH,
		NULL,
		&error);

	if (proxy == NULL) {
		g_critical("Unable to create DBus proxy for %s: %s", ORG_FREEDESKTOP_LOCALE1_DBUS_NAME, error->message);
		return;
	}

	current_layout = keyboard_locale1_dup_x11_layout(proxy);
	current_options = keyboard_locale1_dup_x11_options(proxy);
	current_variant = keyboard_locale1_dup_x11_variant(proxy);
	current_source = keyboard_locale_manager_find_current_input_source(self, current_layout, current_options, current_variant);

	if (KEYBOARD_IS_INPUT_SOURCE(current_source)) {
		keyboard_locale_manager_set_current_input_source(self, current_source);
	}

	g_signal_connect(
		proxy,
		"g-properties-changed",
		G_CALLBACK(keyboard_locale_manager_properties_changed_cb),
		self);

	self->proxy = proxy;
}

/**
 * keyboard_locale_manager_get_current_input_source:
 * @self: a #KeyboardLocaleManager
 *
 * Gets the current input source.
 *
 * Returns: (type KeyboardInputSource*) (transfer full): The current input source
 */
KeyboardInputSource* keyboard_locale_manager_get_current_input_source(KeyboardLocaleManager* self) {
	g_return_val_if_fail(KEYBOARD_IS_LOCALE_MANAGER(self), NULL);

	return g_object_ref(self->current_input_source);
}

/**
 * keyboard_locale_manager_set_current_input_source:
 * @self: A #KeyboardLocaleManager
 * @source: (nullable): A #KeyboardInputSource
 *
 * Sets the current input source.
 */
void keyboard_locale_manager_set_current_input_source(KeyboardLocaleManager* self, KeyboardInputSource* source) {
	g_return_if_fail(KEYBOARD_IS_LOCALE_MANAGER(self));

	if (g_set_object(&self->current_input_source, source)) {
		g_object_notify_by_pspec(G_OBJECT(self), properties[PROP_CURRENT_SOURCE]);
	}
}

/**
 * keyboard_locale_manager_get_model:
 * @self: a #KeyboardLocaleManager
 *
 * Gets the input source model.
 *
 * Returns: (type GListModel*) (transfer none): The model
 */
GListStore* keyboard_locale_manager_get_model(KeyboardLocaleManager* self) {
	g_return_val_if_fail(KEYBOARD_IS_LOCALE_MANAGER(self), NULL);

	return self->model;
}

/**
 * keyboard_locale_manager_get_proxy:
 * @self: a #KeyboardLocaleManager
 *
 * Gets the D-Bus proxy for org.freedesktop.Locale1.
 *
 * Returns: (type KeyboardLocale1Proxy*) (transfer none): The proxy
 */
KeyboardLocale1Proxy* keyboard_locale_manager_get_proxy(KeyboardLocaleManager* self) {
	g_return_val_if_fail(KEYBOARD_IS_LOCALE_MANAGER(self), NULL);

	return self->proxy;
}
