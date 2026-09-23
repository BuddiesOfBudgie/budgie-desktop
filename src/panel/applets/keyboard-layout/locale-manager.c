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

#define INPUT_SOURCES_SCHEMA "org.gnome.desktop.input-sources"
#define KEY_SOURCES "sources"

#define ORG_FREEDESKTOP_LOCALE1_DBUS_PATH "/org/freedesktop/locale1"
#define ORG_FREEDESKTOP_LOCALE1_DBUS_NAME "org.freedesktop.locale1"

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

/* g_str_equal is a plain strcmp and crashes on NULL. locale1 leaves a property
 * NULL when it is unset, and so does a source with no variant, so compare with
 * NULL and "" meaning the same thing. */
static gboolean keyboard_locale_manager_str_equal(const gchar* a, const gchar* b) {
	return g_strcmp0(a != NULL ? a : "", b != NULL ? b : "") == 0;
}

/* locale1 puts every layout and options in one property, like "us,fi", so
 * split to get the first (active) one */
static gchar* keyboard_locale_manager_first_entry(const gchar* list) {
	g_auto(GStrv) entries = NULL;

	if (list == NULL) {
		return NULL;
	}

	entries = g_strsplit(list, ",", 2);

	return g_strdup(entries[0]);
}

/* Returns: (transfer full) (nullable): The active locale1 layout as a GSettings
 * xkb id, e.g. "us+intl" */
static gchar* keyboard_locale_manager_get_locale1_id(KeyboardLocaleManager* self) {
	g_autofree gchar* layouts = NULL;
	g_autofree gchar* variants = NULL;
	g_autofree gchar* layout = NULL;
	g_autofree gchar* variant = NULL;

	if (self->proxy == NULL) {
		return NULL;
	}

	layouts = keyboard_locale1_dup_x11_layout(self->proxy);
	variants = keyboard_locale1_dup_x11_variant(self->proxy);
	layout = keyboard_locale_manager_first_entry(layouts);
	variant = keyboard_locale_manager_first_entry(variants);

	if (layout == NULL || g_str_equal(layout, "")) {
		return NULL;
	}

	if (variant == NULL || g_str_equal(variant, "")) {
		return g_steal_pointer(&layout);
	}

	return g_strdup_printf("%s+%s", layout, variant);
}

