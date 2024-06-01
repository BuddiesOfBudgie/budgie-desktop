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

#include "popover-redux.h"
#define _GNU_SOURCE

#include "util.h"

BUDGIE_BEGIN_PEDANTIC
#include "popover-manager.h"
#include <gtk/gtk.h>
#include <gtk-layer-shell/gtk-layer-shell.h>
BUDGIE_END_PEDANTIC

struct _BudgiePopoverManagerPrivate {
	GHashTable* popovers;
	BudgiePopoverRedux* active_popover;
	gboolean grabbed;
};

G_DEFINE_TYPE_WITH_PRIVATE(BudgiePopoverManager, budgie_popover_manager, G_TYPE_OBJECT)

#if !GTK_CHECK_VERSION(3, 20, 0)
/*
 * Borrowed from brisk's popover-manager.c (in turn borrowed from) gdkseatdefault.c
 */
#define KEYBOARD_EVENTS (GDK_KEY_PRESS_MASK | GDK_KEY_RELEASE_MASK | GDK_FOCUS_CHANGE_MASK)
#define POINTER_EVENTS (GDK_POINTER_MOTION_MASK | GDK_BUTTON_PRESS_MASK | GDK_BUTTON_RELEASE_MASK | GDK_SCROLL_MASK |    \
						GDK_SMOOTH_SCROLL_MASK | GDK_ENTER_NOTIFY_MASK | GDK_LEAVE_NOTIFY_MASK | GDK_PROXIMITY_IN_MASK | \
						GDK_PROXIMITY_OUT_MASK)
#endif

static void budgie_popover_manager_link_signals(BudgiePopoverManager* manager, GtkWidget* parent_widget, BudgiePopoverRedux* popover);
static void budgie_popover_manager_unlink_signals(BudgiePopoverManager* manager, GtkWidget* parent_widget, BudgiePopoverRedux* popover);
static gboolean budgie_popover_manager_popover_mapped(BudgiePopoverRedux* popover, GdkEvent* event, BudgiePopoverManager* self);
static gboolean budgie_popover_manager_popover_unmapped(BudgiePopoverRedux* popover, GdkEvent* event, BudgiePopoverManager* self);
static void budgie_popover_manager_grab_notify(BudgiePopoverManager* self, gboolean was_grabbed, BudgiePopoverRedux* popover);
static gboolean budgie_popover_manager_grab_broken(BudgiePopoverManager* self, GdkEvent* event, BudgiePopoverRedux* popover);
static void budgie_popover_manager_grab(BudgiePopoverManager* self, BudgiePopoverRedux* popover);
static void budgie_popover_manager_ungrab(BudgiePopoverManager* self, BudgiePopoverRedux* popover);
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

/**
 * budgie_popover_manager_class_init:
 *
 * Handle class initialisation
 */
static void budgie_popover_manager_class_init(BudgiePopoverManagerClass* klazz) {
	GObjectClass* obj_class = G_OBJECT_CLASS(klazz);

	/* gobject vtable hookup */
	obj_class->dispose = budgie_popover_manager_dispose;
}

/**
 * budgie_popover_manager_init:
 *
 * Handle construction of the BudgiePopoverManager
 */
static void budgie_popover_manager_init(BudgiePopoverManager* self) {
	self->priv = budgie_popover_manager_get_instance_private(self);
	self->priv->grabbed = FALSE;

	/* We don't re-ref anything as we just effectively hold floating references
	 * to the WhateverTheyAres
	 */
	self->priv->popovers = g_hash_table_new_full(g_direct_hash, g_direct_equal, NULL, NULL);
}

void budgie_popover_manager_register_popover_v2(BudgiePopoverManager* self, GtkWidget* parent_widget, GtkPopover* popover) {
	g_assert(self != NULL);
	g_return_if_fail(parent_widget != NULL && popover != NULL);

	if (g_hash_table_contains(self->priv->popovers, parent_widget)) {
		g_warning("register_popover_v2(): Widget %p is already registered", (gpointer) parent_widget);
		return;
	}

	GdkWindow * win = gtk_widget_get_parent_window(popover);
	if (GDK_IS_WINDOW(win)) gtk_widget_add_events(popover, GDK_FOCUS_CHANGE_MASK);
	gtk_popover_set_constrain_to(popover, GTK_POPOVER_CONSTRAINT_NONE);
	gtk_popover_set_relative_to(popover, parent_widget);

	budgie_popover_manager_link_signals(self, parent_widget, popover);
	g_hash_table_insert(self->priv->popovers, parent_widget, popover);
}

/**
 * budgie_popover_manager_unregister_popover_v2:
 * @parent_widget: The associated widget (key) for the registered popover
 *
 * Unregister a popover so that it is no longer managed by this implementation,
 * and is free to manage itself.
 */
