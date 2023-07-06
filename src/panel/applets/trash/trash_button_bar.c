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

/**
 * SECTION:trashbuttonbar
 * @Short_description: A widget that emits a signal when a button is clicked
 * @Title: TrashButtonBar
 *
 * The #TrashButtonBar widget is meant to be used similar to a #GtkDialog. It
 * closely resembles a #GtkInfoBar in terms of API and use. The layout of this
 * widget is more focused and thus less flexible than the #GtkInfoBar it resembles.
 *
 * There is a @content_area at the top that can be filled with any widgets of your
 * choice. Or you can leave it empty and it will take up no extra space.
 *
 * Below the content area is a horizontal button bar where the added buttons are put.
 * Clicking one of the buttons will emit the #TrashButtonBar::response signal with
 * the response ID set when the button was created.
 *
 * # CSS nodes
 *
 * TrashButtonBar has a single CSS node with name trashbuttonbar. It has child
 * content areas with the style classes .trash-button-bar-content and
 * .trash-button-bar-actions for the content area and button area, respectively.
 */

#include "trash_button_bar.h"

enum {
	RESPONSE,
	LAST_SIGNAL
};

static guint signals[LAST_SIGNAL];

typedef struct _TrashButtonBarPrivate TrashButtonBarPrivate;

struct _TrashButtonBarPrivate {
	GtkWidget *revealer;
	GtkWidget *content_area;
	GtkWidget *action_area;
};

typedef struct {
	gint response_id;
} ResponseData;

G_DEFINE_TYPE_WITH_PRIVATE(TrashButtonBar, trash_button_bar, GTK_TYPE_BOX)

static void trash_button_bar_class_init(TrashButtonBarClass *klass) {
	GtkWidgetClass *widget_class;

	widget_class = GTK_WIDGET_CLASS(klass);

	// Signals

	/**
	 * TrashButtonBar::response:
	 * @self: a #TrashButtonBar
	 * @response_id: a response ID
	 *
	 * Emitted when a button is clicked to generate
	 * a response. The @reponse_id depends on which
	 * widget was clicked.
	 */
	signals[RESPONSE] = g_signal_new("response",
		G_TYPE_FROM_CLASS(klass),
		G_SIGNAL_RUN_LAST,
		G_STRUCT_OFFSET(TrashButtonBarClass, response),
		NULL, NULL, NULL,
		G_TYPE_NONE,
		1,
		G_TYPE_INT);

	gtk_widget_class_set_css_name(widget_class, "trashbuttonbar");
}

static void trash_button_bar_init(TrashButtonBar *self) {
	TrashButtonBarPrivate *priv;
	GtkStyleContext *content_area_style, *action_area_style;
	GtkWidget *box;

	priv = trash_button_bar_get_instance_private(self);

	priv->content_area = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
	priv->action_area = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);

	content_area_style = gtk_widget_get_style_context(priv->content_area);
	gtk_style_context_add_class(content_area_style, "trash-button-bar-content");

	action_area_style = gtk_widget_get_style_context(priv->action_area);
	gtk_style_context_add_class(action_area_style, "trash-button-bar-actions");

	box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);

	gtk_box_pack_start(GTK_BOX(box), priv->content_area, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(box), priv->action_area, TRUE, TRUE, 6);

	priv->revealer = gtk_revealer_new();
	gtk_revealer_set_reveal_child(GTK_REVEALER(priv->revealer), TRUE);
	gtk_revealer_set_transition_type(GTK_REVEALER(priv->revealer), GTK_REVEALER_TRANSITION_TYPE_SLIDE_DOWN);

	gtk_container_add(GTK_CONTAINER(priv->revealer), box);

	gtk_container_add(GTK_CONTAINER(self), priv->revealer);

	gtk_widget_show_all(GTK_WIDGET(self));
}

/**
 * trash_button_bar_new:
 *
 * Creates a new #TrashButtonBar object.
 *
 * Returns: a new #TrashButtonBar object.
 */
TrashButtonBar *trash_button_bar_new(void) {
	return g_object_new(TRASH_TYPE_BUTTON_BAR, "orientation", GTK_ORIENTATION_VERTICAL, "spacing", 0, NULL);
}

static void response_data_free(gpointer data) {
	g_slice_free(ResponseData, data);
}

static ResponseData *get_response_data(GtkWidget *widget, gboolean create) {
	ResponseData *data;

	data = g_object_get_data(G_OBJECT(widget), "trash-button-bar-response-data");

	if (data == NULL && create) {
		data = g_slice_new(ResponseData);

		g_object_set_data_full(G_OBJECT(widget), "trash-button-bar-response-data", data, response_data_free);
	}

	return data;
}

