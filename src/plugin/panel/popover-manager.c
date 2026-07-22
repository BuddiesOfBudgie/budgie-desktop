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

#include "applet.h"
#include "popover.h"
#include <stdio.h>
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
static gboolean on_focus_out(GtkWidget *widget, GdkEvent *event, GtkPopover *popover);
static void on_popover_closed_restore_keyboard_mode(GtkPopover *popover, GtkWindow *toplevel);
static gboolean on_toplevel_focus_in_grab_widget(GtkWidget *toplevel_widget, GdkEvent *event, GtkWidget *w);

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

	GtkWidget * toplevel = gtk_widget_get_toplevel(parent_widget);

	g_signal_connect(toplevel, "focus-out-event", G_CALLBACK(on_focus_out), popover);

	BudgiePanelPosition * position = NULL;
	g_object_get(G_OBJECT(toplevel), "position", &position, NULL);

	if (position == BUDGIE_PANEL_POSITION_TOP) {
		gtk_popover_set_position(popover, GTK_POS_BOTTOM);
	} else if (position == BUDGIE_PANEL_POSITION_BOTTOM) {
		gtk_popover_set_position(popover, GTK_POS_TOP);
	} else if (position == BUDGIE_PANEL_POSITION_LEFT) {
		gtk_popover_set_position(popover, GTK_POS_RIGHT);
	} else if (position == BUDGIE_PANEL_POSITION_RIGHT) {
		gtk_popover_set_position(popover, GTK_POS_LEFT);
	}

	// GtkPopover (GTK3) is a GtkBin, NOT a GtkWindow. It never gets its own Wayland
	// surface role (no xdg_popup, no layer-surface) -- it renders via a wl_subsurface
	// parented to its *toplevel*, and routes keyboard input through an in-process GTK
	// grab. That in-process grab only has real key events to redirect if the toplevel
	// itself already holds actual Wayland keyboard focus.
	//
	// Mouse-opened popovers work because clicking the panel gives the panel's own
	// zwlr_layer_surface_v1 keyboard focus (labwc honours the click), so the popover's
	// internal grab has input to intercept. Keyboard-shortcut-opened popovers (e.g.
	// Super to open the app menu) fail because the panel's layer-surface sits at
	// KEYBOARD_MODE_ON_DEMAND -- no click, no focus, nothing for the grab to redirect.
	//
	// The previous approach here tried to promote the *popover's own* GdkWindow to a
	// zwlr_layer_surface_v1 via gtk_layer_init_for_window(). That can never work:
	// GtkPopover isn't a GtkWindow, so gtk-layer-shell's "linked-gtk-window" data key
	// (only set on windows gtk-layer-shell already manages) is never present on a
	// popover's GdkWindow -- the lookup returns garbage/NULL and every subsequent
	// gtk_layer_* call is a no-op on nothing.
	//
	// The actual fix: toggle keyboard-interactivity on the PANEL's already-existing
	// layer-surface (which Budgie itself owns and already manages via GtkLayerShell)
	// to EXCLUSIVE right before popping the menu open, then grab focus into the
	// popover's own search entry so GTK's internal focus chain routes the now-real
	// keyboard events there. Revert to ON_DEMAND when the popover closes so we don't
	// trap the compositor keyboard globally. See: https://github.com/BuddiesOfBudgie/budgie-desktop/issues/842
	GtkWindow *toplevel_win = GTK_IS_WINDOW(toplevel) ? GTK_WINDOW(toplevel) : NULL;

	if (toplevel_win != NULL && gtk_layer_is_layer_window(toplevel_win)) {
		gtk_layer_set_keyboard_mode(toplevel_win, GTK_LAYER_SHELL_KEYBOARD_MODE_EXCLUSIVE);

		// Make sure we drop EXCLUSIVE again once the popover is dismissed, on every
		// exit path (Esc via on_focus_out's hide(), click-away, app launched, etc.)
		// -- all of them end up hiding the popover, so "hide" is the one signal that
		// reliably fires for all of them.
		g_signal_connect(popover, "hide", G_CALLBACK(on_popover_closed_restore_keyboard_mode), toplevel_win);

		// The EXCLUSIVE request above only takes effect on a LATER Wayland roundtrip
		// (labwc processes the layer-surface commit, then sends wl_keyboard.enter
		// asynchronously) -- it is NOT synchronous with this function call.
		if (gtk_window_has_toplevel_focus(toplevel_win)) {
			// Edge case: the panel already held real wl_keyboard focus (e.g. it was
			// just clicked moments before Super was pressed). Flipping to EXCLUSIVE
			// on an already-focused surface produces no NEW wl_keyboard.enter, so
			// waiting for focus-in-event would hang forever. Grab immediately.
			gtk_widget_grab_focus(w);
		} else {
			// Idempotent arm: guard against show->show without an intervening hide
			// stacking multiple handlers (e.g. rapid double Super-press).
			g_signal_handlers_disconnect_by_func(toplevel_win, G_CALLBACK(on_toplevel_focus_in_grab_widget), w);
			// Use _after + connect_object: GtkWindow's own default focus-in handler
			// (gtk_window_focus_in_event) re-establishes toplevel-focus bookkeeping
			// against its stored focus_widget when wl_keyboard.enter arrives. If our
			// handler ran BEFORE that default handler, our grab could be clobbered
			// by stale state. G_CONNECT_AFTER guarantees we run after GTK's own
			// bookkeeping settles. connect_object also auto-disconnects if `w` (the
			// widget we intend to focus) is destroyed while still armed, avoiding a
			// dangling callback into freed memory.
			g_signal_connect_object(toplevel_win, "focus-in-event", G_CALLBACK(on_toplevel_focus_in_grab_widget), w, G_CONNECT_AFTER);
		}
	} else {
		// No layer-surface to wait on (e.g. mouse-click path where the toplevel
		// already has focus) -- grab immediately as before.
		gtk_widget_grab_focus(w);
	}

	gtk_popover_popup(popover);

	// Ensures the default widget (input) is activated
	gtk_widget_set_can_default(w, TRUE);
	gtk_widget_grab_default(w);
}

