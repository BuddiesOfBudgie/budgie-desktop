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

#include "input-source.h"

#define _GNU_SOURCE

struct _KeyboardInputSource {
	GObject parent_instance;

	gchar* id;
	gchar* display_name;
	gchar* short_name;
	gchar* layout;
	gchar* variant;
	gchar* options;
	guint index;
	gboolean is_xkb;
};

typedef enum {
	PROP_ID = 1,
	PROP_DISPLAY_NAME,
	PROP_SHORT_NAME,
	PROP_LAYOUT,
	PROP_VARIANT,
	PROP_OPTIONS,
	PROP_INDEX,
	PROP_XKB,
} KeyboardInputSourceProps;

static GParamSpec* properties[PROP_XKB + 1] = {NULL};

G_DEFINE_FINAL_TYPE(KeyboardInputSource, keyboard_input_source, G_TYPE_OBJECT)

/******************************************************************************
 * GObject
 *****************************************************************************/

static void keyboard_input_source_dispose(GObject* object) {
	KeyboardInputSource* self = KEYBOARD_INPUT_SOURCE(object);

	g_clear_pointer(&self->id, g_free);
	g_clear_pointer(&self->display_name, g_free);
	g_clear_pointer(&self->short_name, g_free);
	g_clear_pointer(&self->layout, g_free);
	g_clear_pointer(&self->variant, g_free);
	g_clear_pointer(&self->options, g_free);

	G_OBJECT_CLASS(keyboard_input_source_parent_class)->dispose(object);
}

static void keyboard_input_source_get_property(GObject* object, guint property_id, GValue* value, GParamSpec* spec) {
	KeyboardInputSource* self = KEYBOARD_INPUT_SOURCE(object);

	switch ((KeyboardInputSourceProps) property_id) {
		case PROP_ID:
			g_value_set_string(value, keyboard_input_source_get_id(self));
			break;
		case PROP_DISPLAY_NAME:
			g_value_set_string(value, keyboard_input_source_get_display_name(self));
			break;
		case PROP_SHORT_NAME:
			g_value_set_string(value, keyboard_input_source_get_short_name(self));
			break;
		case PROP_LAYOUT:
			g_value_set_string(value, keyboard_input_source_get_layout(self));
			break;
		case PROP_VARIANT:
			g_value_set_string(value, keyboard_input_source_get_variant(self));
			break;
		case PROP_OPTIONS:
			g_value_set_string(value, keyboard_input_source_get_options(self));
			break;
		case PROP_INDEX:
			g_value_set_uint(value, self->index);
			break;
		case PROP_XKB:
			g_value_set_boolean(value, self->is_xkb);
			break;
	}
}

static void keyboard_input_source_set_property(GObject* object, guint property_id, const GValue* value, GParamSpec* spec) {
	KeyboardInputSource* self = KEYBOARD_INPUT_SOURCE(object);

	switch ((KeyboardInputSourceProps) property_id) {
		case PROP_ID:
			keyboard_input_source_set_id(self, g_value_get_string(value));
			break;
		case PROP_DISPLAY_NAME:
			keyboard_input_source_set_display_name(self, g_value_get_string(value));
			break;
		case PROP_SHORT_NAME:
			keyboard_input_source_set_short_name(self, g_value_get_string(value));
			break;
		case PROP_LAYOUT:
			keyboard_input_source_set_layout(self, g_value_get_string(value));
			break;
		case PROP_VARIANT:
			keyboard_input_source_set_variant(self, g_value_get_string(value));
			break;
		case PROP_OPTIONS:
			keyboard_input_source_set_options(self, g_value_get_string(value));
			break;
		case PROP_INDEX:
			keyboard_input_source_set_index(self, g_value_get_uint(value));
			break;
		case PROP_XKB:
			keyboard_input_source_set_xkb(self, g_value_get_boolean(value));
			break;
	}
}

