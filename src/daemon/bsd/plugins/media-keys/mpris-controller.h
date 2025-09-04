/*
 * Copyright © 2013 Intel Corporation.
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms and conditions of the GNU Lesser General Public License,
 * version 2.1, as published by the Free Software Foundation.
 *
 * This program is distributed in the hope it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, see <http://www.gnu.org/licenses>
 *
 * Author: Michael Wood <michael.g.wood@intel.com>
 */

#ifndef __MPRIS_CONTROLLER_H__
#define __MPRIS_CONTROLLER_H__

#include <glib-object.h>

G_BEGIN_DECLS

#define MPRIS_TYPE_CONTROLLER mpris_controller_get_type()

G_DECLARE_FINAL_TYPE (MprisController, mpris_controller, MPRIS, CONTROLLER, GObject)

MprisController *mpris_controller_new (void);
gboolean         mpris_controller_key (MprisController *self, const gchar *key);
gboolean         mpris_controller_seek (MprisController *self, gint64 offset);
gboolean         mpris_controller_toggle (MprisController *self, const gchar *property);
gboolean         mpris_controller_get_has_active_player (MprisController *controller);

G_END_DECLS

#endif /* __MPRIS_CONTROLLER_H__ */
