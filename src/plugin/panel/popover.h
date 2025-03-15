/*
 * This file is part of budgie-desktop.
 *
 * Copyright Budgie Desktop Developers
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 */

#pragma once

#include <glib-object.h>
#include <gtk/gtk.h>

G_BEGIN_DECLS

G_DECLARE_DERIVABLE_TYPE(BudgiePopover, budgie_popover, BUDGIE, POPOVER, GtkPopover)

struct _BudgiePopoverClass {
	GtkPopoverClass parent_class;

	gpointer padding[4];
};

#define BUDGIE_TYPE_POPOVER (budgie_popover_get_type())

GtkWidget* budgie_popover_new(GtkWidget* relative_to);

G_END_DECLS