static void keyboard_input_source_class_init(KeyboardInputSourceClass* klass) {
	GObjectClass* class = G_OBJECT_CLASS(klass);

	class->dispose = keyboard_input_source_dispose;
	class->get_property = keyboard_input_source_get_property;
	class->set_property = keyboard_input_source_set_property;

	/**
	 * KeyboardInputSource:type:
	 *
	 * The input type for this source.
	 */
	properties[PROP_ID] = g_param_spec_string(
		"id",
		NULL,
		NULL,
		NULL,
		G_PARAM_CONSTRUCT_ONLY | G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS);

	/**
	 * KeyboardInputSource:display-name:
	 *
	 * The display name for this input source. This is a friendly name suitable for
	 * use in a UI.
	 */
	properties[PROP_DISPLAY_NAME] = g_param_spec_string(
		"display-name",
		NULL,
		NULL,
		NULL,
		G_PARAM_CONSTRUCT_ONLY | G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS);

	/**
	 * KeyboardInputSource:short-name:
	 *
	 * The short name for this input source.
	 */
	properties[PROP_SHORT_NAME] = g_param_spec_string(
		"short-name",
		NULL,
		NULL,
		NULL,
		G_PARAM_CONSTRUCT_ONLY | G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS);

	/**
	 * KeyboardInputSource:layout:
	 *
	 * The layout for this input source.
	 */
	properties[PROP_LAYOUT] = g_param_spec_string(
		"layout",
		NULL,
		NULL,
		NULL,
		G_PARAM_CONSTRUCT_ONLY | G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS);

	/**
	 * KeyboardInputSource:variant:
	 *
	 * The variant for this input source.
	 */
	properties[PROP_VARIANT] = g_param_spec_string(
		"variant",
		NULL,
		NULL,
		NULL,
		G_PARAM_CONSTRUCT_ONLY | G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS);

	/**
	 * KeyboardInputSource:options:
	 *
	 * The options for this input source. This is a comma-delineated list
	 * of options that this layout sets.
	 */
	properties[PROP_OPTIONS] = g_param_spec_string(
		"options",
		NULL,
		NULL,
		NULL,
		G_PARAM_CONSTRUCT_ONLY | G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS);

	/**
	 * KeyboardInputSource:index:
	 *
	 * The index of this input source.
	 */
	properties[PROP_INDEX] = g_param_spec_uint(
		"index",
		NULL,
		NULL,
		0,
		G_MAXUINT,
		0,
		G_PARAM_CONSTRUCT_ONLY | G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS);

	/**
	 * KeyboardInputSource:xkb:
	 *
	 * Whether or not this source is from XKB.
	 */
	properties[PROP_XKB] = g_param_spec_boolean(
		"is-xkb",
		NULL,
		NULL,
		FALSE,
		G_PARAM_CONSTRUCT_ONLY | G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS);

	g_object_class_install_properties(class, G_N_ELEMENTS(properties), properties);
}

static void keyboard_input_source_init(KeyboardInputSource* self) {
	self->id = NULL;
	self->display_name = NULL;
	self->short_name = NULL;
	self->layout = NULL;
	self->variant = NULL;
	self->options = NULL;
}

/******************************************************************************
 * Public API
 *****************************************************************************/

/**
 * keyboard_input_source_new:
 * @id: The language for the layout
 * @index: The index in the #GSettings
 * @is_xkb: Whether this input source is from XKB
 *
 * A convenience method to create a new #KeyboardInputSource.
 *
 * See: keyboard_input_source_new_full
 *
 * Returns: (transfer full): A new #KeyboardInputSource
 */
KeyboardInputSource* keyboard_input_source_new(gchar* id, guint index, gboolean is_xkb) {
	return keyboard_input_source_new_full(id, index, "", "", "", "", "", is_xkb);
}

/**
 * keyboard_input_source_new_full:
 * @id: The language for the layout
 * @index: The index in the #GSettings
 * @display_name: A display-friendly name suitable for use in a UI
 * @short_name: The short code for this input layout
 * @layout: The layout code
 * @variant: The variant code
 * @options: The options in this layout
 * @is_xkb: Whether this input source is from XKB
 *
 * Creates a new #KeyboardInputSource.
 *
 * Returns: (transfer full): A new #KeyboardInputSource
 */
