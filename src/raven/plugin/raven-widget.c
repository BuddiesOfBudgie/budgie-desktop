/*
 * This file is part of budgie-desktop
 *
 * Copyright © 2015-2022 Budgie Desktop Developers
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 */

#include "raven-widget.h"
#include "budgie-raven-enums.h"


G_DEFINE_TYPE_WITH_PRIVATE(BudgieRavenWidget, budgie_raven_widget, GTK_TYPE_BIN)


// static method header

static void budgie_raven_widget_init(BudgieRavenWidget* self);
static void budgie_raven_widget_class_init(BudgieRavenWidgetClass* klass);
static void budgie_raven_widget_dispose(GObject* g_object);


// public methods

BudgieRavenWidget* budgie_raven_widget_new() {
	return g_object_new(BUDGIE_TYPE_RAVEN_WIDGET, NULL);
}

void budgie_raven_widget_initialize(BudgieRavenWidget* self, const char* uuid, GSettings* instance_settings) {
	if (self->priv->initialized) {
		return;
	}

	self->priv->initialized = TRUE;
	self->priv->uuid = uuid;
	self->priv->instance_settings = instance_settings;
}

gboolean budgie_raven_widget_supports_settings(BudgieRavenWidget* self) {
	if (!BUDGIE_IS_RAVEN_WIDGET(self)) {
		return FALSE;
	}

	BudgieRavenWidgetClass* klass = BUDGIE_RAVEN_WIDGET_GET_CLASS(self);
	if (!klass->supports_settings) {
		return FALSE;
	}
	return klass->supports_settings(self);
}

GtkWidget* budgie_raven_widget_get_settings_ui(BudgieRavenWidget* self) {
	if (!BUDGIE_IS_RAVEN_WIDGET(self)) {
		return NULL;
	}

	BudgieRavenWidgetClass* klass = BUDGIE_RAVEN_WIDGET_GET_CLASS(self);
	if (!klass->supports_settings || klass->get_settings_ui == NULL) {
		return NULL;
	}
	return klass->get_settings_ui(self);
}

GSettings* budgie_raven_widget_get_settings(BudgieRavenWidget* self) {
	if (!BUDGIE_IS_RAVEN_WIDGET(self)) {
		return NULL;
	}

	if (!self || !self->priv || !self->priv->instance_settings) {
		return NULL;
	}

	return self->priv->instance_settings;
}


// static method definitions

static void budgie_raven_widget_init(BudgieRavenWidget* self) {
	self->priv->uuid = NULL;
	self->priv->instance_settings = NULL;
	self->priv->initialized = FALSE;
}

static void budgie_raven_widget_class_init(BudgieRavenWidgetClass* klass) {
	GObjectClass* g_object_class = G_OBJECT_CLASS(klass);
	g_object_class->dispose = budgie_raven_widget_dispose;
}

static void budgie_raven_widget_dispose(GObject* g_object) {
	BudgieRavenWidget* self = BUDGIE_RAVEN_WIDGET(g_object);

	g_clear_pointer(&self->priv->instance_settings, g_free);
	g_clear_pointer(&self->priv, g_free);

	G_OBJECT_CLASS(budgie_raven_widget_parent_class)->dispose(g_object);
}
