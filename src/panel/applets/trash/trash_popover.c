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
 * SECTION:trashpopover
 * @Short_description: A widget that makes up the body of a popover
 * @Title: TrashPopover
 *
 * The #TrashPopover widget is the contents of the trash applet's popover. It
 * consists of a header and a list of files below it, as well as buttons to
 * restore items or empty the trash bin.
 */

#include <glib/gi18n.h>

#include "trash_button_bar.h"
#include "trash_info.h"
#include "trash_item_row.h"
#include "trash_manager.h"
#include "trash_popover.h"
#include "trash_settings.h"

enum {
	TRASH_RESPONSE_EMPTY = 1,
	TRASH_RESPONSE_RESTORE
};

enum {
	PROP_SETTINGS = 1,
	LAST_PROP
};

enum {
	TRASH_EMPTY,
	TRASH_FILLED,
	LAST_SIGNAL
};

static GParamSpec *props[LAST_PROP] = {
	NULL,
};
static guint signals[LAST_SIGNAL];

struct _TrashPopover {
	GtkBox parent_instance;

	TrashManager *trash_manager;

	GSettings *settings;
	TrashSortMode sort_mode;

	GtkWidget *stack;
	GtkWidget *file_box;
	TrashButtonBar *button_bar;
	TrashButtonBar *confirm_bar;
};

G_DEFINE_TYPE(TrashPopover, trash_popover, GTK_TYPE_BOX)

static gint list_box_sort_func(GtkListBoxRow *row1, GtkListBoxRow *row2, gpointer user_data) {
	TrashPopover *self = user_data;
	TrashItemRow *a;
	TrashItemRow *b;

	a = TRASH_ITEM_ROW(row1);
	b = TRASH_ITEM_ROW(row2);

	switch (self->sort_mode) {
		case TRASH_SORT_A_Z:
			return trash_item_row_collate_by_name(a, b);
		case TRASH_SORT_Z_A:
			return trash_item_row_collate_by_name(b, a);
		case TRASH_SORT_DATE_DESCENDING:
			return trash_item_row_collate_by_date(b, a);
		case TRASH_SORT_DATE_ASCENDING:
			return trash_item_row_collate_by_date(a, b);
		case TRASH_SORT_TYPE:
		default:
			return trash_item_row_collate_by_type(a, b);
	}
}

static void settings_changed(GSettings *settings, gchar *key, gpointer user_data) {
	TrashPopover *self = user_data;
	TrashSortMode new_sort_mode;

	new_sort_mode = (TrashSortMode) g_settings_get_enum(settings, key);

	if (new_sort_mode == self->sort_mode) {
		return;
	}

	self->sort_mode = new_sort_mode;

	gtk_list_box_invalidate_sort(GTK_LIST_BOX(self->file_box));
}

static void settings_clicked(GtkButton *button, TrashPopover *self) {
	GtkStack *stack;
	GtkWidget *image;
	const gchar *current_name = NULL;

	stack = GTK_STACK(self->stack);
	current_name = gtk_stack_get_visible_child_name(stack);

	if (g_strcmp0(current_name, "main") == 0) {
		gtk_stack_set_visible_child_name(stack, "settings");

		image = gtk_image_new_from_icon_name("user-trash-symbolic", GTK_ICON_SIZE_BUTTON);
		gtk_button_set_image(button, image);
		gtk_widget_set_tooltip_text(GTK_WIDGET(button), _("Trash Bin"));
	} else {
		gtk_stack_set_visible_child_name(stack, "main");

		image = gtk_image_new_from_icon_name("system-settings-symbolic", GTK_ICON_SIZE_BUTTON);
		gtk_button_set_image(button, image);
		gtk_widget_set_tooltip_text(GTK_WIDGET(button), _("Settings"));
	}
}

static void trash_added(TrashManager *manager, TrashInfo *trash_info, TrashPopover *self) {
	(void) manager;
	TrashItemRow *row;

	row = trash_item_row_new(trash_info);

	gtk_list_box_insert(GTK_LIST_BOX(self->file_box), GTK_WIDGET(row), -1);

	gtk_list_box_invalidate_sort(GTK_LIST_BOX(self->file_box));

	g_signal_emit(self, signals[TRASH_FILLED], 0, NULL);
}

