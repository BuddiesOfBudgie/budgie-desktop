/*
 * This file is part of budgie-desktop.
 *
 * Copyright © 2015-2022 Budgie Desktop Developers
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

typedef struct _BudgieRavenWidgetPrivate BudgieRavenWidgetPrivate;
typedef struct _BudgieRavenWidget BudgieRavenWidget;
typedef struct _BudgieRavenWidgetClass BudgieRavenWidgetClass;

#define BUDGIE_TYPE_RAVEN_WIDGET budgie_raven_widget_get_type()
#define BUDGIE_RAVEN_WIDGET(o) (G_TYPE_CHECK_INSTANCE_CAST((o), BUDGIE_TYPE_RAVEN_WIDGET, BudgieRavenWidget))
#define BUDGIE_IS_RAVEN_WIDGET(o) (G_TYPE_CHECK_INSTANCE_TYPE((o), BUDGIE_TYPE_RAVEN_WIDGET))
#define BUDGIE_RAVEN_WIDGET_CLASS(o) (G_TYPE_CHECK_CLASS_CAST((o), BUDGIE_TYPE_RAVEN_WIDGET, BudgieRavenWidgetClass))
#define BUDGIE_IS_RAVEN_WIDGET_CLASS(o) (G_TYPE_CHECK_CLASS_TYPE((o), BUDGIE_TYPE_RAVEN_WIDGET))
#define BUDGIE_RAVEN_WIDGET_GET_CLASS(o) (G_TYPE_INSTANCE_GET_CLASS((o), BUDGIE_TYPE_RAVEN_WIDGET, BudgieRavenWidgetClass))

struct _BudgieRavenWidgetClass {
	GtkBinClass parent_class;

	GtkWidget* (*build_settings_ui)(BudgieRavenWidget* self);
};

struct _BudgieRavenWidgetPrivate {
	gboolean initialized;
	const char* uuid;
	GSettings* instance_settings;
};

struct _BudgieRavenWidget {
	GtkBin parent_instance;
	BudgieRavenWidgetPrivate* priv;
};

BudgieRavenWidget* budgie_raven_widget_new(void);

// should be implemented by subclasses
GtkWidget* budgie_raven_widget_build_settings_ui(BudgieRavenWidget* self);

// cannot be implemented by subclasses
void budgie_raven_widget_initialize(BudgieRavenWidget* self, const char* uuid, GSettings* instance_settings);
gchar* budgie_raven_widget_get_uuid(BudgieRavenWidget* self);
GSettings* budgie_raven_widget_get_instance_settings(BudgieRavenWidget* self);

GType budgie_raven_widget_get_type(void);

G_END_DECLS
