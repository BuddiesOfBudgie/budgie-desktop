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

#include "popover-redux.h"

struct BudgiePopoverRedux {
    GtkWidget * relative_to;
};

G_DEFINE_TYPE(BudgiePopoverRedux, budgie_popover_redux, GTK_TYPE_POPOVER)

static void budgie_popover_redux_init(BudgiePopoverRedux * self){

}

static void budgie_popover_redux_class_init(BudgiePopoverReduxClass * c) {
	(void) c;
}

GtkWidget * budgie_popover_redux_new(GtkWidget * relative_to) {
    return g_object_new(BUDGIE_TYPE_POPOVER_REDUX, "relative-to", relative_to);
}
