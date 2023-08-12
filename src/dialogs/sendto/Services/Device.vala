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

[DBus (name = "org.bluez.Device1")]
public interface Bluetooth.Device : Object {
	public abstract string[] UUIDs { owned get; }
	public abstract bool blocked { owned get; set; }
	public abstract bool connected { owned get; }
	public abstract bool legacy_pairing { owned get; }
	public abstract bool paired { owned get; }
	public abstract bool trusted { owned get; set; }
	public abstract int16 RSSI { owned get; }
	public abstract ObjectPath adapter { owned get; }
	public abstract string address { owned get; }
	public abstract string alias { owned get; set; }
	public abstract string icon { owned get; }
	public abstract string modalias { owned get; }
	public abstract string name { owned get; }
	public abstract uint16 appearance { owned get; }
	public abstract uint32 @class { owned get; }

	public abstract void cancel_pairing() throws Error;
	public abstract async void connect() throws Error;
	public abstract void connect_profile(string UUID) throws Error; //vala-lint=naming-convention
	public abstract async void disconnect() throws Error;
	public abstract void disconnect_profile(string UUID) throws Error; //vala-lint=naming-convention
	public abstract void pair() throws Error;
}