static void foreach_item_cb(TrashItemRow *row, gchar *uri) {
	TrashInfo *info;
	g_autofree const gchar *info_uri;

	info = trash_item_row_get_info(row);
	info_uri = trash_info_get_uri(info);

	if (g_strcmp0(info_uri, uri) == 0) {
		gtk_widget_destroy(GTK_WIDGET(row));
	}
}

static void trash_removed(TrashManager *manager, gchar *name, TrashPopover *self) {
	(void) manager;
	gint count;

	gtk_container_foreach(GTK_CONTAINER(self->file_box), (GtkCallback) foreach_item_cb, name);

	gtk_list_box_invalidate_sort(GTK_LIST_BOX(self->file_box));

	count = trash_manager_get_item_count(self->trash_manager);
	if (count == 0) {
		g_signal_emit(self, signals[TRASH_EMPTY], 0, NULL);
	}
}

static void selected_rows_changed(GtkListBox *source, gpointer user_data) {
	TrashButtonBar *button_bar = user_data;
	GList *selected_rows;
	guint count;

	selected_rows = gtk_list_box_get_selected_rows(source);
	count = g_list_length(selected_rows);

	trash_button_bar_set_response_sensitive(button_bar, TRASH_RESPONSE_RESTORE, count > 0);
	g_list_free(selected_rows);
}

static void delete_item(GtkWidget *widget, gpointer user_data) {
	(void) user_data;

	trash_item_row_delete(TRASH_ITEM_ROW(widget));
}

static void restore_item(gpointer data, gpointer user_data) {
	(void) user_data;
	TrashItemRow *row = data;

	trash_item_row_restore(row);
}

static void handle_response_cb(TrashButtonBar *source, gint response, gpointer user_data) {
	(void) source;
	TrashPopover *self = user_data;
	GList *selected_rows;

	switch (response) {
		case TRASH_RESPONSE_RESTORE:
			selected_rows = gtk_list_box_get_selected_rows(GTK_LIST_BOX(self->file_box));
			g_list_foreach(selected_rows, restore_item, NULL);
			g_list_free(selected_rows);
			break;
		case TRASH_RESPONSE_EMPTY:
			trash_button_bar_set_revealed(self->button_bar, FALSE);
			trash_button_bar_set_revealed(self->confirm_bar, TRUE);
			break;
	}
}

static void confirm_response_cb(TrashButtonBar *source, gint response_id, gpointer user_data) {
	TrashPopover *self = user_data;

	switch (response_id) {
		case GTK_RESPONSE_YES:
			gtk_container_foreach(GTK_CONTAINER(self->file_box), delete_item, NULL);
			break;
		default:
			break;
	}

	trash_button_bar_set_revealed(source, FALSE);
	trash_button_bar_set_revealed(self->button_bar, TRUE);
}

