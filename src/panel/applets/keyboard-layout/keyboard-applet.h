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

#pragma once

#include "applet.h"

G_BEGIN_DECLS

typedef struct _KeyboardAppletPrivate KeyboardAppletPrivate;
typedef struct _KeyboardApplet KeyboardApplet;
typedef struct _KeyboardAppletClass KeyboardAppletClass;

#define KEYBOARD_TYPE_APPLET (keyboard_applet_get_type())
#define KEYBOARD_APPLET(o) (G_TYPE_CHECK_INSTANCE_CAST((o), KEYBOARD_TYPE_APPLET, KeyboardApplet))
#define KEYBOARD_IS_APPLET(o) (G_TYPE_CHECK_INSTANCE_TYPE((o), KEYBOARD_TYPE_APPLET))
#define KEYBOARD_APPLET_CLASS(o) (G_TYPE_CHECK_CLASS_CAST((o), KEYBOARD_TYPE_APPLET, KeyboardAppletClass))
#define KEYBOARD_IS_APPLET_CLASS(o) (G_TYPE_CHECK_CLASS_TYPE((o), KEYBOARD_TYPE_APPLET))
#define KEYBOARD_APPLET_GET_CLASS(o) (G_TYPE_INSTANCE_GET_CLASS((o), KEYBOARD_TYPE_APPLET, KeyboardAppletClass))

struct _KeyboardAppletClass {
	BudgieAppletClass parent_class;
};

struct _KeyboardApplet {
	BudgieApplet parent;

	KeyboardAppletPrivate* priv;
};

GType keyboard_applet_get_type(void);

void keyboard_applet_init_gtype(GTypeModule* module);

KeyboardApplet* keyboard_applet_new(const gchar* uuid);

gchar* keyboard_applet_get_uuid(KeyboardApplet* self);

void keyboard_applet_set_uuid(KeyboardApplet* self, const gchar* uuid);

G_END_DECLS
