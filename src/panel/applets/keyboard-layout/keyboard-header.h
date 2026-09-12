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

G_BEGIN_DECLS

#define KEYBOARD_TYPE_HEADER (keyboard_header_get_type())

G_DECLARE_FINAL_TYPE(KeyboardHeader, keyboard_header, KEYBOARD, HEADER, GtkBox)

KeyboardHeader* keyboard_header_new(void);

G_END_DECLS