static void trash_popover_constructed(GObject *object) {
	TrashPopover *self;
	GtkWidget *header;
	PangoAttrList *attr_list;
	PangoFontDescription *font_description;
	PangoAttribute *font_attr;
	GtkWidget *header_label;
	GtkWidget *settings_button;
	GtkStyleContext *header_label_style;
	GtkStyleContext *settings_button_style;
	GtkWidget *separator;
	GtkWidget *main_view;
	GtkWidget *scroller;
	GtkWidget *content_area, *confirm_label;
	GtkWidget *btn;
	TrashSettings *settings_view;

	self = TRASH_POPOVER(object);

	gtk_widget_set_size_request(GTK_WIDGET(self), -1, 256);

	// Settings
	self->sort_mode = (TrashSortMode) g_settings_get_enum(self->settings, TRASH_SETTINGS_KEY_SORT_MODE);
	g_signal_connect(self->settings, "changed", G_CALLBACK(settings_changed), self);

	// Create our header
	header = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
	gtk_widget_set_margin_start(header, 4);
	gtk_widget_set_margin_end(header, 4);

	// Text attribute to make the label bold

	attr_list = pango_attr_list_new();
	font_description = pango_font_description_new();
	pango_font_description_set_weight(font_description, PANGO_WEIGHT_BOLD);
	font_attr = pango_attr_font_desc_new(font_description);
	pango_attr_list_insert(attr_list, font_attr);

	// Header label
	header_label = gtk_label_new(_("Trash"));
	gtk_label_set_attributes(GTK_LABEL(header_label), attr_list);
	gtk_widget_set_halign(header_label, GTK_ALIGN_START);
	gtk_widget_set_margin_start(header_label, 4);

	header_label_style = gtk_widget_get_style_context(header_label);
	gtk_style_context_add_class(header_label_style, GTK_STYLE_CLASS_DIM_LABEL);

	settings_button = gtk_button_new_from_icon_name("preferences-system-symbolic", GTK_ICON_SIZE_BUTTON);
	gtk_widget_set_tooltip_text(settings_button, _("Trash Applet Settings"));
	g_signal_connect(settings_button, "clicked", G_CALLBACK(settings_clicked), self);

	settings_button_style = gtk_widget_get_style_context(settings_button);
	gtk_style_context_add_class(settings_button_style, GTK_STYLE_CLASS_FLAT);
	gtk_style_context_remove_class(settings_button_style, GTK_STYLE_CLASS_BUTTON);

	separator = gtk_separator_new(GTK_ORIENTATION_HORIZONTAL);

	// Pack up the header
	gtk_box_pack_start(GTK_BOX(header), header_label, TRUE, TRUE, 0);
	gtk_box_pack_end(GTK_BOX(header), settings_button, FALSE, FALSE, 0);

	// Create our main view

	self->button_bar = trash_button_bar_new();

	btn = trash_button_bar_add_button(self->button_bar, _("Restore"), TRASH_RESPONSE_RESTORE);
	gtk_widget_set_tooltip_text(btn, _("Restore selected items"));

	btn = trash_button_bar_add_button(self->button_bar, _("Empty"), TRASH_RESPONSE_EMPTY);
	gtk_widget_set_tooltip_text(btn, _("Empty the trash bin"));

	g_signal_connect(self->button_bar, "response", G_CALLBACK(handle_response_cb), self);

	self->confirm_bar = trash_button_bar_new();
	trash_button_bar_set_revealed(self->confirm_bar, FALSE);

	confirm_label = gtk_label_new(_("Are you sure you want to empty the trash bin?"));
	gtk_label_set_attributes(GTK_LABEL(confirm_label), attr_list);
	gtk_label_set_line_wrap(GTK_LABEL(confirm_label), TRUE);
	gtk_label_set_max_width_chars(GTK_LABEL(confirm_label), 32);
	gtk_label_set_width_chars(GTK_LABEL(confirm_label), 32);

	content_area = trash_button_bar_get_content_area(self->confirm_bar);
	gtk_box_pack_start(GTK_BOX(content_area), confirm_label, TRUE, TRUE, 6);

	trash_button_bar_add_button(self->confirm_bar, _("No"), GTK_RESPONSE_NO);
	trash_button_bar_add_button(self->confirm_bar, _("Yes"), GTK_RESPONSE_YES);

	trash_button_bar_add_response_style_class(self->confirm_bar, GTK_RESPONSE_YES, GTK_STYLE_CLASS_DESTRUCTIVE_ACTION);

	g_signal_connect(self->confirm_bar, "response", G_CALLBACK(confirm_response_cb), self);

	// Create our drive list box
	self->file_box = gtk_list_box_new();
	gtk_list_box_set_activate_on_single_click(GTK_LIST_BOX(self->file_box), FALSE);
	gtk_list_box_set_selection_mode(GTK_LIST_BOX(self->file_box), GTK_SELECTION_MULTIPLE);
	gtk_list_box_set_sort_func(GTK_LIST_BOX(self->file_box), list_box_sort_func, self, NULL);

	g_signal_connect(self->file_box, "selected-rows-changed", G_CALLBACK(selected_rows_changed), self->button_bar);

	// Create our scrolled window
	scroller = gtk_scrolled_window_new(NULL, NULL);
	gtk_scrolled_window_set_max_content_height(GTK_SCROLLED_WINDOW(scroller), 256);
	gtk_scrolled_window_set_propagate_natural_height(GTK_SCROLLED_WINDOW(scroller), TRUE);
	gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroller), GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);

	gtk_container_add(GTK_CONTAINER(scroller), self->file_box);

	main_view = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
	selected_rows_changed(GTK_LIST_BOX(self->file_box), self->button_bar);
	gtk_container_add(GTK_CONTAINER(main_view), GTK_WIDGET(self->button_bar));
	gtk_container_add(GTK_CONTAINER(main_view), GTK_WIDGET(self->confirm_bar));
	gtk_container_add(GTK_CONTAINER(main_view), scroller);
	gtk_widget_show_all(main_view);

	// Create our stack
	self->stack = gtk_stack_new();
	gtk_stack_set_transition_type(GTK_STACK(self->stack), GTK_STACK_TRANSITION_TYPE_SLIDE_LEFT_RIGHT);
	gtk_stack_add_named(GTK_STACK(self->stack), main_view, "main");

	// Trash Manager hookups

	self->trash_manager = trash_manager_new();

	g_signal_connect(self->trash_manager, "trash-added", G_CALLBACK(trash_added), self);
	g_signal_connect(self->trash_manager, "trash-removed", G_CALLBACK(trash_removed), self);

	trash_manager_scan_items(self->trash_manager);

	// Create our settings view
	settings_view = trash_settings_new(self->settings);
	gtk_stack_add_named(GTK_STACK(self->stack), GTK_WIDGET(settings_view), "settings");

	// Pack ourselves up
	gtk_box_pack_start(GTK_BOX(self), header, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(self), separator, FALSE, FALSE, 2);
	gtk_box_pack_start(GTK_BOX(self), self->stack, TRUE, TRUE, 0);
	gtk_widget_show_all(GTK_WIDGET(self));
	gtk_stack_set_visible_child_name(GTK_STACK(self->stack), "main");
	gtk_widget_show_all(self->stack);

	G_OBJECT_CLASS(trash_popover_parent_class)->constructed(object);
}