static KeyboardInputSource* keyboard_locale_manager_get_fallback_source(KeyboardLocaleManager* self) {
	g_autofree gchar* locale1_id = NULL;
	const gchar* type = NULL;
	const gchar* id = NULL;
	const gchar* layout = NULL;
	const gchar* variant = NULL;
	const gchar* display_name = NULL;
	const gchar* locale = NULL;
	const gchar* const* languages = NULL;

	g_return_val_if_fail(KEYBOARD_IS_LOCALE_MANAGER(self), NULL);

	/* The installer sets the keyboard in locale1, which is also what the
	 * bridge applies when no sources are configured */
	locale1_id = keyboard_locale_manager_get_locale1_id(self);

	if (locale1_id != NULL && gnome_xkb_info_get_layout_info(self->xkb_info, locale1_id, &display_name, NULL, &layout, &variant)) {
		return keyboard_input_source_new(locale1_id, 0, display_name, layout, variant);
	}

	languages = g_get_language_names();

	if (languages != NULL && languages[0] != NULL) {
		locale = languages[0];
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

	if (!gnome_xkb_info_get_layout_info(self->xkb_info, id, &display_name, NULL, &layout, &variant)) {
		layout = "us";
		variant = "";
	}

	return keyboard_input_source_new(id, 0, display_name, layout, variant);
}

static void keyboard_locale_manager_update_sources(KeyboardLocaleManager* self) {
	g_autoptr(KeyboardInputSource) fallback_source = NULL;
	g_autoptr(GVariant) value = NULL;
	guint i;

	g_return_if_fail(KEYBOARD_IS_LOCALE_MANAGER(self));

	g_list_store_remove_all(self->model);

	value = g_settings_get_value(self->input_settings, KEY_SOURCES);

	// Iterate over the configured layouts, and create
	// input sources from them.
	for (i = 0; i < g_variant_n_children(value); i++) {
		g_autoptr(KeyboardInputSource) source = NULL;
		g_autofree gchar* type = NULL;
		g_autofree gchar* id = NULL;
		const gchar* display_name = NULL;
		const gchar* layout = NULL;
		const gchar* variant = NULL;

		g_variant_get_child(value, i, "(ss)", &type, &id);

		if (g_str_equal(type, "xkb")) {
			/* The id is "layout+variant", which is the form xkb_info looks up */
			if (!gnome_xkb_info_get_layout_info(self->xkb_info, id, &display_name, NULL, &layout, &variant)) {
				g_warning("Could not get layout info for '%s'", id);
				continue;
			}

			source = keyboard_input_source_new(id, i, display_name, layout, variant);
		} else {
			source = keyboard_input_source_new(id, i, NULL, NULL, NULL);
		}

		/* insert_sorted takes its own reference, so ours still needs dropping */
		g_list_store_insert_sorted(self->model, source, (GCompareDataFunc) keyboard_input_source_compare, NULL);
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

/* The caller owns the returned reference, so hold it in a
 * g_autoptr(KeyboardInputSource) - set_current_input_source takes its own. */
static KeyboardInputSource*
keyboard_locale_manager_find_current_input_source(
	KeyboardLocaleManager* self,
	const gchar* current_layout,
	const gchar* current_variant) {
	KeyboardInputSource* source = NULL;
	g_autofree gchar* active_layout = NULL;
	g_autofree gchar* active_variant = NULL;
	guint i = 0;

	g_return_val_if_fail(KEYBOARD_IS_LOCALE_MANAGER(self), NULL);

	/* Without a layout there is nothing to match on, and every source that
	 * carries no layout of its own would compare equal. */
	if (current_layout == NULL || g_str_equal(current_layout, "")) {
		return NULL;
	}

	active_layout = keyboard_locale_manager_first_entry(current_layout);
	active_variant = keyboard_locale_manager_first_entry(current_variant);

	while ((source = g_list_model_get_item(G_LIST_MODEL(self->model), i)) != NULL) {
		i++;

		if (KEYBOARD_IS_INPUT_SOURCE(source) &&
			keyboard_locale_manager_str_equal(keyboard_input_source_get_layout(source), active_layout) &&
			keyboard_locale_manager_str_equal(keyboard_input_source_get_variant(source), active_variant)) {
			break;
		}

		g_object_unref(source);
	}

	return source;
}

static void keyboard_locale_manager_refresh_current_input_source(KeyboardLocaleManager* self) {
	g_autoptr(KeyboardInputSource) source = NULL;
	g_autofree gchar* layout = NULL;
	g_autofree gchar* variant = NULL;

	/* start() has not run yet, or there is no localed to talk to */
	if (self->proxy != NULL) {
		layout = keyboard_locale1_dup_x11_layout(self->proxy);
		variant = keyboard_locale1_dup_x11_variant(self->proxy);
	}

	source = keyboard_locale_manager_find_current_input_source(self, layout, variant);

	if (!KEYBOARD_IS_INPUT_SOURCE(source)) {
		/* locale1 names a layout that is not configured, and the applet always
		 * shows one, so the first source is the best answer available */
		source = g_list_model_get_item(G_LIST_MODEL(self->model), 0);
	}

	if (!KEYBOARD_IS_INPUT_SOURCE(source)) {
		/* Passing NULL on is what leaves the popover with no row selected */
		return;
	}

	keyboard_locale_manager_set_current_input_source(self, source);
}

/******************************************************************************
 * Callbacks
 *****************************************************************************/

static void keyboard_locale_manager_settings_changed_cb(G_GNUC_UNUSED GSettings* settings, gchar* key, gpointer user_data) {
	KeyboardLocaleManager* self = KEYBOARD_LOCALE_MANAGER(user_data);

	if (!g_str_equal(key, KEY_SOURCES)) {
		return;
	}

	keyboard_locale_manager_update_sources(self);

	keyboard_locale_manager_refresh_current_input_source(self);
}

static void
keyboard_locale_manager_properties_changed_cb(
	G_GNUC_UNUSED GDBusProxy* proxy,
	G_GNUC_UNUSED GVariant* changed_properties,
	G_GNUC_UNUSED const gchar* const* invalidated_properties,
	gpointer user_data) {
	KeyboardLocaleManager* self = KEYBOARD_LOCALE_MANAGER(user_data);

	/* locale1 names only the properties that changed, and the proxy has already
	 * cached them, so all three are read back from there */
	keyboard_locale_manager_refresh_current_input_source(self);
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
			/* take_object, not set_object: the getter already returns a new
			 * reference, and set_object would add another one and leak it. */
			g_value_take_object(value, keyboard_locale_manager_get_current_input_source(self));
			break;
		default:
			G_OBJECT_WARN_INVALID_PROPERTY_ID(object, property_id, spec);
			break;
	}
}

static void keyboard_locale_manager_set_property(GObject* object, guint property_id, const GValue* value, GParamSpec* spec) {
	KeyboardLocaleManager* self = KEYBOARD_LOCALE_MANAGER(object);

	switch ((KeyboardLocaleManagerProps) property_id) {
		case PROP_CURRENT_SOURCE:
			keyboard_locale_manager_set_current_input_source(self, g_value_get_object(value));
			break;
		default:
			G_OBJECT_WARN_INVALID_PROPERTY_ID(object, property_id, spec);
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
	g_signal_connect(input_settings, "changed::" KEY_SOURCES, G_CALLBACK(keyboard_locale_manager_settings_changed_cb), self);

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

	self->proxy = proxy;

	/* The fallback source reads locale1, which was not available in init */
	keyboard_locale_manager_update_sources(self);
	keyboard_locale_manager_refresh_current_input_source(self);

	g_signal_connect(
		proxy,
		"g-properties-changed",
		G_CALLBACK(keyboard_locale_manager_properties_changed_cb),
		self);
}

/**
 * keyboard_locale_manager_get_current_input_source:
 * @self: a #KeyboardLocaleManager
 *
 * Gets the current input source. The caller owns the returned reference, so
 * hold it in a g_autoptr(KeyboardInputSource).
 *
 * Returns: (type KeyboardInputSource*) (transfer full) (nullable): The current input source
 */
KeyboardInputSource* keyboard_locale_manager_get_current_input_source(KeyboardLocaleManager* self) {
	g_return_val_if_fail(KEYBOARD_IS_LOCALE_MANAGER(self), NULL);

	if (self->current_input_source == NULL) {
		return NULL;
	}

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
 * keyboard_locale_manager_set_current_layout:
 * @self: A #KeyboardLocaleManager
 * @layout: (nullable): An XKB layout code, e.g. "fi"
 *
 * Makes the configured source for @layout the current input source.
 *
 * Nothing happens when the current source already uses @layout: the code
 * carries no variant, so it cannot pick between two sources sharing a layout.
 */
void keyboard_locale_manager_set_current_layout(KeyboardLocaleManager* self, const gchar* layout) {
	guint i;

	g_return_if_fail(KEYBOARD_IS_LOCALE_MANAGER(self));

	if (layout == NULL || g_str_equal(layout, "")) {
		return;
	}

	if (self->current_input_source != NULL &&
		keyboard_locale_manager_str_equal(keyboard_input_source_get_layout(self->current_input_source), layout)) {
		return;
	}

	for (i = 0; i < g_list_model_get_n_items(G_LIST_MODEL(self->model)); i++) {
		g_autoptr(KeyboardInputSource) source = g_list_model_get_item(G_LIST_MODEL(self->model), i);

		if (!KEYBOARD_IS_INPUT_SOURCE(source)) {
			continue;
		}

		if (keyboard_locale_manager_str_equal(keyboard_input_source_get_layout(source), layout)) {
			keyboard_locale_manager_set_current_input_source(self, source);
			return;
		}
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
 * Returns: (type KeyboardLocale1*) (transfer none): The proxy
 */
KeyboardLocale1* keyboard_locale_manager_get_proxy(KeyboardLocaleManager* self) {
	g_return_val_if_fail(KEYBOARD_IS_LOCALE_MANAGER(self), NULL);

	return self->proxy;
}
