/*
 * This file is part of budgie-desktop
 *
 * Copyright © 2015-2022 Budgie Desktop Developers
 * Copyright (C) 2015 Alberts Muktupāvels
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

/**
 * Definition for Bluez Adapter1 interface.
 */
[DBus (name="org.bluez.Adapter1")]
public interface Adapter1 : GLib.Object {
	public abstract string address { owned get; }
	public abstract string name { owned get; }
	public abstract string alias { owned get; set; }
	public abstract uint32 @class { get; }
	public abstract bool powered { get; set; }
	public abstract string powered_state { owned get; }
	public abstract bool discoverable { set; get; }
	public abstract uint32 discoverable_timeout { get; set; }
	public abstract bool pairable { get; set; }
	public abstract uint32 pairable_timeout { get; set; }
	public abstract bool discovering { get; set; }
	public abstract string[] UUIDS { owned get; }
	public abstract string modalias { owned get; }

	public async abstract void start_discovery() throws GLib.DBusError, GLib.IOError;
	public async abstract void stop_discovery() throws GLib.DBusError, GLib.IOError;
	public async abstract void remove_device(GLib.ObjectPath device) throws GLib.DBusError, GLib.IOError;
	public async abstract void set_discovery_filter(HashTable<string, Variant> properties) throws GLib.DBusError, GLib.IOError;
}

/**
 * Definition of the Bluez Device1 interface.
 */
[DBus (name = "org.bluez.Device1")]
public interface Device1 : GLib.Object {
	public abstract string address { owned get; }
	public abstract string name { owned get; }
	public abstract string alias { owned get; set; }
	public abstract uint32 @class { owned get; }
	public abstract uint16 appearance { owned get; }
	public abstract string icon { owned get; }
	public abstract bool paired { owned get; }
	public abstract bool trusted { owned get; set; }
	public abstract bool blocked { owned get; set; }
	public abstract bool legacy_pairing { owned get; }
	public abstract int16 RSSI { owned get; }
	public abstract bool connected { owned get; }
	public abstract string[] UUIDs { owned get; }
	public abstract string modalias { owned get; }
	public abstract GLib.ObjectPath adapter { owned get; }

	public async abstract void connect() throws GLib.DBusError, GLib.IOError;
	public async abstract void disconnect() throws GLib.DBusError, GLib.IOError;
	public async abstract void connect_profile(string uuid) throws GLib.DBusError, GLib.IOError;
	public async abstract void disconnect_profile(string uuid) throws GLib.DBusError, GLib.IOError;
	public async abstract void pair() throws GLib.DBusError, GLib.IOError;
	public async abstract void cancel_pairing() throws GLib.DBusError, GLib.IOError;
}
