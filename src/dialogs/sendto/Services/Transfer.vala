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

[DBus (name = "org.bluez.obex.Transfer1")]
public interface Bluetooth.Obex.Transfer : Object {
	public abstract string status { owned get; }
    public abstract ObjectPath session { owned get; }
    public abstract string name { owned get; }
    public abstract string Type { owned get; }
    public abstract uint64 time { owned get; }
    public abstract uint64 size { owned get; }
    public abstract uint64 transferred { owned get; }
    public abstract string filename { owned get; }

    public abstract void cancel() throws GLib.Error;
    public abstract void resume() throws GLib.Error;
    public abstract void suspend() throws GLib.Error;
}
