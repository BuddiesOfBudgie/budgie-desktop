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
 * SECTION:trashsettings
 * @Short_description: A widget that exposes the applet's settings
 * @Title: TrashSettings
 *
 * The #TrashSettings widget contains controls that bind to the applet settings.
 */

#include "trash_settings.h"

struct _TrashSettings {
	GtkGrid parent_instance;

	GSettings *settings;

	gboolean update_setting;

	GtkRadioButton *btn_sort_type;
	GtkRadioButton *btn_sort_alphabetical;
	GtkRadioButton *btn_sort_reverse_alphabetical;
	GtkRadioButton *btn_sort_date_ascending;
	GtkRadioButton *btn_sort_date_descending;
};

G_DEFINE_FINAL_TYPE(TrashSettings, trash_settings, GTK_TYPE_GRID)

static void trash_settings_finalize(GObject *obj) {
	TrashSettings *self = TRASH_SETTINGS(obj);

	if (self->settings) {
		g_object_unref(self->settings);
	}

	G_OBJECT_CLASS(trash_settings_parent_class)->finalize(obj);
}

static void trash_settings_class_init(TrashSettingsClass *klass) {
	GObjectClass *class;

	class = G_OBJECT_CLASS(klass);

	gtk_widget_class_set_template_from_resource(GTK_WIDGET_CLASS(klass), "/com/solus-project/trash/settings.ui");
	gtk_widget_class_bind_template_child(GTK_WIDGET_CLASS(klass), TrashSettings, btn_sort_type);
	gtk_widget_class_bind_template_child(GTK_WIDGET_CLASS(klass), TrashSettings, btn_sort_alphabetical);
	gtk_widget_class_bind_template_child(GTK_WIDGET_CLASS(klass), TrashSettings, btn_sort_reverse_alphabetical);
	gtk_widget_class_bind_template_child(GTK_WIDGET_CLASS(klass), TrashSettings, btn_sort_date_ascending);
	gtk_widget_class_bind_template_child(GTK_WIDGET_CLASS(klass), TrashSettings, btn_sort_date_descending);

	class->finalize = trash_settings_finalize;
}

static void button_toggled(GtkToggleButton *button, gpointer user_data) {
	TrashSettings *self = user_data;
	GtkRadioButton *radio_btn;
	TrashSortMode new_mode;

	// Do nothing if being toggled off
	if (!gtk_toggle_button_get_active(button)) {
		return;
	}

	// Do nothing if the setting shouldn't be updated, e.g. during a UI update
	if (!self->update_setting) {
		return;
	}

	radio_btn = GTK_RADIO_BUTTON(button);

	if (radio_btn == self->btn_sort_alphabetical) {
		new_mode = TRASH_SORT_A_Z;
	} else if (radio_btn == self->btn_sort_reverse_alphabetical) {
		new_mode = TRASH_SORT_Z_A;
	} else if (radio_btn == self->btn_sort_date_ascending) {
		new_mode = TRASH_SORT_DATE_ASCENDING;
	} else if (radio_btn == self->btn_sort_date_descending) {
		new_mode = TRASH_SORT_DATE_DESCENDING;
	} else {
		new_mode = TRASH_SORT_TYPE;
	}

	g_settings_set_enum(self->settings, TRASH_SETTINGS_KEY_SORT_MODE, new_mode);
}

static void trash_settings_init(TrashSettings *self) {
	gtk_widget_init_template(GTK_WIDGET(self));

	g_signal_connect(self->btn_sort_type, "toggled", G_CALLBACK(button_toggled), self);
	g_signal_connect(self->btn_sort_alphabetical, "toggled", G_CALLBACK(button_toggled), self);
	g_signal_connect(self->btn_sort_reverse_alphabetical, "toggled", G_CALLBACK(button_toggled), self);
	g_signal_connect(self->btn_sort_date_ascending, "toggled", G_CALLBACK(button_toggled), self);
	g_signal_connect(self->btn_sort_date_descending, "toggled", G_CALLBACK(button_toggled), self);

	self->update_setting = TRUE;
}

static void settings_changed(GSettings *settings, gchar *key, gpointer user_data) {
	TrashSettings *self = user_data;
	TrashSortMode new_mode;

	if (g_strcmp0(key, TRASH_SETTINGS_KEY_SORT_MODE) == 0) {
		new_mode = (TrashSortMode) g_settings_get_enum(settings, key);

		// We don't want to trigger an infinite update loop, so don't update the GSettings
		// until after our UI state is updated.
		self->update_setting = FALSE;

		switch (new_mode) {
			case TRASH_SORT_A_Z:
				gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(self->btn_sort_alphabetical), TRUE);
				break;
			case TRASH_SORT_Z_A:
				gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(self->btn_sort_reverse_alphabetical), TRUE);
				break;
			case TRASH_SORT_DATE_ASCENDING:
				gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(self->btn_sort_date_ascending), TRUE);
				break;
			case TRASH_SORT_DATE_DESCENDING:
				gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(self->btn_sort_date_descending), TRUE);
				break;
			case TRASH_SORT_TYPE:
				gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(self->btn_sort_type), TRUE);
				break;
		}

		// Turn settings updates on again
		self->update_setting = TRUE;
	}
}

/**
 * trash_settings_new:
 * @settings: (transfer full): A #GSettings object
 *
 * Create a new #TrashSettings widget.
 *
 * Returns: a new #TrashSettings widget
 */
TrashSettings *trash_settings_new(GSettings *settings) {
	TrashSettings *self;

	self = g_object_new(TRASH_TYPE_SETTINGS, NULL);

	self->settings = g_object_ref(settings);

	settings_changed(self->settings, TRASH_SETTINGS_KEY_SORT_MODE, self);

	g_signal_connect(self->settings, "changed", G_CALLBACK(settings_changed), self);

	return self;
}
