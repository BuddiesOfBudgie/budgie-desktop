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

#include "trash_enum_types.h"
#include "trash_settings.h"

#define C_ENUM(v) ((gint) v)
#define C_FLAGS(v) ((guint) v)

/* enumerations from "trash_settings.h" */

GType trash_sort_mode_get_type(void) {
	static gsize gtype_id = 0;
	static const GEnumValue values[] = {
		{C_ENUM(TRASH_SORT_TYPE), "TRASH_SORT_TYPE", "type"},
		{C_ENUM(TRASH_SORT_A_Z), "TRASH_SORT_A_Z", "a-z"},
		{C_ENUM(TRASH_SORT_Z_A), "TRASH_SORT_Z_A", "z-a"},
		{C_ENUM(TRASH_SORT_DATE_ASCENDING), "TRASH_SORT_DATE_ASCENDING", "date-ascending"},
		{C_ENUM(TRASH_SORT_DATE_DESCENDING), "TRASH_SORT_DATE_DESCENDING", "date-descending"},
		{0, NULL, NULL}};

	if (g_once_init_enter(&gtype_id)) {
		GType new_type = g_enum_register_static(g_intern_static_string("TrashSortMode"), values);
		g_once_init_leave(&gtype_id, new_type);
	}

	return (GType) gtype_id;
}
