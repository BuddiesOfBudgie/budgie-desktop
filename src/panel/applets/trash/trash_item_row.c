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
 * SECTION:trashitemrow
 * @Short_description: A widget representing a trashed file
 * @Title: TrashItemRow
 *
 * The #TrashItemRow widget displays a trashed file in the trash popover.
 * It conists of a #GtkGrid containing an icon, labels for the file name
 * and timestamp when the file was sent to the trash, and a button to
 * delete the file.
 *
 * Confirming the deletion of a file is done by using a #TrashButtonBar
 * widget.
 *
 * CSS nodes
 *
 * TrashItemRow has a single CSS class with name .trash-item-row
 */

#include <glib/gi18n.h>
#include <pango/pango.h>

#include "trash_button_bar.h"
#include "trash_item_row.h"
#include "trash_notify.h"

enum {
	PROP_TRASH_INFO = 1,
	LAST_PROP
};

static GParamSpec *props[LAST_PROP] = {
	NULL,
};

struct _TrashItemRow {
	GtkListBoxRow parent_instance;

	TrashInfo *trash_info;

	GtkWidget *header;
	GtkWidget *delete_btn;
	TrashButtonBar *confirm_bar;
};

G_DEFINE_FINAL_TYPE(TrashItemRow, trash_item_row, GTK_TYPE_LIST_BOX_ROW)

static void delete_clicked_cb(GtkButton *source, gpointer user_data) {
	(void) source;

	TrashItemRow *self = user_data;
	gboolean revealed;

	revealed = trash_button_bar_get_revealed(self->confirm_bar);

	if (revealed) {
		trash_button_bar_set_revealed(self->confirm_bar, FALSE);
	} else {
		trash_button_bar_set_revealed(self->confirm_bar, TRUE);
	}
}

static void confirm_response_cb(TrashButtonBar *source, GtkResponseType type, gpointer user_data) {
	TrashItemRow *self = user_data;

	trash_button_bar_set_revealed(source, FALSE);

	switch (type) {
		case GTK_RESPONSE_YES:
			trash_item_row_delete(self);
			break;
		default:
			break;
	}
}

static void trash_item_row_constructed(GObject *object) {
	TrashItemRow *self;

	GVariant *raw_icon;
	GIcon *gicon;
	const gchar *name;
	const gchar *path;
	GDateTime *deletion_time;
	gchar *formatted_date;

	GtkWidget *grid;
	GtkWidget *icon;
	GtkWidget *name_label;
	GtkWidget *date_label;
	GtkStyleContext *date_style_context;
	PangoAttrList *attr_list;
	PangoFontDescription *font_description;
	PangoAttribute *font_attr;
	GtkStyleContext *delete_button_style;
	GtkWidget *content_area, *confirm_label;

	self = TRASH_ITEM_ROW(object);

	g_object_get(
		self->trash_info,
		"display-name", &name,
		"icon", &raw_icon,
		"restore-path", &path,
		"deletion-time", &deletion_time,
		NULL);

	gicon = g_icon_deserialize(raw_icon);
	icon = gtk_image_new_from_gicon(gicon, GTK_ICON_SIZE_LARGE_TOOLBAR);
	gtk_widget_set_margin_start(icon, 6);
	gtk_widget_set_margin_end(icon, 6);

	name_label = gtk_label_new(name);
	gtk_widget_set_halign(name_label, GTK_ALIGN_START);
	gtk_widget_set_valign(name_label, GTK_ALIGN_CENTER);
	gtk_widget_set_hexpand(name_label, TRUE);
	gtk_widget_set_tooltip_text(name_label, path);

	attr_list = pango_attr_list_new();
	font_description = pango_font_description_new();
	pango_font_description_set_stretch(font_description, PANGO_STRETCH_ULTRA_CONDENSED);
	pango_font_description_set_weight(font_description, PANGO_WEIGHT_SEMILIGHT);
	font_attr = pango_attr_font_desc_new(font_description);
	pango_attr_list_insert(attr_list, font_attr);

	formatted_date = g_date_time_format(deletion_time, "%d %b %Y %X");
	date_label = gtk_label_new(formatted_date);
	gtk_widget_set_halign(date_label, GTK_ALIGN_START);
	gtk_widget_set_hexpand(date_label, TRUE);
	gtk_label_set_attributes(GTK_LABEL(date_label), attr_list);
	date_style_context = gtk_widget_get_style_context(date_label);
	gtk_style_context_add_class(date_style_context, GTK_STYLE_CLASS_DIM_LABEL);

	self->delete_btn = gtk_button_new_from_icon_name("user-trash-symbolic", GTK_ICON_SIZE_BUTTON);
	delete_button_style = gtk_widget_get_style_context(self->delete_btn);
	gtk_style_context_add_class(delete_button_style, GTK_STYLE_CLASS_DESTRUCTIVE_ACTION);
	gtk_style_context_add_class(delete_button_style, GTK_STYLE_CLASS_FLAT);
	gtk_style_context_add_class(delete_button_style, "circular");
	gtk_widget_set_tooltip_text(self->delete_btn, _("Permanently delete this item"));

	// Confirmation widget

	self->confirm_bar = trash_button_bar_new();
	trash_button_bar_set_revealed(self->confirm_bar, FALSE);

	confirm_label = gtk_label_new(_("Are you sure you want to delete this item?"));
	gtk_label_set_line_wrap(GTK_LABEL(confirm_label), TRUE);

	content_area = trash_button_bar_get_content_area(self->confirm_bar);
	gtk_box_pack_start(GTK_BOX(content_area), confirm_label, TRUE, TRUE, 6);

	trash_button_bar_add_button(self->confirm_bar, _("No"), GTK_RESPONSE_NO);
	trash_button_bar_add_button(self->confirm_bar, _("Yes"), GTK_RESPONSE_YES);

	trash_button_bar_add_response_style_class(self->confirm_bar, GTK_RESPONSE_YES, GTK_STYLE_CLASS_DESTRUCTIVE_ACTION);

	g_signal_connect(self->confirm_bar, "response", G_CALLBACK(confirm_response_cb), self);

	// Grid

	grid = gtk_grid_new();
	gtk_grid_set_column_spacing(GTK_GRID(grid), 6);
	gtk_widget_set_margin_top(GTK_WIDGET(self), 2);
	gtk_widget_set_margin_bottom(GTK_WIDGET(self), 2);

	gtk_grid_attach(GTK_GRID(grid), icon, 0, 0, 2, 2);
	gtk_grid_attach(GTK_GRID(grid), name_label, 2, 0, 1, 1);
	gtk_grid_attach(GTK_GRID(grid), self->delete_btn, 3, 0, 1, 1);
	gtk_grid_attach(GTK_GRID(grid), date_label, 2, 1, 1, 1);
	gtk_grid_attach(GTK_GRID(grid), GTK_WIDGET(self->confirm_bar), 0, 3, 4, 1);

	gtk_container_add(GTK_CONTAINER(self), grid);

	gtk_widget_set_margin_end(GTK_WIDGET(self), 10);
	gtk_widget_show_all(GTK_WIDGET(self));

	g_signal_connect(self->delete_btn, "clicked", G_CALLBACK(delete_clicked_cb), self);

	G_OBJECT_CLASS(trash_item_row_parent_class)->constructed(object);
}