static gboolean on_toplevel_focus_in_grab_widget(GtkWidget *toplevel_widget, GdkEvent *event, GtkWidget *w) {
	if (GTK_IS_WIDGET(w) && gtk_widget_get_visible(w)) {
		gtk_widget_grab_focus(w);
	}
	// One-shot: this signal fires every time the panel regains keyboard focus, but we
	// only need to redirect focus the first time after opening it. (g_signal_connect_object
	// ties this handler's lifetime to `w`, so no manual disconnect needed for cleanup,
	// but we still want to stop reacting after the first fire per open.)
	g_signal_handlers_disconnect_by_func(toplevel_widget, G_CALLBACK(on_toplevel_focus_in_grab_widget), w);
	return GDK_EVENT_PROPAGATE;
}

static void on_popover_closed_restore_keyboard_mode(GtkPopover *popover, GtkWindow *toplevel) {
	if (toplevel != NULL && GTK_IS_WINDOW(toplevel) && gtk_layer_is_layer_window(toplevel)) {
		gtk_layer_set_keyboard_mode(toplevel, GTK_LAYER_SHELL_KEYBOARD_MODE_ON_DEMAND);
	}
	g_signal_handlers_disconnect_by_func(popover, G_CALLBACK(on_popover_closed_restore_keyboard_mode), toplevel);
	// In case the popover was closed before focus-in ever fired (e.g. reopened/closed
	// quickly), make sure we don't leave a stale one-shot handler connected.
	g_signal_handlers_disconnect_by_func(toplevel, G_CALLBACK(on_toplevel_focus_in_grab_widget), popover);
}

static gboolean on_focus_out(GtkWidget *widget, GdkEvent *event, GtkPopover *popover) {
	g_return_val_if_fail(popover != NULL, GDK_EVENT_PROPAGATE);

	gtk_widget_hide(GTK_WIDGET(popover));
	return GDK_EVENT_PROPAGATE;
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