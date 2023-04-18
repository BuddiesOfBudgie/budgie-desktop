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

#pragma once

#include <gtk/gtk.h>

G_BEGIN_DECLS

#define TRASH_TYPE_BUTTON_BAR (trash_button_bar_get_type())

G_DECLARE_DERIVABLE_TYPE(TrashButtonBar, trash_button_bar, TRASH, BUTTON_BAR, GtkBox)

struct _TrashButtonBarClass {
	GtkBoxClass parent_class;

	/* Signals */

	void (*response)(TrashButtonBar *self, gint response_id);

	gpointer padding[12];
};

TrashButtonBar *trash_button_bar_new(void);

GtkWidget *trash_button_bar_add_button(TrashButtonBar *self, const gchar *text, gint response_id);

GtkWidget *trash_button_bar_get_content_area(TrashButtonBar *self);

gboolean trash_button_bar_get_revealed(TrashButtonBar *self);

void trash_button_bar_add_response_style_class(TrashButtonBar *self, gint response_id, const gchar *style);

void trash_button_bar_set_response_sensitive(TrashButtonBar *self, gint response_id, gboolean sensitive);

void trash_button_bar_set_revealed(TrashButtonBar *self, gboolean reveal);

G_END_DECLS
