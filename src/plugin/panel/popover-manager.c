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

#include "popover.h"
#define _GNU_SOURCE

#include "util.h"

BUDGIE_BEGIN_PEDANTIC
#include "popover-manager.h"
#include <gtk/gtk.h>
#include <gtk-layer-shell/gtk-layer-shell.h>
BUDGIE_END_PEDANTIC

struct _BudgiePopoverManagerPrivate {
	GHashTable* popovers;
	gboolean grabbed;
};

G_DEFINE_TYPE_WITH_PRIVATE(BudgiePopoverManager, budgie_popover_manager, G_TYPE_OBJECT)

static void budgie_popover_manager_widget_died(BudgiePopoverManager* self, GtkWidget* child);

/**
 * budgie_popover_manager_new:

 * Construct a new BudgiePopoverManager object
 *
 * Return value: A pointer to a new #BudgiePopoverManager object.
 */
BudgiePopoverManager* budgie_popover_manager_new(void) {
	return g_object_new(BUDGIE_TYPE_POPOVER_MANAGER, NULL);
}

/**
 * budgie_popover_manager_dispose:
 *
 * Clean up a BudgiePopoverManager instance
 */
static void budgie_popover_manager_dispose(GObject* obj) {
	BudgiePopoverManager* self = NULL;

	self = BUDGIE_POPOVER_MANAGER(obj);
	g_clear_pointer(&self->priv->popovers, g_hash_table_unref);

	G_OBJECT_CLASS(budgie_popover_manager_parent_class)->dispose(obj);
}


static void budgie_popover_manager_class_init(BudgiePopoverManagerClass* c) {
	GObjectClass* obj_class = G_OBJECT_CLASS(c);

	obj_class->dispose = budgie_popover_manager_dispose;
}

static void budgie_popover_manager_init(BudgiePopoverManager* self) {
	self->priv = budgie_popover_manager_get_instance_private(self);
	self->priv->grabbed = FALSE;
	self->priv->popovers = g_hash_table_new_full(g_direct_hash, g_direct_equal, NULL, NULL);
}

void budgie_popover_manager_register_popover(BudgiePopoverManager* self, GtkWidget* parent_widget, GtkPopover* popover) {
	g_assert(self != NULL);
	g_return_if_fail(parent_widget != NULL && popover != NULL);

	if (g_hash_table_contains(self->priv->popovers, parent_widget)) {
		g_warning("register_popover(): Widget %p is already registered", (gpointer) parent_widget);
		return;
	}

	GdkWindow * win = gtk_widget_get_parent_window(popover);
	if (GDK_IS_WINDOW(win)) gtk_widget_add_events(popover, GDK_FOCUS_CHANGE_MASK);
	gtk_popover_set_constrain_to(popover, GTK_POPOVER_CONSTRAINT_NONE);
	gtk_popover_set_relative_to(popover, parent_widget);

	g_signal_connect_swapped(parent_widget, "destroy", G_CALLBACK(budgie_popover_manager_widget_died), self);
	g_hash_table_insert(self->priv->popovers, parent_widget, popover);
}

/**
 * budgie_popover_manager_show_popover:
 * @parent_widget: The widget owning the popover to be shown
 *
 * Show a #BudgiePopover on screen belonging to the specified @parent_widget
 */
void budgie_popover_manager_show_popover(BudgiePopoverManager* self, GtkWidget* parent_widget) {
	BudgiePopover* popover = NULL;

	g_assert(self != NULL);
	g_return_if_fail(parent_widget != NULL);

	popover = g_hash_table_lookup(self->priv->popovers, parent_widget);
	if (!GTK_IS_POPOVER(popover)) {
		g_warning("budgie_popover_manager_show_popover(): Widget %p is unknown", (gpointer) parent_widget);
		return;
	}

	GtkWidget* w = GTK_WIDGET(popover);

	gtk_popover_popup(popover);

	// Ensures the default widget (input) is activated
	gtk_widget_set_can_default(w, TRUE);
	gtk_widget_grab_default(w);

	GdkWindow * gdk_window = gtk_widget_get_window(w);

	if (!GDK_IS_WINDOW(gdk_window)) return;

	// Thanks gtk-layer-shell for the following conversion code for getting the GtkWindow from a GdkWaylandWindow
	GtkWindow *popover_win = GTK_WINDOW (g_object_get_data (G_OBJECT (gdk_window), "linked-gtk-window"));
	if (!GTK_IS_WINDOW(popover_win)) return;

	// Ensure gtk layer shell is initialised for the popover window, needs to be done after being realized
	gtk_layer_init_for_window(popover_win);

	gtk_layer_set_layer(popover_win, GTK_LAYER_SHELL_LAYER_TOP);
	gtk_layer_set_keyboard_mode(popover_win, GTK_LAYER_SHELL_KEYBOARD_MODE_ON_DEMAND);
}

/**
 * budgie_popover_manager_unregister_popover:
 * @parent_widget: The associated widget (key) for the registered popover
 *
 * Unregister a popover so that it is no longer managed by this implementation,
 * and is free to manage itself.
 */
void budgie_popover_manager_unregister_popover(BudgiePopoverManager* self, GtkWidget* parent_widget) {
	g_assert(self != NULL);
	g_return_if_fail(parent_widget != NULL);
	BudgiePopover* popover = NULL;

	popover = g_hash_table_lookup(self->priv->popovers, parent_widget);
	if (!popover) {
		g_warning("unregister_popover(): Widget %p is unknown", (gpointer) parent_widget);
		return;
	}

	g_signal_handlers_disconnect_by_data(parent_widget, self);
	g_signal_handlers_disconnect_by_data(popover, self);
	g_hash_table_remove(self->priv->popovers, parent_widget);
}

/**
 * budgie_popover_manager_widget_died:
 *
 * The widget has died, so remove it from our internal state
 */
static void budgie_popover_manager_widget_died(BudgiePopoverManager* self, GtkWidget* child) {
	if (!g_hash_table_contains(self->priv->popovers, child)) {
		return;
	}
	g_hash_table_remove(self->priv->popovers, child);
}