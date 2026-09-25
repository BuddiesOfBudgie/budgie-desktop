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

#include <glib/gi18n.h>

#include "input-row.h"
#include "keyboard-header.h"

struct _KeyboardPopover {
	BudgiePopover parent_instance;

	GtkWidget* content;
	GtkWidget* listbox;

	/* Set while we move the selection ourselves, so row-selected can tell that
	 * apart from the user picking a row */
	gboolean syncing_selection;

	/* The row and event time of the last emit, compared only, never dereferenced */
	GtkListBoxRow* emitted_row;
	guint32 emitted_time;
};

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

	/* g_list_free walks forward from whatever node it is given, so iterate with
	 * elem and leave children pointing at the head. */
	for (elem = children; elem != NULL; elem = elem->next) {
		child_source = keyboard_input_row_get_source(KEYBOARD_INPUT_ROW(elem->data));

		if (keyboard_input_source_equal(child_source, source)) {
			child = elem->data;
			break;
		}
	}

	g_list_free(children);

	return child;
}

static void keyboard_popover_emit_layout_selected(KeyboardPopover* self, GtkListBoxRow* row) {
	self->emitted_row = row;
	self->emitted_time = gtk_get_current_event_time();

	g_signal_emit(self, signals[SIGNAL_LAYOUT_SELECTED], 0, keyboard_input_row_get_source(KEYBOARD_INPUT_ROW(row)));
}

/******************************************************************************
 * Callbacks
 *****************************************************************************/

static void keyboard_popover_row_selected_cb(G_GNUC_UNUSED GtkListBox* list_box, GtkListBoxRow* row, gpointer user_data) {
	KeyboardPopover* self = KEYBOARD_POPOVER(user_data);

	if (self->syncing_selection || row == NULL) {
		return;
	}

	keyboard_popover_emit_layout_selected(self, row);
}

static void keyboard_popover_row_activated_cb(G_GNUC_UNUSED GtkListBox* list_box, GtkListBoxRow* row, gpointer user_data) {
	KeyboardPopover* self = KEYBOARD_POPOVER(user_data);

	/* A click or Return on an unselected row emits row-selected and then
	 * row-activated for the same event */
	if (row == NULL || (row == self->emitted_row && gtk_get_current_event_time() == self->emitted_time)) {
		return;
	}

	keyboard_popover_emit_layout_selected(self, row);
}

/******************************************************************************
 * GObject
 *****************************************************************************/

static void keyboard_popover_class_init(KeyboardPopoverClass* klass) {
	GtkWidgetClass* widget_class = GTK_WIDGET_CLASS(klass);

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
		KEYBOARD_TYPE_INPUT_SOURCE);
}

static void keyboard_popover_init(KeyboardPopover* self) {
	self->syncing_selection = FALSE;
	self->emitted_row = NULL;
	self->emitted_time = 0;

	gtk_widget_init_template(GTK_WIDGET(self));
	gtk_widget_set_size_request(GTK_WIDGET(self), 275, -1);

	/* Arrow keys move the selection without activating, and a click on the
	 * already-selected row activates without moving it, so both are needed */
	g_signal_connect(self->listbox, "row-selected", G_CALLBACK(keyboard_popover_row_selected_cb), self);
	g_signal_connect(self->listbox, "row-activated", G_CALLBACK(keyboard_popover_row_activated_cb), self);

	gtk_widget_show_all(self->content);
}

/******************************************************************************
 * Public API
 *****************************************************************************/

/**
 * keyboard_popover_new:
 * @relative_to: The #GtkWidget that the popover is connected to
 * @model: The model of configured input sources
 *
 * Creates a new #KeyboardPopover.
 *
 * Returns: (transfer full): A new #KeyboardPopover
 */
KeyboardPopover* keyboard_popover_new(GtkWidget* relative_to, GListStore* model) {
	KeyboardPopover* self = g_object_new(KEYBOARD_TYPE_POPOVER, "relative-to", relative_to, NULL);

	gtk_list_box_bind_model(GTK_LIST_BOX(self->listbox), G_LIST_MODEL(model), (GtkListBoxCreateWidgetFunc) keyboard_input_row_new, NULL, NULL);

	return self;
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

	if (!KEYBOARD_IS_INPUT_SOURCE(current_source)) {
		g_debug("Unselecting all input sources");
		self->syncing_selection = TRUE;
		gtk_list_box_unselect_all(GTK_LIST_BOX(self->listbox));
		self->syncing_selection = FALSE;
		return;
	}

	row = keyboard_popover_get_row_from_source(self, current_source);

	if G_UNLIKELY (row == NULL) {
		return;
	}

	self->syncing_selection = TRUE;
	gtk_list_box_select_row(GTK_LIST_BOX(self->listbox), GTK_LIST_BOX_ROW(row));
	self->syncing_selection = FALSE;
}
