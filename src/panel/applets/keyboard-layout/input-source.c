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

#include <string.h>

struct _KeyboardInputSource {
	GObject parent_instance;

	gchar* id;
	gchar* display_name;
	gchar* layout;
	gchar* variant;
	guint index;
};

typedef enum {
	PROP_ID = 1,
	PROP_DISPLAY_NAME,
	PROP_LAYOUT,
	PROP_VARIANT,
	PROP_INDEX,
} KeyboardInputSourceProps;

static GParamSpec* properties[PROP_INDEX + 1] = {NULL};

G_DEFINE_FINAL_TYPE(KeyboardInputSource, keyboard_input_source, G_TYPE_OBJECT)

/******************************************************************************
 * GObject
 *****************************************************************************/

static void keyboard_input_source_dispose(GObject* object) {
	KeyboardInputSource* self = KEYBOARD_INPUT_SOURCE(object);

	g_clear_pointer(&self->id, g_free);
	g_clear_pointer(&self->display_name, g_free);
	g_clear_pointer(&self->layout, g_free);
	g_clear_pointer(&self->variant, g_free);

	G_OBJECT_CLASS(keyboard_input_source_parent_class)->dispose(object);
}

static void keyboard_input_source_get_property(GObject* object, guint property_id, GValue* value, GParamSpec* spec) {
	KeyboardInputSource* self = KEYBOARD_INPUT_SOURCE(object);

	switch ((KeyboardInputSourceProps) property_id) {
		case PROP_ID:
			g_value_set_string(value, self->id);
			break;
		case PROP_DISPLAY_NAME:
			g_value_set_string(value, self->display_name);
			break;
		case PROP_LAYOUT:
			g_value_set_string(value, self->layout);
			break;
		case PROP_VARIANT:
			g_value_set_string(value, self->variant);
			break;
		case PROP_INDEX:
			g_value_set_uint(value, self->index);
			break;
		default:
			G_OBJECT_WARN_INVALID_PROPERTY_ID(object, property_id, spec);
			break;
	}
}

static void keyboard_input_source_set_property(GObject* object, guint property_id, const GValue* value, GParamSpec* spec) {
	KeyboardInputSource* self = KEYBOARD_INPUT_SOURCE(object);

	switch ((KeyboardInputSourceProps) property_id) {
		case PROP_ID:
			self->id = g_value_dup_string(value);
			break;
		case PROP_DISPLAY_NAME:
			self->display_name = g_value_dup_string(value);
			break;
		case PROP_LAYOUT:
			self->layout = g_value_dup_string(value);
			break;
		case PROP_VARIANT:
			self->variant = g_value_dup_string(value);
			break;
		case PROP_INDEX:
			self->index = g_value_get_uint(value);
			break;
		default:
			G_OBJECT_WARN_INVALID_PROPERTY_ID(object, property_id, spec);
			break;
	}
}

static void keyboard_input_source_class_init(KeyboardInputSourceClass* klass) {
	GObjectClass* class = G_OBJECT_CLASS(klass);

	class->dispose = keyboard_input_source_dispose;
	class->get_property = keyboard_input_source_get_property;
	class->set_property = keyboard_input_source_set_property;

	/**
	 * KeyboardInputSource:id:
	 *
	 * The GSettings id for this source, e.g. "us+intl" for an xkb source.
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

	g_object_class_install_properties(class, G_N_ELEMENTS(properties), properties);
}

static void keyboard_input_source_init(KeyboardInputSource* self) {
	self->id = NULL;
	self->display_name = NULL;
	self->layout = NULL;
	self->variant = NULL;
}

/******************************************************************************
 * Public API
 *****************************************************************************/

/**
 * keyboard_input_source_new:
 * @id: The GSettings id for this source
 * @index: The index in the #GSettings
 * @display_name: (nullable): A display-friendly name suitable for use in a UI
 * @layout: (nullable): The layout code
 * @variant: (nullable): The variant code
 *
 * Creates a new #KeyboardInputSource.
 *
 * Returns: (transfer full): A new #KeyboardInputSource
 */
KeyboardInputSource* keyboard_input_source_new(
	const gchar* id,
	guint index,
	const gchar* display_name,
	const gchar* layout,
	const gchar* variant) {
	return g_object_new(KEYBOARD_TYPE_INPUT_SOURCE,
		"id", id,
		"index", index,
		"display-name", display_name,
		"layout", layout,
		"variant", variant,
		NULL);
}

/**
 * keyboard_input_source_get_id:
 * @self: A #KeyboardInputSource
 *
 * Get the ID of this input source.
 *
 * Returns: (transfer none): The ID
 */
const gchar* keyboard_input_source_get_id(KeyboardInputSource* self) {
	g_return_val_if_fail(KEYBOARD_IS_INPUT_SOURCE(self), NULL);

	return self->id;
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
 * Returns: (transfer none) (nullable): The display name
 */
const gchar* keyboard_input_source_get_display_name(KeyboardInputSource* self) {
	g_return_val_if_fail(KEYBOARD_IS_INPUT_SOURCE(self), NULL);

	return self->display_name;
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
 * Returns: (transfer none) (nullable): The layout
 */
const gchar* keyboard_input_source_get_layout(KeyboardInputSource* self) {
	g_return_val_if_fail(KEYBOARD_IS_INPUT_SOURCE(self), NULL);

	return self->layout;
}

/**
 * keyboard_input_source_get_variant:
 * @self: A #KeyboardInputSource
 *
 * Get the variant for this input source.
 *
 * Returns: (transfer none) (nullable): The variant
 */
const gchar* keyboard_input_source_get_variant(KeyboardInputSource* self) {
	g_return_val_if_fail(KEYBOARD_IS_INPUT_SOURCE(self), NULL);

	return self->variant;
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
 * Compares the index and id of both input sources to determine
 * if they are equal.
 *
 * Returns: #TRUE if both input sources are equal
 */
gboolean keyboard_input_source_equal(KeyboardInputSource* self, KeyboardInputSource* other) {
	g_return_val_if_fail(KEYBOARD_IS_INPUT_SOURCE(self), FALSE);
	g_return_val_if_fail(KEYBOARD_IS_INPUT_SOURCE(other), FALSE);

	return self->index == other->index && g_strcmp0(self->id, other->id) == 0;
}
