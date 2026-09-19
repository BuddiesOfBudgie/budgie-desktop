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

KeyboardInputSource* keyboard_input_source_new(const gchar* id, guint index, gboolean is_xkb);

KeyboardInputSource* keyboard_input_source_new_full(
	const gchar* id,
	guint index,
	const gchar* display_name,
	const gchar* short_name,
	const gchar* layout,
	const gchar* variant,
	const gchar* options,
	gboolean is_xkb);

gchar* keyboard_input_source_get_id(KeyboardInputSource* self);

void keyboard_input_source_set_id(KeyboardInputSource* self, const gchar* id);

guint keyboard_input_source_get_index(KeyboardInputSource* self);

void keyboard_input_source_set_index(KeyboardInputSource* self, guint index);

gboolean keyboard_input_source_is_xkb(KeyboardInputSource* self);

void keyboard_input_source_set_xkb(KeyboardInputSource* self, gboolean xkb);

gboolean keyboard_input_source_has_display_name(KeyboardInputSource* self);

gchar* keyboard_input_source_get_display_name(KeyboardInputSource* self);

void keyboard_input_source_set_display_name(KeyboardInputSource* self, const gchar* display_name);

gboolean keyboard_input_source_has_short_name(KeyboardInputSource* self);

gchar* keyboard_input_source_get_short_name(KeyboardInputSource* self);

void keyboard_input_source_set_short_name(KeyboardInputSource* self, const gchar* short_name);

gboolean keyboard_input_source_has_layout(KeyboardInputSource* self);

gchar* keyboard_input_source_get_layout(KeyboardInputSource* self);

void keyboard_input_source_set_layout(KeyboardInputSource* self, const gchar* layout);

gboolean keyboard_input_source_has_variant(KeyboardInputSource* self);

gchar* keyboard_input_source_get_variant(KeyboardInputSource* self);

void keyboard_input_source_set_variant(KeyboardInputSource* self, const gchar* variant);

gboolean keyboard_input_source_has_options(KeyboardInputSource* self);

gchar* keyboard_input_source_get_options(KeyboardInputSource* self);

void keyboard_input_source_set_options(KeyboardInputSource* self, const gchar* options);

gint keyboard_input_source_compare(KeyboardInputSource* self, KeyboardInputSource* other, gpointer user_data);

gboolean keyboard_input_source_equal(KeyboardInputSource* self, KeyboardInputSource* other);

G_END_DECLS