static GtkWidget *find_button(TrashButtonBar *self, gint response_id) {
	TrashButtonBarPrivate *priv;
	GtkWidget *widget = NULL;
	GList *children, *list;

	priv = trash_button_bar_get_instance_private(self);

	children = gtk_container_get_children(GTK_CONTAINER(priv->action_area));

	for (list = children; list; list = list->next) {
		ResponseData *data;

		data = get_response_data(list->data, FALSE);

		if (data && data->response_id == response_id) {
			widget = list->data;
			break;
		}
	}

	g_list_free(children);

	return widget;
}

static void button_clicked(GtkButton *button, gpointer user_data) {
	TrashButtonBar *self = user_data;
	ResponseData *data;

	data = get_response_data(GTK_WIDGET(button), FALSE);

	g_signal_emit(self, signals[RESPONSE], 0, data->response_id);
}

/**
 * trash_button_bar_add_button:
 * @self: a #TrashButtonBar
 * @text: (transfer none): the text for the button
 * @response_id: a response ID
 *
 * Adds a new button to the bar with a and response ID.
 *
 * The resulting button is returned, though you generally don't need it.
 *
 * Returns: (type Gtk.Button) (transfer none): the created button.
 */
GtkWidget *trash_button_bar_add_button(TrashButtonBar *self, const gchar *text, gint response_id) {
	TrashButtonBarPrivate *priv;
	GtkWidget *button;
	ResponseData *data;

	g_return_val_if_fail(self != NULL, NULL);
	g_return_val_if_fail(text != NULL, NULL);

	priv = trash_button_bar_get_instance_private(self);

	button = gtk_button_new_with_label(text);
	gtk_button_set_use_underline(GTK_BUTTON(button), TRUE);

	// Set the response data to the button
	data = get_response_data(button, TRUE);
	data->response_id = response_id;

	g_signal_connect(button, "clicked", G_CALLBACK(button_clicked), self);

	gtk_box_pack_start(GTK_BOX(priv->action_area), button, TRUE, TRUE, 6);

	gtk_widget_show(button);

	return button;
}

/**
 * trash_button_bar_get_content_area:
 * @self: a #TrashButtonBar
 *
 * Get the content area for @self.
 *
 * Returns: (type Gtk.Box) (transfer none): the content area.
 */
GtkWidget *trash_button_bar_get_content_area(TrashButtonBar *self) {
	TrashButtonBarPrivate *priv;

	g_return_val_if_fail(self != NULL, NULL);

	priv = trash_button_bar_get_instance_private(self);

	return priv->content_area;
}

/**
 * trash_button_bar_get_revealed:
 * @self: a #TrashButtonBar
 *
 * Get whether or not the revealer is showing its contents.
 *
 * Returns: the reveal state of the revealer.
 */
gboolean trash_button_bar_get_revealed(TrashButtonBar *self) {
	TrashButtonBarPrivate *priv;

	g_return_val_if_fail(self != NULL, FALSE);

	priv = trash_button_bar_get_instance_private(self);

	return gtk_revealer_get_reveal_child(GTK_REVEALER(priv->revealer));
}

/**
 * trash_button_bar_add_response_style_class:
 * @self: a #TrashButtonBar
 * @response_id: a response ID
 * @style: (transfer none): a style class
 *
 * Adds a style class to any button with the given @response_id.
 */
void trash_button_bar_add_response_style_class(TrashButtonBar *self, gint response_id, const gchar *style) {
	GtkWidget *widget;
	GtkStyleContext *widget_style;

	g_return_if_fail(self != NULL);
	g_return_if_fail(style != NULL);

	widget = find_button(self, response_id);

	if (widget == NULL) {
		g_warning("Could not find widget for response id");
		return;
	}

	widget_style = gtk_widget_get_style_context(widget);

	gtk_style_context_add_class(widget_style, style);
}

/**
 * trash_button_bar_set_response_sensitive:
 * @self: a #TrashInfoBar
 * @response_id: a response ID
 * @sensitive: TRUE for sensitive
 *
 * Sets the sensitivity of any button that has the given @response_id.
 */
void trash_button_bar_set_response_sensitive(TrashButtonBar *self, gint response_id, gboolean sensitive) {
	GtkWidget *widget;

	g_return_if_fail(self != NULL);

	widget = find_button(self, response_id);

	if (widget == NULL) {
		g_warning("Could not find widget for response id");
		return;
	}

	gtk_widget_set_sensitive(widget, sensitive);
}

/**
 * trash_button_bar_set_revealed:
 * @self: a #TrashButtonBar
 * @reveal: whether or not to show
 *
 * Sets whether or not the revealer should show its contents.
 */
void trash_button_bar_set_revealed(TrashButtonBar *self, gboolean reveal) {
	TrashButtonBarPrivate *priv;

	g_return_if_fail(self != NULL);

	priv = trash_button_bar_get_instance_private(self);

	gtk_revealer_set_reveal_child(GTK_REVEALER(priv->revealer), reveal);
}