void budgie_popover_manager_unregister_popover(BudgiePopoverManager* self, GtkWidget* parent_widget) {
	g_assert(self != NULL);
	g_return_if_fail(parent_widget != NULL);
	BudgiePopoverRedux* popover = NULL;

	popover = g_hash_table_lookup(self->priv->popovers, parent_widget);
	if (!popover) {
		g_warning("unregister_popover_v2(): Widget %p is unknown", (gpointer) parent_widget);
		return;
	}

	budgie_popover_manager_unlink_signals(self, parent_widget, popover);
	g_hash_table_remove(self->priv->popovers, parent_widget);
}

/**
 * show_one_popover:
 *
 * Show a popover on the idle loop to prevent any weird event locks
 */
static gboolean show_one_popover(gpointer v) {
	if (gtk_grab_get_current()) {
		return FALSE;
	}

	gtk_widget_show(GTK_WIDGET(v));
	gtk_widget_set_can_default(GTK_WIDGET(v), TRUE);
	gtk_widget_grab_default(GTK_WIDGET(v));

	GdkWindow * gdk_window = gtk_widget_get_window(GTK_WIDGET(v));

	if (!GDK_IS_WINDOW(gdk_window)) return FALSE;

	// Thanks gtk-layer-shell for the following conversion code
	GtkWindow *popover_win = GTK_WINDOW (g_object_get_data (G_OBJECT (gdk_window), "linked-gtk-window"));
	if (!GTK_IS_WINDOW(popover_win)) return FALSE;

	gtk_layer_init_for_window(popover_win);
	gtk_layer_set_layer(popover_win, GTK_LAYER_SHELL_LAYER_TOP);
	gtk_layer_set_keyboard_mode(popover_win, GTK_LAYER_SHELL_KEYBOARD_MODE_ON_DEMAND);
	return FALSE;
}

/**
 * budgie_popover_manager_show_popover:
 * @parent_widget: The widget owning the popover to be shown
 *
 * Show a #BudgiePopover on screen belonging to the specified @parent_widget
 */
