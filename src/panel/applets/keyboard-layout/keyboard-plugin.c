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

#include "keyboard-plugin.h"
#include "keyboard-applet.h"

#define _GNU_SOURCE

static void keyboard_plugin_iface_init(BudgiePluginIface* iface);

G_DEFINE_DYNAMIC_TYPE_EXTENDED(KeyboardPlugin, keyboard_plugin, G_TYPE_OBJECT, 0,
	G_IMPLEMENT_INTERFACE_DYNAMIC(
		BUDGIE_TYPE_PLUGIN, keyboard_plugin_iface_init))

static BudgieApplet* keyboard_applet_get_panel_widget(BudgiePlugin* base, gchar* uuid) {
	KeyboardApplet* applet = keyboard_applet_new(uuid);
	return BUDGIE_APPLET(g_object_ref_sink(applet));
}

/******************************************************************************
 * GObject
 *****************************************************************************/

static void keyboard_plugin_dispose(GObject* object) {
	G_OBJECT_CLASS(keyboard_plugin_parent_class)->dispose(object);
}

static void keyboard_plugin_class_init(KeyboardPluginClass* klass) {
	GObjectClass* obj_class = G_OBJECT_CLASS(klass);

	obj_class->dispose = keyboard_plugin_dispose;
}

static void keyboard_plugin_iface_init(BudgiePluginIface* iface) {
	iface->get_panel_widget = keyboard_applet_get_panel_widget;
}

static void keyboard_plugin_init(KeyboardPlugin* self) {
	(void) self;
}

static void keyboard_plugin_class_finalize(KeyboardPluginClass* klass) {
	(void) klass;
}

G_MODULE_EXPORT void peas_register_types(PeasObjectModule* module) {
	keyboard_plugin_register_type(G_TYPE_MODULE(module));
	keyboard_applet_init_gtype(G_TYPE_MODULE(module));
	peas_object_module_register_extension_type(module, BUDGIE_TYPE_PLUGIN, KEYBOARD_TYPE_PLUGIN);
}
