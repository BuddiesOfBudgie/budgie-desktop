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

KeyboardInputSource* keyboard_input_source_new(gchar* id, guint index, gboolean is_xkb);

KeyboardInputSource* keyboard_input_source_new_full(
	gchar* id,
	guint index,
	gchar* display_name,
	gchar* short_name,
	gchar* layout,
	gchar* variant,
	gchar* options,
	gboolean is_xkb);

gchar* keyboard_input_source_get_id(KeyboardInputSource* self);

void keyboard_input_source_set_id(KeyboardInputSource* self, gchar* id);

guint keyboard_input_source_get_index(KeyboardInputSource* self);

void keyboard_input_source_set_index(KeyboardInputSource* self, guint index);

gboolean keyboard_input_source_is_xkb(KeyboardInputSource* self);

void keyboard_input_source_set_xkb(KeyboardInputSource* self, gboolean xkb);

gboolean keyboard_input_source_has_display_name(KeyboardInputSource* self);

gchar* keyboard_input_source_get_display_name(KeyboardInputSource* self);

void keyboard_input_source_set_display_name(KeyboardInputSource* self, gchar* display_name);

gboolean keyboard_input_source_has_short_name(KeyboardInputSource* self);

gchar* keyboard_input_source_get_short_name(KeyboardInputSource* self);

void keyboard_input_source_set_short_name(KeyboardInputSource* self, gchar* short_name);

gboolean keyboard_input_source_has_layout(KeyboardInputSource* self);

gchar* keyboard_input_source_get_layout(KeyboardInputSource* self);

void keyboard_input_source_set_layout(KeyboardInputSource* self, gchar* layout);

gboolean keyboard_input_source_has_variant(KeyboardInputSource* self);

gchar* keyboard_input_source_get_variant(KeyboardInputSource* self);

void keyboard_input_source_set_variant(KeyboardInputSource* self, gchar* variant);

gboolean keyboard_input_source_has_options(KeyboardInputSource* self);

gchar* keyboard_input_source_get_options(KeyboardInputSource* self);

void keyboard_input_source_set_options(KeyboardInputSource* self, gchar* options);

gint keyboard_input_source_compare(KeyboardInputSource* self, KeyboardInputSource* other, gpointer user_data);

gboolean keyboard_input_source_equal(KeyboardInputSource* self, KeyboardInputSource* other);

G_END_DECLS