void budgie_popover_manager_show_popover(BudgiePopoverManager* self, GtkWidget* parent_widget) {
	BudgiePopoverRedux* popover = NULL;

	g_assert(self != NULL);
	g_return_if_fail(parent_widget != NULL);

	popover = g_hash_table_lookup(self->priv->popovers, parent_widget);
	if (!popover) {
		g_warning("show_popover(): Widget %p is unknown", (gpointer) parent_widget);
		return;
	}

	g_idle_add(show_one_popover, popover);
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

/**
 * budgie_popover_manager_link_signals:
 *
 * Hook up the various signals we need to manage this popover correctly
 */
static void budgie_popover_manager_link_signals(BudgiePopoverManager* self, GtkWidget* parent_widget, BudgiePopoverRedux* popover) {
	g_signal_connect_swapped(parent_widget, "destroy", G_CALLBACK(budgie_popover_manager_widget_died), self);

	/* Monitor map/unmap to manage the grab semantics */
	g_signal_connect(popover, "map-event", G_CALLBACK(budgie_popover_manager_popover_mapped), self);
	g_signal_connect(popover, "unmap-event", G_CALLBACK(budgie_popover_manager_popover_unmapped), self);

	/* Determine when a re-grab is needed */
	g_signal_connect_swapped(popover, "grab-notify", G_CALLBACK(budgie_popover_manager_grab_notify), self);
	g_signal_connect_swapped(popover, "grab-broken-event", G_CALLBACK(budgie_popover_manager_grab_broken), self);
	g_signal_connect_swapped(popover, "focus-out-event", G_CALLBACK(budgie_popover_manager_grab_broken), self);
}

/**
 * budgie_popover_manager_unlink_signals:
 *
 * Disconnect any prior signals for this popover so we stop receiving events for it
 */
static void budgie_popover_manager_unlink_signals(BudgiePopoverManager* self, GtkWidget* parent_widget, BudgiePopoverRedux* popover) {
	g_signal_handlers_disconnect_by_data(parent_widget, self);
	g_signal_handlers_disconnect_by_data(popover, self);
}

/**
 * budgie_popover_manager_popover_mapped:
 *
 * Handle the BudgiePopover becoming visible on screen, updating our knowledge
 * of who the currently active popover is
 */
static gboolean budgie_popover_manager_popover_mapped(BudgiePopoverRedux* popover, __budgie_unused__ GdkEvent* event, BudgiePopoverManager* self) {
	/* Someone might have forcibly opened a new popover with one active, so
	 * if we're already managing a popover, the only sane thing to do is
	 * to tell it to sod off and start managing the new one.
	 */
	if (self->priv->active_popover && self->priv->active_popover != popover) {
		budgie_popover_manager_ungrab(self, self->priv->active_popover);
		self->priv->active_popover = NULL;
		if (gtk_widget_get_visible(GTK_WIDGET(popover))) {
			gtk_widget_hide(GTK_WIDGET(popover));
		}
	}

	self->priv->active_popover = popover;

	/* Don't attempt to steal grabs */
	if (gtk_grab_get_current()) {
		gtk_widget_hide(GTK_WIDGET(popover));
		self->priv->active_popover = NULL;
		self->priv->grabbed = FALSE;
		return GDK_EVENT_PROPAGATE;
	}

	/* If we don't do this weird cycle then the rollover enter-notify
	 * event becomes broken, defeating the purpose of a manager.
	 */
	budgie_popover_manager_grab(self, popover);
	budgie_popover_manager_ungrab(self, popover);
	budgie_popover_manager_grab(self, popover);

	return GDK_EVENT_PROPAGATE;
}

/**
 * budgie_popover_manager_popover_unmapped:
 *
 * Handle the BudgiePopover becoming invisible on screen, updating our knowledge
 * of who the currently active popover is
 */
static gboolean budgie_popover_manager_popover_unmapped(BudgiePopoverRedux* popover, __budgie_unused__ GdkEvent* event, BudgiePopoverManager* self) {
	budgie_popover_manager_ungrab(self, popover);

	if (popover == self->priv->active_popover) {
		self->priv->active_popover = NULL;
	}

	return GDK_EVENT_PROPAGATE;
}

/**
 * budgie_popover_manager_grab:
 *
 * Grab the input events using the GdkSeat
 */
static void budgie_popover_manager_grab(BudgiePopoverManager* self, BudgiePopoverRedux* popover) {
	GdkDisplay* display = NULL;
	GdkWindow* window = NULL;
	GdkGrabStatus st;

	if (self->priv->grabbed || popover != self->priv->active_popover) {
		return;
	}

	window = gtk_widget_get_window(GTK_WIDGET(popover));

	if (!window) {
		g_warning("Attempting to grab BudgiePopover when not realized");
		return;
	}

	display = gtk_widget_get_display(GTK_WIDGET(popover));

	/* 3.20 and newer use GdkSeat API */
	GdkSeat* seat = NULL;
	GdkSeatCapabilities caps = GDK_SEAT_CAPABILITY_ALL;

	seat = gdk_display_get_default_seat(display);

	st = gdk_seat_grab(seat, window, caps, TRUE, NULL, NULL, NULL, NULL);
	if (st == GDK_GRAB_SUCCESS) {
		self->priv->grabbed = TRUE;
		gtk_grab_add(GTK_WIDGET(popover));
	}
}

/**
 * budgie_popover_manager_ungrab:
 *
 * Ungrab a previous grab by this widget
 */
static void budgie_popover_manager_ungrab(BudgiePopoverManager* self, BudgiePopoverRedux* popover) {
	GdkDisplay* display = NULL;

	if (popover == NULL || !self->priv->grabbed || popover != self->priv->active_popover) {
		return;
	}

	display = gtk_widget_get_display(GTK_WIDGET(popover));

	GdkSeat* seat = NULL;

	seat = gdk_display_get_default_seat(display);

	gtk_grab_remove(GTK_WIDGET(popover));
	gdk_seat_ungrab(seat);
	self->priv->grabbed = FALSE;
}

/**
 * budgie_popover_manager_grab_broken:
 *
 * Grab was broken, most likely due to a window within our application
 */
static gboolean budgie_popover_manager_grab_broken(BudgiePopoverManager* self, __budgie_unused__ GdkEvent* event, BudgiePopoverRedux* popover) {
	if (popover != self->priv->active_popover) {
		return GDK_EVENT_PROPAGATE;
	}

	GtkWidget * popover_widget = GTK_WIDGET(popover);
	if (GTK_IS_WIDGET(popover_widget)) gtk_widget_hide(popover_widget);

	self->priv->grabbed = FALSE;
	return GDK_EVENT_PROPAGATE;
}

/**
 * budgie_popover_manager_grab_notify:
 *
 * Grab changed _within_ the application
 *
 * If our grab was broken, i.e. due to some popup menu, and we're still visible,
 * we'll now try and grab focus once more.
 */
static void budgie_popover_manager_grab_notify(BudgiePopoverManager* self, gboolean was_grabbed, BudgiePopoverRedux* popover) {
	/* Only interested in unshadowed */
	if (!was_grabbed || popover != self->priv->active_popover) {
		return;
	}

	budgie_popover_manager_ungrab(self, popover);

	/* And being visible. ofc. */
	if (!gtk_widget_get_visible(GTK_WIDGET(popover))) {
		return;
	}

	/* Redo the whole grab cycle to restore proper enter-notify events */
	budgie_popover_manager_grab(self, popover);
	budgie_popover_manager_ungrab(self, popover);
	budgie_popover_manager_grab(self, popover);
}
