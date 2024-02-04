/*
 * This file is part of budgie-desktop
 *
 * Copyright Budgie Desktop Developers, elementary LLC
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

[DBus (name = "org.bluez.obex.Session1")]
public interface Bluetooth.Obex.Session : Object {
	public abstract string source { owned get; }
	public abstract string destination { owned get; }
	public abstract uchar channel { owned get; }
	public abstract string target { owned get; }
	public abstract string root { owned get; }

	public abstract string get_capabilities() throws GLib.Error;
}