KeyboardInputSource* keyboard_input_source_new_full(
	gchar* id,
	guint index,
	gchar* display_name,
	gchar* short_name,
	gchar* layout,
	gchar* variant,
	gchar* options,
	gboolean is_xkb) {
	return g_object_new(KEYBOARD_TYPE_INPUT_SOURCE,
		"id", id,
		"index", index,
		"layout", layout,
		"variant", variant,
		"display-name", display_name,
		"short-name", short_name,
		"options", options,
		"is-xkb", is_xkb,
		NULL);
}

/**
 * keyboard_input_source_get_id:
 * @self: A #KeyboardInputSource
 *
 * Get the ID of this input source.
 *
 * Returns: (transfer full): The ID
 */
gchar* keyboard_input_source_get_id(KeyboardInputSource* self) {
	gchar* id = NULL;

	g_return_val_if_fail(KEYBOARD_IS_INPUT_SOURCE(self), NULL);

	if (self->id) {
		id = g_strdup(self->id);
	}

	return id;
}

/**
 * keyboard_input_source_set_id:
 * @self: A #KeyboardInputSource
 * @id: The ID
 *
 * Sets the ID of this input source.
 */
void keyboard_input_source_set_id(KeyboardInputSource* self, gchar* id) {
	g_return_if_fail(KEYBOARD_IS_INPUT_SOURCE(self));

	if (g_set_str(&self->id, id)) {
		g_object_notify_by_pspec(G_OBJECT(self), properties[PROP_ID]);
	}
}

/**
 * keyboard_input_source_get_index:
 * @self: A #KeyboardInputSource
 *
 * Get the index of this input source.
 *
 * Returns: The index
 */
guint keyboard_input_source_get_index(KeyboardInputSource* self) {
	g_return_val_if_fail(KEYBOARD_IS_INPUT_SOURCE(self), 0);

	return self->index;
}

/**
 * keyboard_input_source_set_index:
 * @self: A #KeyboardInputSource
 * @index: The index
 *
 * Sets the index of this input source.
 */
void keyboard_input_source_set_index(KeyboardInputSource* self, guint index) {
	g_return_if_fail(KEYBOARD_IS_INPUT_SOURCE(self));

	self->index = index;

	g_object_notify_by_pspec(G_OBJECT(self), properties[PROP_INDEX]);
}

/**
 * keyboard_input_source_is_xkb:
 * @self: A #KeyboardInputSource
 *
 * Get whether this input source is from XKB.
 *
 * Returns: #TRUE if the source is from XKB
 */
gboolean keyboard_input_source_is_xkb(KeyboardInputSource* self) {
	g_return_val_if_fail(KEYBOARD_IS_INPUT_SOURCE(self), FALSE);

	return self->is_xkb;
}

/**
 * keyboard_input_source_set_xkb:
 * @self: A #KeyboardInputSource
 * @xkb: #TRUE if the input source is from XKB
 *
 * Sets whether this input source is from XKB.
 */
void keyboard_input_source_set_xkb(KeyboardInputSource* self, gboolean xkb) {
	g_return_if_fail(KEYBOARD_IS_INPUT_SOURCE(self));

	self->is_xkb = xkb;

	g_object_notify_by_pspec(G_OBJECT(self), properties[PROP_XKB]);
}

/**
 * keyboard_input_source_has_display_name:
 * @self: A #KeyboardInputSource
 *
 * Get whether this source has a display name.
 *
 * Returns: #TRUE if a display name is set
 */
gboolean keyboard_input_source_has_display_name(KeyboardInputSource* self) {
	g_return_val_if_fail(KEYBOARD_IS_INPUT_SOURCE(self), FALSE);

	return (self->display_name != NULL && strlen(self->display_name) > 0);
}

/**
 * keyboard_input_source_get_display_name:
 * @self: A #KeyboardInputSource
 *
 * Get the display name for this input source.
 *
 * Returns: (transfer full): The display name, or #NULL
 */
gchar* keyboard_input_source_get_display_name(KeyboardInputSource* self) {
	gchar* display_name = NULL;

	g_return_val_if_fail(KEYBOARD_IS_INPUT_SOURCE(self), NULL);

	if (self->display_name) {
		display_name = g_strdup(self->display_name);
	}

	return display_name;
}

/**
 * keyboard_input_source_set_display_name:
 * @self: A #KeyboardInputSource
 * @display_name: (nullable): The display name to set
 *
 * Sets the display name for this input source.
 */
