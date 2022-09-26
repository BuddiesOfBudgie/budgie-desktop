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
	public abstract string Address { get; }
	public abstract string Name { get; }
	public abstract string Alias { get; set; }
	public abstract uint32 Class { get; }
	public abstract bool Powered { get; set; }
	public abstract string PoweredState { get; }
	public abstract bool Discoverable { set; get; }
	public abstract uint32 DiscoverableTimeout { get; set; }
	public abstract bool Pairable { get; set; }
	public abstract uint32 PairableTimeout { get; set; }
	public abstract bool Discovering { get; set; }
	public abstract string[] UUIDS { get; }
	public abstract string Modalias { get; }

	public async abstract void StartDiscovery() throws GLib.DBusError, GLib.IOError;
	public async abstract void StopDiscovery() throws GLib.DBusError, GLib.IOError;
	public async abstract void RemoveDevice(GLib.ObjectPath device) throws GLib.DBusError, GLib.IOError;
	public async abstract void SetDiscoveryFilter(HashTable<string, Variant> properties) throws GLib.DBusError, GLib.IOError;
}

/**
 * Definition of the Bluez Device1 interface.
 */
[DBus (name = "org.bluez.Device1")]
public interface Device1 : GLib.Object {
	public abstract string Address { get; }
	public abstract string Name { get; }
	public abstract string Alias { get; set; }
	public abstract uint32 Class { get; }
	public abstract uint16 Appearance { get; }
	public abstract string Icon { get; }
	public abstract bool Paired { get; }
	public abstract bool Trusted { get; set; }
	public abstract bool Blocked { get; set; }
	public abstract bool LegacyPairing { get; }
	public abstract int16 RSSI { get; }
	public abstract bool Connected { get; }
	public abstract string[] UUIDs { get; }
	public abstract string Modalias { get; }
	public abstract GLib.ObjectPath Adapter { get; }

	public async abstract void Connect() throws GLib.DBusError, GLib.IOError;
	public async abstract void Disconnect() throws GLib.DBusError, GLib.IOError;
	public async abstract void ConnectProfile(string uuid) throws GLib.DBusError, GLib.IOError;
	public async abstract void DisconnectProfile(string uuid) throws GLib.DBusError, GLib.IOError;
	public async abstract void Pair() throws GLib.DBusError, GLib.IOError;
	public async abstract void CancelPairing() throws GLib.DBusError, GLib.IOError;
}

/**
 * Definition of the Bluez AgentManager1 interface.
 */
[DBus (name = "org.bluez.AgentManager1")]
public interface AgentManager1 : GLib.Object {
	public async abstract void RegisterAgent(GLib.ObjectPath agent, string capability) throws GLib.DBusError, GLib.IOError;
	public async abstract void UnregisterAgent(GLib.ObjectPath agent) throws GLib.DBusError, GLib.IOError;
	public async abstract void RequestDefaultAgent(GLib.ObjectPath agent) throws GLib.DBusError, GLib.IOError;
}
