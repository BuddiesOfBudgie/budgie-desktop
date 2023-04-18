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

#include <libnotify/notification.h>

G_BEGIN_DECLS

void trash_notify_try_send(gchar *summary, gchar *body, gchar *icon_name);

G_END_DECLS
