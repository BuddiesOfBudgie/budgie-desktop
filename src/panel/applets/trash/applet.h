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

#include "notify.h"
#include "trash_popover.h"
#include "trash_settings.h"
#include <budgie-desktop/applet.h>
#include <gtk/gtk.h>
#include <libnotify/notify.h>

#define __budgie_unused__ __attribute__((unused))

G_BEGIN_DECLS

typedef struct _TrashAppletPrivate TrashAppletPrivate;
typedef struct _TrashApplet TrashApplet;
typedef struct _TrashAppletClass TrashAppletClass;

#define TRASH_TYPE_APPLET (trash_applet_get_type())
#define TRASH_APPLET(o) (G_TYPE_CHECK_INSTANCE_CAST((o), TRASH_TYPE_APPLET, TrashApplet))
#define TRASH_IS_APPLET(o) (G_TYPE_CHECK_INSTANCE_TYPE((o), TRASH_TYPE_APPLET))
#define TRASH_APPLET_CLASS(o) (G_TYPE_CHECK_CLASS_CAST((o), TRASH_TYPE_APPLET, TrashAppletClass))
#define TRASH_IS_APPLET_CLASS(o) (G_TYPE_CHECK_CLASS_TYPE((o), TRASH_TYPE_APPLET))
#define TRASH_APPLET_GET_CLASS(o) (G_TYPE_INSTANCE_GET_CLASS((o), TRASH_TYPE_APPLET, TrashAppletClass))

struct _TrashAppletClass {
	BudgieAppletClass parent_class;
};

struct _TrashApplet {
	BudgieApplet parent;

	TrashAppletPrivate *priv;
	GSettings *settings;
};

GType trash_applet_get_type(void);

void trash_applet_init_gtype(GTypeModule *module);

TrashApplet *trash_applet_new(const gchar *uuid);

gchar *trash_applet_get_uuid(TrashApplet *self);

void trash_applet_set_uuid(TrashApplet *self, const gchar *value);

G_END_DECLS
