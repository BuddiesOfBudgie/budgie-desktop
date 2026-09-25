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

#include <glib-object.h>

G_BEGIN_DECLS

#define KEYBOARD_TYPE_INPUT_SOURCE (keyboard_input_source_get_type())

G_DECLARE_FINAL_TYPE(KeyboardInputSource, keyboard_input_source, KEYBOARD, INPUT_SOURCE, GObject)

KeyboardInputSource* keyboard_input_source_new(
	const gchar* id,
	guint index,
	const gchar* display_name,
	const gchar* layout,
	const gchar* variant);

const gchar* keyboard_input_source_get_id(KeyboardInputSource* self);

gboolean keyboard_input_source_has_display_name(KeyboardInputSource* self);

const gchar* keyboard_input_source_get_display_name(KeyboardInputSource* self);

gboolean keyboard_input_source_has_layout(KeyboardInputSource* self);

const gchar* keyboard_input_source_get_layout(KeyboardInputSource* self);

const gchar* keyboard_input_source_get_variant(KeyboardInputSource* self);

gint keyboard_input_source_compare(KeyboardInputSource* self, KeyboardInputSource* other, gpointer user_data);

gboolean keyboard_input_source_equal(KeyboardInputSource* self, KeyboardInputSource* other);

G_END_DECLS