static void trash_item_row_finalize(GObject *object) {
	TrashItemRow *self;

	self = TRASH_ITEM_ROW(object);

	g_object_unref(self->trash_info);

	G_OBJECT_CLASS(trash_item_row_parent_class)->finalize(object);
}

static void trash_item_row_get_property(GObject *object, guint prop_id, GValue *value, GParamSpec *spec) {
	TrashItemRow *self;

	self = TRASH_ITEM_ROW(object);

	switch (prop_id) {
		case PROP_TRASH_INFO:
			g_value_set_pointer(value, trash_item_row_get_info(self));
			break;
		default:
			G_OBJECT_WARN_INVALID_PROPERTY_ID(object, prop_id, spec);
			break;
	}
}

static void trash_item_row_set_property(GObject *object, guint prop_id, const GValue *value, GParamSpec *spec) {
	TrashItemRow *self;
	gpointer pointer;

	self = TRASH_ITEM_ROW(object);

	switch (prop_id) {
		case PROP_TRASH_INFO:
			pointer = g_value_get_pointer(value);
			self->trash_info = g_object_ref_sink(pointer);
			break;
		default:
			G_OBJECT_WARN_INVALID_PROPERTY_ID(object, prop_id, spec);
			break;
	}
}

static void trash_item_row_class_init(TrashItemRowClass *klass) {
	GObjectClass *class;

	class = G_OBJECT_CLASS(klass);

	class->constructed = trash_item_row_constructed;
	class->finalize = trash_item_row_finalize;
	class->get_property = trash_item_row_get_property;
	class->set_property = trash_item_row_set_property;

	// Properties

	props[PROP_TRASH_INFO] = g_param_spec_pointer(
		"trash-info",
		"Trash info",
		"The information for this row",
		G_PARAM_CONSTRUCT_ONLY | G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS);

	g_object_class_install_properties(class, LAST_PROP, props);
}

static void trash_item_row_init(TrashItemRow *self) {
	GtkStyleContext *style;

	style = gtk_widget_get_style_context(GTK_WIDGET(self));

	gtk_style_context_add_class(style, "trash-item-row");
}

/**
 * trash_item_row_new:
 * @trash_info: (transfer full): a #TrashInfo
 *
 * Creates a new #TrashItemRow.
 *
 * Returns: a new #TrashItemRow
 */
TrashItemRow *trash_item_row_new(TrashInfo *trash_info) {
	return g_object_new(TRASH_TYPE_ITEM_ROW, "trash-info", trash_info, NULL);
}

/**
 * trash_item_row_get_info:
 * @self: a #TrashItemRow
 *
 * Gets the #TrashInfo for this row.
 *
 * Returns: (type Trash.Info) (transfer full): the file information for the row
 */
