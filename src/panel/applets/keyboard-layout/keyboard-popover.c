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

#include "keyboard-popover.h"

#include <gio-unix-2.0/gio/gdesktopappinfo.h>
#include <glib/gi18n.h>

#include "input-row.h"
#include "keyboard-header.h"

#define _GNU_SOURCE

struct _KeyboardPopover {
	BudgiePopover parent_instance;

	GtkWidget* content;
	GtkWidget* listbox;

	gulong handler_id;

	GListStore* model;
	KeyboardInputSource* current_source;
};

typedef enum {
	PROP_MODEL = 1,
	PROP_CURRENT_SOURCE,
} KeyboardPopoverProps;

static GParamSpec* properties[PROP_CURRENT_SOURCE + 1] = {NULL};

enum {
	SIGNAL_LAYOUT_SELECTED,
};

static guint signals[SIGNAL_LAYOUT_SELECTED + 1];

G_DEFINE_FINAL_TYPE(KeyboardPopover, keyboard_popover, BUDGIE_TYPE_POPOVER)

/******************************************************************************
 * Helpers
 *****************************************************************************/

static GtkWidget* keyboard_popover_get_row_from_source(KeyboardPopover* self, KeyboardInputSource* source) {
	KeyboardInputSource* child_source = NULL;
	GtkWidget* child = NULL;
	GList *children, *elem;

	g_return_val_if_fail(KEYBOARD_IS_POPOVER(self), NULL);
	g_return_val_if_fail(KEYBOARD_IS_INPUT_SOURCE(source), NULL);

	children = gtk_container_get_children(GTK_CONTAINER(self->listbox));

	while (children) {
		if (!KEYBOARD_IS_INPUT_ROW(children->data)) {
			children = children->next;
			continue;
		}

		child_source = keyboard_input_row_get_source(KEYBOARD_INPUT_ROW(children->data));

		if (keyboard_input_source_equal(child_source, source)) {
			child = children->data;
			break;
		}

		children = children->next;
	}

	g_list_free(children);

	if (!child) {
		return NULL;
	}

	return child;
}

/******************************************************************************
 * Callbacks
 *****************************************************************************/

static void keyboard_popover_row_selected_cb(G_GNUC_UNUSED GtkListBox* list_box, GtkListBoxRow* row, gpointer user_data) {
	KeyboardPopover* self = KEYBOARD_POPOVER(user_data);
	KeyboardInputRow* input_row = KEYBOARD_INPUT_ROW(row);
	KeyboardInputSource* source = NULL;

	if (row == NULL) {
		return;
	}

	source = keyboard_input_row_get_source(input_row);

	g_signal_emit(self, signals[SIGNAL_LAYOUT_SELECTED], 0, source);
}

/******************************************************************************
 * GObject
 *****************************************************************************/

static void keyboard_popover_constructed(GObject* object) {
	KeyboardPopover* self = KEYBOARD_POPOVER(object);

	gtk_list_box_bind_model(GTK_LIST_BOX(self->listbox), self->model, (GtkListBoxCreateWidgetFunc) keyboard_input_row_new, NULL, NULL);

	self->handler_id = g_signal_connect(self->listbox, "row-selected", G_CALLBACK(keyboard_popover_row_selected_cb), self);

	gtk_widget_show_all(self->content);

	G_OBJECT_CLASS(keyboard_popover_parent_class)->constructed(object);
}

static void
keyboard_popover_dispose(GObject* object) {
	KeyboardPopover* self = KEYBOARD_POPOVER(object);

	g_clear_object(&self->current_source);

	G_OBJECT_CLASS(keyboard_popover_parent_class)->dispose(object);
}

void keyboard_popover_get_property(GObject* object, guint property_id, GValue* value, GParamSpec* spec) {
	KeyboardPopover* self = KEYBOARD_POPOVER(object);

	switch ((KeyboardPopoverProps) property_id) {
		case PROP_MODEL:
			g_value_set_pointer(value, keyboard_popover_get_model(self));
			break;
		case PROP_CURRENT_SOURCE:
			g_value_set_pointer(value, keyboard_popover_get_current_source(self));
			break;
	}
}

void keyboard_popover_set_property(GObject* object, guint property_id, const GValue* value, GParamSpec* spec) {
	KeyboardPopover* self = KEYBOARD_POPOVER(object);
	gpointer ptr = NULL;

	switch ((KeyboardPopoverProps) property_id) {
		case PROP_MODEL:
			keyboard_popover_set_model(self, g_value_get_object(value));
			break;
		case PROP_CURRENT_SOURCE:
			keyboard_popover_set_current_source(self, g_value_get_object(value));
			break;
	}
}

