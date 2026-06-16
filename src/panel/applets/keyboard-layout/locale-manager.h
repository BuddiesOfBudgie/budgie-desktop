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

#include <gio/gio.h>
#include <glib-object.h>

#include "input-source.h"
#include "org.freedesktop.locale1.h"

G_BEGIN_DECLS

#define KEYBOARD_TYPE_LOCALE_MANAGER (keyboard_locale_manager_get_type())

G_DECLARE_FINAL_TYPE(KeyboardLocaleManager, keyboard_locale_manager, KEYBOARD, LOCALE_MANAGER, GObject)

KeyboardLocaleManager* keyboard_locale_manager_new(void);

void keyboard_locale_manager_start(KeyboardLocaleManager* self);

KeyboardInputSource* keyboard_locale_manager_get_current_input_source(KeyboardLocaleManager* self);

void keyboard_locale_manager_set_current_input_source(KeyboardLocaleManager* self, KeyboardInputSource* source);

GListStore* keyboard_locale_manager_get_model(KeyboardLocaleManager* self);

KeyboardLocale1Proxy* keyboard_locale_manager_get_proxy(KeyboardLocaleManager* self);

G_END_DECLS