static void trash_popover_finalize(GObject *object) {
	TrashPopover *self;

	self = TRASH_POPOVER(object);

	g_object_unref(self->trash_manager);
	g_object_unref(self->settings);

	G_OBJECT_CLASS(trash_popover_parent_class)->finalize(object);
}

static void trash_popover_get_property(GObject *object, guint prop_id, GValue *value, GParamSpec *spec) {
	TrashPopover *self;

	self = TRASH_POPOVER(object);

	switch (prop_id) {
		case PROP_SETTINGS:
			g_value_set_pointer(value, g_object_ref(self->settings));
			break;
		default:
			G_OBJECT_WARN_INVALID_PROPERTY_ID(object, prop_id, spec);
			break;
	}
}

static void trash_popover_set_property(GObject *object, guint prop_id, const GValue *value, GParamSpec *spec) {
	TrashPopover *self;

	self = TRASH_POPOVER(object);

	switch (prop_id) {
		case PROP_SETTINGS:
			self->settings = g_object_ref(g_value_get_pointer(value));
			break;
		default:
			G_OBJECT_WARN_INVALID_PROPERTY_ID(object, prop_id, spec);
			break;
	}
}

static void trash_popover_class_init(TrashPopoverClass *klass) {
	GObjectClass *class;

	class = G_OBJECT_CLASS(klass);
	class->constructed = trash_popover_constructed;
	class->finalize = trash_popover_finalize;
	class->get_property = trash_popover_get_property;
	class->set_property = trash_popover_set_property;

	// Properties

	props[PROP_SETTINGS] = g_param_spec_pointer(
		"settings",
		"Settings",
		"The applet instance settings for this Trash Applet",
		G_PARAM_CONSTRUCT_ONLY | G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS);

	// Signals

	/**
	 * TrashPopover::trash-empty:
	 * @self: a #TrashPopover
	 *
	 * Emitted when there are no more items in the trash bin.
	 */
	signals[TRASH_EMPTY] = g_signal_new("trash-empty",
		G_TYPE_FROM_CLASS(klass),
		G_SIGNAL_RUN_LAST,
		0,
		NULL, NULL, NULL,
		G_TYPE_NONE,
		0,
		NULL);

	/**
	 * TrashPopover::trash-filled:
	 * @self: a #TrashPopover
	 *
	 * Emitted when something has been added to the trash bin.
	 */
	signals[TRASH_FILLED] = g_signal_new("trash-filled",
		G_TYPE_FROM_CLASS(klass),
		G_SIGNAL_RUN_LAST,
		0,
		NULL, NULL, NULL,
		G_TYPE_NONE,
		0,
		NULL);

	g_object_class_install_properties(class, LAST_PROP, props);
}

static void trash_popover_init(TrashPopover *self) {
	(void) self;
}

/**
 * trash_popover_new:
 * @settings: (transfer full): a #GSettings object
 *
 * Creates a new #TrashPopover.
 *
 * Retruns: a new #TrashPopover
 */
TrashPopover *trash_popover_new(GSettings *settings) {
	return g_object_new(TRASH_TYPE_POPOVER, "settings", settings, "orientation", GTK_ORIENTATION_VERTICAL, "spacing", 0, NULL);
}
