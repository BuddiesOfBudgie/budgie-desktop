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

#include "trash_plugin.h"

#define _GNU_SOURCE

static void trash_plugin_iface_init(BudgiePluginIface *iface);

G_DEFINE_DYNAMIC_TYPE_EXTENDED(TrashPlugin, trash_plugin, G_TYPE_OBJECT, 0,
	G_IMPLEMENT_INTERFACE_DYNAMIC(BUDGIE_TYPE_PLUGIN,
		trash_plugin_iface_init))

/**
 * Return a new panel widget.
 */
static BudgieApplet *trash_applet_get_panel_widget(__budgie_unused__ BudgiePlugin *base,
	gchar *uuid) {
	TrashApplet *self = trash_applet_new(uuid);
	return BUDGIE_APPLET(g_object_ref_sink(self));
}

/**
 * Handle cleanup.
 */
static void trash_plugin_dispose(GObject *object) {
	G_OBJECT_CLASS(trash_plugin_parent_class)->dispose(object);
}

/**
 * Class initialisation.
 */
static void trash_plugin_class_init(TrashPluginClass *klazz) {
	GObjectClass *obj_class = G_OBJECT_CLASS(klazz);

	// gobject vtable hookup
	obj_class->dispose = trash_plugin_dispose;
}

/**
 * Implement the BudgiePlugin interface, i.e the factory method get_panel_widget.
 */
static void trash_plugin_iface_init(BudgiePluginIface *iface) {
	iface->get_panel_widget = trash_applet_get_panel_widget;
}

/**
 * No-op, just skips compiler errors.
 */
static void trash_plugin_init(__budgie_unused__ TrashPlugin *self) {
}

/**
 * We have no cleaning ourselves to do.
 */
static void trash_plugin_class_finalize(__budgie_unused__ TrashPluginClass *klazz) {
}

/**
 * Export the types to the GObject type system.
 */
G_MODULE_EXPORT void peas_register_types(PeasObjectModule *module) {
	trash_plugin_register_type(G_TYPE_MODULE(module));

	// Register the actual dynamic types contained in the resulting plugin
	trash_applet_init_gtype(G_TYPE_MODULE(module));

	peas_object_module_register_extension_type(module, BUDGIE_TYPE_PLUGIN, TRASH_TYPE_PLUGIN);
}
