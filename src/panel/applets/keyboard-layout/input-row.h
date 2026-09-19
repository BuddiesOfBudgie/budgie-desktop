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

#include <gtk/gtk.h>

#include "input-source.h"

G_BEGIN_DECLS

#define KEYBOARD_TYPE_INPUT_ROW (keyboard_input_row_get_type())

G_DECLARE_FINAL_TYPE(KeyboardInputRow, keyboard_input_row, KEYBOARD, INPUT_ROW, GtkListBoxRow)

KeyboardInputRow* keyboard_input_row_new(KeyboardInputSource* source, gpointer user_data);

KeyboardInputSource* keyboard_input_row_get_source(KeyboardInputRow* self);

void keyboard_input_row_set_source(KeyboardInputRow* self, KeyboardInputSource* source);

G_END_DECLS
