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

#include "input-source.h"
#include "popover.h"


G_BEGIN_DECLS

#define KEYBOARD_TYPE_POPOVER (keyboard_popover_get_type())

G_DECLARE_FINAL_TYPE(KeyboardPopover, keyboard_popover, KEYBOARD, POPOVER, BudgiePopover)

KeyboardPopover* keyboard_popover_new(GtkWidget* relative_to, GListStore* model);

void keyboard_popover_set_current_source(KeyboardPopover* self, KeyboardInputSource* current_source);

G_END_DECLS
