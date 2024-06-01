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

//typedef struct _BudgiePopoverRedux BudgiePopoverRedux;
//typedef struct _BudgiePopoverReduxClass BudgiePopoverReduxClass;
//typedef struct _BudgiePopoverReduxPrivate BudgiePopoverReduxPrivate;

G_DECLARE_DERIVABLE_TYPE(BudgiePopoverRedux, budgie_popover_redux, BUDGIE, POPOVER_REDUX, GtkPopover)

struct _BudgiePopoverReduxClass {
	GtkPopoverClass parent_class;

	gpointer padding[4];
};

/* struct _BudgiePopoverRedux {
	GtkPopover parent;
	BudgiePopoverReduxPrivate* private;
}; */

#define BUDGIE_TYPE_POPOVER_REDUX (budgie_popover_redux_get_type())
//#define BUDGIE_POPOVER_REDUX(o) (G_TYPE_CHECK_INSTANCE_CAST((o), BUDGIE_TYPE_POPOVER_REDUX, BudgiePopoverRedux))
//#define BUDGIE_IS_POPOVER_REDUX(o) (G_TYPE_CHECK_INSTANCE_TYPE((o), BUDGIE_TYPE_POPOVER_REDUX))
//#define BUDGIE_POPOVER_REDUX_CLASS(o) (G_TYPE_CHECK_CLASS_CAST((o), BUDGIE_TYPE_POPOVER_REDUX, BudgiePopoverReduxClass))
//#define BUDGIE_IS_POPOVER_REDUX_CLASS(o) (G_TYPE_CHECK_CLASS_TYPE((o), BUDGIE_TYPE_POPOVER_REDUX))
//#define BUDGIE_POPOVER_REDUX_GET_CLASS(o) (G_TYPE_INSTANCE_GET_CLASS((o), BUDGIE_TYPE_POPOVER_REDUX, BudgiePopoverReduxClass))

GtkWidget* budgie_popover_redux_new(GtkWidget* relative_to);

//GType budgie_popover_redux_get_type(void);

G_END_DECLS