void keyboard_input_source_set_display_name(KeyboardInputSource* self, gchar* display_name) {
	g_return_if_fail(KEYBOARD_IS_INPUT_SOURCE(self));

	if (g_set_str(&self->display_name, display_name)) {
		g_object_notify_by_pspec(G_OBJECT(self), properties[PROP_DISPLAY_NAME]);
	}
}

/**
 * keyboard_input_source_has_short_name:
 * @self: A #KeyboardInputSource
 *
 * Get whether this source has a short name.
 *
 * Returns: #TRUE if a short name is set
 */
gboolean keyboard_input_source_has_short_name(KeyboardInputSource* self) {
	g_return_val_if_fail(KEYBOARD_IS_INPUT_SOURCE(self), FALSE);

	return (self->short_name != NULL && strlen(self->short_name) > 0);
}

/**
 * keyboard_input_source_get_short_name:
 * @self: A #KeyboardInputSource
 *
 * Get the short name for this input source.
 *
 * Returns: (transfer full): The short name, or #NULL
 */
gchar* keyboard_input_source_get_short_name(KeyboardInputSource* self) {
	gchar* short_name = NULL;

	g_return_val_if_fail(KEYBOARD_IS_INPUT_SOURCE(self), NULL);

	if (self->short_name) {
		short_name = g_strdup(self->short_name);
	}

	return short_name;
}

/**
 * keyboard_input_source_set_short_name:
 * @self: A #KeyboardInputSource
 * @short_name: (nullable): The short name to set
 *
 * Sets the short name for this input source.
 */
void keyboard_input_source_set_short_name(KeyboardInputSource* self, gchar* short_name) {
	g_return_if_fail(KEYBOARD_IS_INPUT_SOURCE(self));

	if (g_set_str(&self->short_name, short_name)) {
		g_object_notify_by_pspec(G_OBJECT(self), properties[PROP_SHORT_NAME]);
	}
}

/**
 * keyboard_input_source_has_layout:
 * @self: A #KeyboardInputSource
 *
 * Get whether this source has a layout.
 *
 * Returns: #TRUE if a layout is set
 */
gboolean keyboard_input_source_has_layout(KeyboardInputSource* self) {
	g_return_val_if_fail(KEYBOARD_IS_INPUT_SOURCE(self), FALSE);

	return (self->layout != NULL && strlen(self->layout) > 0);
}

/**
 * keyboard_input_source_get_layout:
 * @self: A #KeyboardInputSource
 *
 * Get the layout for this input source.
 *
 * Returns: (transfer full): The layout, or #NULL
 */
gchar* keyboard_input_source_get_layout(KeyboardInputSource* self) {
	gchar* layout = NULL;

	g_return_val_if_fail(KEYBOARD_IS_INPUT_SOURCE(self), NULL);

	if (self->layout) {
		layout = g_strdup(self->layout);
	}

	return layout;
}

/**
 * keyboard_input_source_set_layout:
 * @self: A #KeyboardInputSource
 * @layout: (nullable): The layout to set
 *
 * Sets the layout for this input source.
 */
void keyboard_input_source_set_layout(KeyboardInputSource* self, gchar* layout) {
	g_return_if_fail(KEYBOARD_IS_INPUT_SOURCE(self));

	if (g_set_str(&self->layout, layout)) {
		g_object_notify_by_pspec(G_OBJECT(self), properties[PROP_LAYOUT]);
	}
}

/**
 * keyboard_input_source_has_variant:
 * @self: A #KeyboardInputSource
 *
 * Get whether this source has a variant.
 *
 * Returns: #TRUE if a variant is set
 */
gboolean keyboard_input_source_has_variant(KeyboardInputSource* self) {
	g_return_val_if_fail(KEYBOARD_IS_INPUT_SOURCE(self), FALSE);

	return (self->variant != NULL && strlen(self->variant) > 0);
}

/**
 * keyboard_input_source_get_variant:
 * @self: A #KeyboardInputSource
 *
 * Get the variant for this input source.
 *
 * Returns: (transfer full): The variant, or #NULL
 */
