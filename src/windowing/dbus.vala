/*
 * This file is part of budgie-desktop
 *
 * Copyright Budgie Desktop Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

namespace Budgie.Windowing {
	[DBus (name="org.buddiesofbudgie.budgie.Dispatcher")]
	public interface NotificationDispatcher : GLib.Object {
		public abstract bool notifications_paused { get; set; default = false; }
	}
}
