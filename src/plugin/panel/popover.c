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


typedef struct {
	GtkPopover parent_instance;
} BudgiePopoverPrivate;

G_DEFINE_TYPE_WITH_PRIVATE(BudgiePopover, budgie_popover, GTK_TYPE_POPOVER)

static void budgie_popover_init(BudgiePopover* self) {

}

static void budgie_popover_dispose (GObject* object) {
	BudgiePopover *popover = budgie_popover_get_instance_private(T_BUDGIE_POPOVER (object));

	G_OBJECT_CLASS(budgie_popover_parent_class)->dispose(object);
}

static void budgie_popover_finalize (GObject* object) {
	BudgiePopover *popover = budgie_popover_get_instance_private(T_BUDGIE_POPOVER (object));

	G_OBJECT_CLASS(budgie_popover_parent_class)->finalize(object);
}

static void budgie_popover_class_init(BudgiePopoverClass* klass) {
	GtkWidgetClass* widget_class = GTK_WIDGET_CLASS(klass);
	GObjectClass* object_class = G_OBJECT_CLASS(klass);

	object_class->dispose = budgie_popover_dispose;
	object_class->finalize = budgie_popover_finalize;
}

BudgiePopover* budgie_popover_new(GtkWidget* relative_to) {
	BudgiePopover* popover = g_object_new(T_TYPE_BUDGIE_POPOVER, "relative-to", relative_to, NULL);
	GtkStyleContext* style = gtk_widget_get_style_context(popover);

	gtk_style_context_add_class(style, "budgie-popover");

	return popover;
}