gchar* keyboard_input_source_get_variant(KeyboardInputSource* self) {
	gchar* variant = NULL;

	g_return_val_if_fail(KEYBOARD_IS_INPUT_SOURCE(self), NULL);

	if (self->variant) {
		variant = g_strdup(self->variant);
	}

	return variant;
}

/**
 * keyboard_input_source_set_variant:
 * @self: A #KeyboardInputSource
 * @variant: (nullable): The variant to set
 *
 * Sets the variant for this input source.
 */
void keyboard_input_source_set_variant(KeyboardInputSource* self, gchar* variant) {
	g_return_if_fail(KEYBOARD_IS_INPUT_SOURCE(self));

	if (g_set_str(&self->variant, variant)) {
		g_object_notify_by_pspec(G_OBJECT(self), properties[PROP_VARIANT]);
	}
}

/**
 * keyboard_input_source_has_options:
 * @self: A #KeyboardInputSource
 *
 * Get whether this source has options.
 *
 * Returns: #TRUE if options are set
 */
gboolean keyboard_input_source_has_options(KeyboardInputSource* self) {
	g_return_val_if_fail(KEYBOARD_IS_INPUT_SOURCE(self), FALSE);

	return (self->options != NULL && strlen(self->options) > 0);
}

/**
 * keyboard_input_source_get_options:
 * @self: A #KeyboardInputSource
 *
 * Get the options for this input source.
 *
 * Input options are a comma-delineated list of the options the layout sets.
 *
 * Returns: (transfer full): The options, or #NULL
 */
gchar* keyboard_input_source_get_options(KeyboardInputSource* self) {
	gchar* options = NULL;

	g_return_val_if_fail(KEYBOARD_IS_INPUT_SOURCE(self), FALSE);

	if (self->options) {
		options = g_strdup(self->options);
	}

	return options;
}

/**
 * keyboard_input_source_set_options:
 * @self: A #KeyboardInputSource
 * @options: (nullable): The options to set
 *
 * Sets the options for this input source.
 */
void keyboard_input_source_set_options(KeyboardInputSource* self, gchar* options) {
	g_return_if_fail(KEYBOARD_IS_INPUT_SOURCE(self));

	if (g_set_str(&self->options, options)) {
		g_object_notify_by_pspec(G_OBJECT(self), properties[PROP_OPTIONS]);
	}
}

/**
 * keyboard_input_source_compare:
 * @self: A #KeyboardInputSource
 * @other: A different #KeyboardInputSource
 * @user_data: Data passed to this function
 *
 * Compare two keyboard input sources. This function is suitable to be used
 * anywhere a #GCompareFunc is needed.
 *
 * Returns: -1 if the index of @self is less than @other,
 * 			1 if the index of @self is greater than @other,
 * 			or 0 if both indices are equal.
 */
gint keyboard_input_source_compare(KeyboardInputSource* self, KeyboardInputSource* other, G_GNUC_UNUSED gpointer user_data) {
	g_return_val_if_fail(KEYBOARD_IS_INPUT_SOURCE(self), 0);
	g_return_val_if_fail(KEYBOARD_IS_INPUT_SOURCE(other), 0);

	if (self->index < other->index) {
		return -1;
	} else if (self->index > other->index) {
		return 1;
	}

	return 0;
}

/**
 * keyboard_input_source_equal:
 * @self: A #KeyboardInputSource
 * @other: Another #KeyboardInputSource
 *
 * Compares the properties of both input sources to determine
 * if they are equal.
 *
 * Returns: #TRUE if the properties of both input sources are equal
 */
gboolean keyboard_input_source_equal(KeyboardInputSource* self, KeyboardInputSource* other) {
	g_return_val_if_fail(KEYBOARD_IS_INPUT_SOURCE(self), FALSE);
	g_return_val_if_fail(KEYBOARD_IS_INPUT_SOURCE(other), FALSE);

	if (self->index != other->index) {
		return FALSE;
	}

	if (!g_str_equal(self->id, other->id)) {
		return FALSE;
	}

	if (!g_str_equal(self->options, other->options)) {
		return FALSE;
	}

	if (!g_str_equal(self->variant, other->variant)) {
		return FALSE;
	}

	return TRUE;
}
