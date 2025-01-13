/*
 * This file is part of budgie-desktop.
 *
 * Copyright Budgie Desktop Developers
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * based on the template described in https://docs.gtk.org/gobject/tutorial.html
 */

#pragma once

#include <glib-object.h>
#include <gtk/gtk.h>

G_BEGIN_DECLS

#define T_TYPE_BUDGIE_POPOVER (budgie_popover_get_type ())
G_DECLARE_DERIVABLE_TYPE (BudgiePopover, budgie_popover, T, BUDGIE_POPOVER, GtkPopover)

struct _BudgiePopoverClass {
	GtkPopoverClass parent_class;

	gpointer padding[12];
};

BudgiePopover* budgie_popover_new(GtkWidget* relative_to);

G_END_DECLS
