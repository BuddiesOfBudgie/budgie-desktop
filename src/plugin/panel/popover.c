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

#include "popover.h"

struct BudgiePopover {
    GtkWidget * relative_to;
};

G_DEFINE_TYPE(BudgiePopover, budgie_popover, GTK_TYPE_POPOVER)

static void budgie_popover_init(BudgiePopover * self){

}

static void budgie_popover_class_init(BudgiePopoverClass * c) {
	(void) c;
}

GtkWidget * budgie_popover_new(GtkWidget * relative_to) {
    GtkWidget * popover = g_object_new(BUDGIE_TYPE_POPOVER, "relative-to", relative_to);
    GtkStyleContext * style = gtk_widget_get_style_context(popover);
    gtk_style_context_add_class(style, "budgie-popover");

    return popover;
}