static void keyboard_popover_class_init(KeyboardPopoverClass* klass) {
	GObjectClass* object_class = G_OBJECT_CLASS(klass);
	GtkWidgetClass* widget_class = GTK_WIDGET_CLASS(klass);

	object_class->constructed = keyboard_popover_constructed;
	object_class->dispose = keyboard_popover_dispose;
	object_class->get_property = keyboard_popover_get_property;
	object_class->set_property = keyboard_popover_set_property;

	g_type_ensure(KEYBOARD_TYPE_HEADER);

	gtk_widget_class_set_template_from_resource(widget_class, "/org/budgie-desktop/keyboard-layout/keyboard-popover.ui");
	gtk_widget_class_bind_template_child(widget_class, KeyboardPopover, content);
	gtk_widget_class_bind_template_child(widget_class, KeyboardPopover, listbox);

	/**
	 * KeyboardPopover::layout-selected:
	 * @popover: The #KeyboardPopover
	 * @source: The #KeyboardInputSource that was selected
	 *
	 * Emitted when a new keyboard layout has been selected.
	 */
	signals[SIGNAL_LAYOUT_SELECTED] = g_signal_new(
		"layout-selected",
		G_TYPE_FROM_CLASS(klass),
		G_SIGNAL_RUN_LAST,
		0,
		NULL, NULL, NULL,
		G_TYPE_NONE,
		1,
		G_TYPE_POINTER);

	/**
	 * KeyboardPopover:model:
	 *
	 * The model of configured input sources.
	 *
	 * This model will be used by the internal list box to display
	 * the configured input sources.
	 */
	properties[PROP_MODEL] = g_param_spec_object(
		"model",
		NULL,
		NULL,
		G_TYPE_LIST_STORE,
		G_PARAM_CONSTRUCT_ONLY | G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS);

	/**
	 * KeyboardPopover:current-source:
	 *
	 * The current [type@Keyboard.InputSource] being used.
	 */
	properties[PROP_CURRENT_SOURCE] = g_param_spec_object(
		"current-source",
		NULL,
		NULL,
		KEYBOARD_TYPE_INPUT_SOURCE,
		G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS);

	g_object_class_install_properties(object_class, G_N_ELEMENTS(properties), properties);
}

static void keyboard_popover_init(KeyboardPopover* self) {
	self->model = NULL;
	self->current_source = NULL;
	self->handler_id = 0;

	gtk_widget_init_template(GTK_WIDGET(self));
	gtk_widget_set_size_request(GTK_WIDGET(self), 275, -1);
}

/******************************************************************************
 * Public API
 *****************************************************************************/

/**
 * keyboard_popover_new:
 * @relative_to: The #GtkWidget that the popover is connected to
 * @current_source: The currently configured #KeyboardInputSource
 * @model: The model of configured input sources
 *
 * Creates a new #KeyboardPopover.
 *
 * Returns: (transfer full): A new #KeyboardPopover
 */
KeyboardPopover* keyboard_popover_new(GtkWidget* relative_to, GListStore* model) {
	return g_object_new(
		KEYBOARD_TYPE_POPOVER,
		"relative-to", relative_to,
		"model", model,
		NULL);
}

/**
 * keyboard_popover_get_current_source:
 * @self: A #KeyboardPopover
 *
 * Gets the current input source.
 *
 * Returns: (transfer none): A #KeyboardInputSource
 */
KeyboardInputSource* keyboard_popover_get_current_source(KeyboardPopover* self) {
	g_return_val_if_fail(KEYBOARD_IS_POPOVER(self), NULL);

	return self->current_source;
}

/**
 * keyboard_popover_set_current_source:
 * @self: A #KeyboardPopover
 * @current_source: (nullable): The new current #KeyboardInputSource
 *
 * Update the selected row for the given input source.
 */
void keyboard_popover_set_current_source(KeyboardPopover* self, KeyboardInputSource* current_source) {
	GtkWidget* row = NULL;

	g_return_if_fail(KEYBOARD_IS_POPOVER(self));

	if (g_set_object(&self->current_source, current_source)) {
		g_object_notify_by_pspec(G_OBJECT(self), properties[PROP_CURRENT_SOURCE]);
	}

	if (!KEYBOARD_IS_INPUT_SOURCE(self->current_source)) {
		g_debug("Unselecting all input sources");
		gtk_list_box_unselect_all(GTK_LIST_BOX(self->listbox));
		return;
	}

	row = keyboard_popover_get_row_from_source(self, current_source);

	if G_UNLIKELY (!GTK_LIST_BOX_ROW(row)) {
		return;
	}

	g_signal_handler_block(self->listbox, self->handler_id);
	gtk_list_box_select_row(GTK_LIST_BOX(self->listbox), GTK_LIST_BOX_ROW(row));
	g_signal_handler_unblock(self->listbox, self->handler_id);
}

/**
 * keyboard_popover_get_model:
 * @self: A #KeyboardPopover
 *
 * Gets the model for the internal listbox.
 *
 * Returns: (transfer none): A #GListStore
 */
GListStore* keyboard_popover_get_model(KeyboardPopover* self) {
	g_return_val_if_fail(KEYBOARD_IS_POPOVER(self), NULL);

	return self->model;
}

/**
 * keyboard_popover_set_model:
 * @self: A #KeyboardPopover
 * @model: (nullable): A model to bind to an internal listbox
 *
 * Sets the model for the internal listbox.
 */
void keyboard_popover_set_model(KeyboardPopover* self, GListStore* model) {
	g_return_if_fail(KEYBOARD_IS_POPOVER(self));

	if (g_set_object(&self->model, model)) {
		g_object_notify_by_pspec(G_OBJECT(self), properties[PROP_MODEL]);
	}
}
