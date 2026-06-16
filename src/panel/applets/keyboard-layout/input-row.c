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

#include "input-row.h"
#include "input-source.h"

#define _GNU_SOURCE

struct _KeyboardInputRow {
	GtkListBoxRow parent_instance;

	GtkWidget* label;

	KeyboardInputSource* source;
};

typedef enum {
	PROP_INPUT_SOURCE = 1,
} KeyboardInputRowProps;

static GParamSpec* properties[PROP_INPUT_SOURCE + 1] = {NULL};

G_DEFINE_FINAL_TYPE(KeyboardInputRow, keyboard_input_row, GTK_TYPE_LIST_BOX_ROW)

/******************************************************************************
 * GObject
 *****************************************************************************/

static void keyboard_input_row_constructed(GObject* object) {
	KeyboardInputRow* self = KEYBOARD_INPUT_ROW(object);
	g_autofree gchar* label_text = NULL;
	g_autofree gchar* short_name_text = NULL;
	g_autofree gchar* layout_text = NULL;
	g_autofree gchar* variant_label_text = NULL;
	GtkWidget* label;
	GtkWidget* variant_label;

	if (keyboard_input_source_has_display_name(self->source)) {
		label_text = keyboard_input_source_get_display_name(self->source);
	} else {
		g_object_get(self->source, "type", &label_text, NULL);
	}

	gtk_label_set_text(GTK_LABEL(self->label), label_text);

	gtk_widget_show_all(GTK_WIDGET(self));

	G_OBJECT_CLASS(keyboard_input_row_parent_class)->constructed(object);
}

static void keyboard_input_row_dispose(GObject* object) {
	KeyboardInputRow* self = KEYBOARD_INPUT_ROW(object);

	g_clear_pointer(&self->source, g_object_unref);

	G_OBJECT_CLASS(keyboard_input_row_parent_class)->dispose(object);
}

static void keyboard_input_row_get_property(GObject* object, guint property_id, GValue* value, GParamSpec* spec) {
	KeyboardInputRow* self = KEYBOARD_INPUT_ROW(object);

	switch ((KeyboardInputRowProps) property_id) {
		case PROP_INPUT_SOURCE:
			g_value_set_pointer(value, keyboard_input_row_get_source(self));
			break;
	}
}

static void keyboard_input_row_set_property(GObject* object, guint property_id, const GValue* value, GParamSpec* spec) {
	KeyboardInputRow* self = KEYBOARD_INPUT_ROW(object);

	switch ((KeyboardInputRowProps) property_id) {
		case PROP_INPUT_SOURCE:
			keyboard_input_row_set_source(self, g_value_get_object(value));
			break;
	}
}

static void keyboard_input_row_class_init(KeyboardInputRowClass* klass) {
	GObjectClass* class = G_OBJECT_CLASS(klass);
	GtkWidgetClass* widget_class = GTK_WIDGET_CLASS(klass);

	gtk_widget_class_set_template_from_resource(widget_class, "/org/budgie-desktop/keyboard-layout/input-row.ui");
	gtk_widget_class_bind_template_child(widget_class, KeyboardInputRow, label);

	class->constructed = keyboard_input_row_constructed;
	class->dispose = keyboard_input_row_dispose;
	class->get_property = keyboard_input_row_get_property;
	class->set_property = keyboard_input_row_set_property;

	/**
	 * KeyboardInputRow:input-source:
	 *
	 * The [type@Keyboard.InputSource] being displayed.
	 */
	properties[PROP_INPUT_SOURCE] = g_param_spec_object(
		"input-source",
		NULL,
		NULL,
		KEYBOARD_TYPE_INPUT_SOURCE,
		G_PARAM_CONSTRUCT_ONLY | G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS);

	g_object_class_install_properties(class, G_N_ELEMENTS(properties), properties);
}

static void keyboard_input_row_init(KeyboardInputRow* self) {
	gtk_widget_init_template(GTK_WIDGET(self));
	gtk_widget_set_size_request(GTK_WIDGET(self), -1, 32);
}

/******************************************************************************
 * Public API
 *****************************************************************************/

/**
 * keyboard_input_row_new:
 * @source: A #KeyboardInputSource
 * @user_data: User data passed to this function
 *
 * Create a new #KeyboardInputRow.
 *
 * Returns: (transfer full): A new #KeyboardInputRow
 */
KeyboardInputRow* keyboard_input_row_new(KeyboardInputSource* source, G_GNUC_UNUSED gpointer user_data) {
	return g_object_new(KEYBOARD_TYPE_INPUT_ROW, "input-source", source, NULL);
}

/**
 * keyboard_input_row_get_source:
 * @self: A #KeyboardInputRow
 *
 * Gets the #KeyboardInputSource for this row.
 *
 * Returns: (transfer none): The #KeyboardInputSource
 */
KeyboardInputSource* keyboard_input_row_get_source(KeyboardInputRow* self) {
	g_return_val_if_fail(KEYBOARD_IS_INPUT_ROW(self), NULL);

	return self->source;
}

/**
 * keyboard_input_row_set_source:
 * @self: A #KeyboardInputRow
 * @source: (nullable): A #KeyboardInputSource
 *
 * Sets the input source for this row.
 */
void keyboard_input_row_set_source(KeyboardInputRow* self, KeyboardInputSource* source) {
	g_return_if_fail(KEYBOARD_INPUT_ROW(self));

	if (g_set_object(&self->source, source)) {
		g_object_notify_by_pspec(G_OBJECT(self), properties[PROP_INPUT_SOURCE]);
	}
}