TrashInfo *trash_item_row_get_info(TrashItemRow *self) {
	return g_object_ref(self->trash_info);
}

static void delete_finish(GObject *object, GAsyncResult *result, gpointer user_data) {
	(void) user_data;

	GFile *file;
	g_autoptr(GError) error = NULL;

	file = G_FILE(object);

	g_file_delete_finish(file, result, &error);

	if (error) {
		g_critical("Error deleting file '%s': %s", g_file_get_basename(file), error->message);
		trash_notify_try_send(_("Trash Error"),
			g_strdup_printf(_("Unable to delete '%s': %s"), g_file_get_basename(G_FILE(object)), error->message),
			"user-trash-symbolic");
	}
}

/**
 * trash_item_row_delete:
 * @self: a #TrashItemRow
 *
 * Asynchronously deletes a trashed item.
 */
void trash_item_row_delete(TrashItemRow *self) {
	g_autoptr(GFile) file;
	g_autofree const gchar *name;
	g_autofree gchar *uri;

	name = trash_info_get_name(self->trash_info);
	uri = g_strdup_printf("trash:///%s", name);
	file = g_file_new_for_uri(uri);

	g_file_delete_async(
		file,
		G_PRIORITY_DEFAULT,
		NULL,
		delete_finish,
		NULL);
}

static void restore_finish(GObject *object, GAsyncResult *result, gpointer user_data) {
	(void) user_data;

	gboolean success;
	g_autoptr(GError) error = NULL;

	success = g_file_move_finish(G_FILE(object), result, &error);

	if (!success) {
		g_critical("Error restoring file '%s' to '%s': %s", g_file_get_basename(G_FILE(object)), g_file_get_path(G_FILE(object)), error->message);
		trash_notify_try_send(_("Trash Error"),
			g_strdup_printf(_("Unable to restore '%s': %s"), g_file_get_basename(G_FILE(object)), error->message),
			"user-trash-symbolic");
	}
}

/**
 * trash_item_row_restore:
 * @self: a #TrashItemRow
 *
 * Asynchronously restores a trashed item to its original location.
 */
void trash_item_row_restore(TrashItemRow *self) {
	g_autoptr(GFile) file, restored_file;
	g_autofree const gchar *name;
	g_autofree gchar *uri;
	g_autofree const gchar *restore_path;

	name = trash_info_get_name(self->trash_info);
	uri = g_strdup_printf("trash:///%s", name);
	file = g_file_new_for_uri(uri);
	restore_path = trash_info_get_restore_path(self->trash_info);
	restored_file = g_file_new_for_path(restore_path);

	g_file_move_async(
		file,
		restored_file,
		G_FILE_COPY_ALL_METADATA,
		G_PRIORITY_DEFAULT,
		NULL, NULL, NULL,
		restore_finish,
		NULL);
}

/**
 * trash_item_row_collate_by_date:
 * @self: a #TrashItemRow
 * @other: a #TrashItemRow
 *
 * Compares two TrashItems for sorting, putting them in order by deletion date
 * in ascending order.
 *
 * Returns: < 0 if @self compares before @other, 0 if they compare equal, > 0 if @self compares after @other
 */
gint trash_item_row_collate_by_date(TrashItemRow *self, TrashItemRow *other) {
	return g_date_time_compare(
		trash_info_get_deletion_time(self->trash_info),
		trash_info_get_deletion_time(other->trash_info));
}

/**
 * trash_item_row_collate_by_name:
 * @self: a #TrashItemRow
 * @other: a #TrashItemRow
 *
 * Compares two TrashItems for sorting, putting them in alphabetical order.
 *
 * Returns: < 0 if @self compares before @other, 0 if they compare equal, > 0 if @self compares after @other
 */
gint trash_item_row_collate_by_name(TrashItemRow *self, TrashItemRow *other) {
	return strcoll(
		trash_info_get_name(self->trash_info),
		trash_info_get_name(other->trash_info));
}

/**
 * trash_item_row_collate_by_type:
 * @self: a #TrashItemRow
 * @other: a #TrashItemRow
 *
 * Compares two TrashItems for sorting. This function uses the following rules:
 *
 * 1. Directories should be above regular files
 * 2. Directories should be sorted alphabetically
 * 3. Files should be sorted alphabetically
 *
 * Returns: < 0 if @self compares before @other, 0 if they compare equal, > 0 if @self compares after @other
 */
gint trash_item_row_collate_by_type(TrashItemRow *self, TrashItemRow *other) {
	gint ret = 0;

	if (trash_info_is_directory(self->trash_info) && trash_info_is_directory(other->trash_info)) {
		ret = trash_item_row_collate_by_name(self, other);
	} else if (trash_info_is_directory(self->trash_info) && !trash_info_is_directory(other->trash_info)) {
		ret = -1;
	} else if (!trash_info_is_directory(self->trash_info) && trash_info_is_directory(other->trash_info)) {
		ret = 1;
	} else {
		ret = trash_item_row_collate_by_name(self, other);
	}

	return ret;
}
