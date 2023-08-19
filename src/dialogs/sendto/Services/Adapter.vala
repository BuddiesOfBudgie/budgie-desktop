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

[DBus (name = "org.bluez.Adapter1")]
public interface Bluetooth.Adapter : Object {
	public abstract string[] UUIDs { owned get; }
    public abstract bool discoverable { get; set; }
    public abstract bool discovering { get; }
    public abstract bool pairable { get; set; }
    public abstract bool powered { get; set; }
    public abstract string address { owned get; }
    public abstract string alias { owned get; set; }
    public abstract string modalias { owned get; }
    public abstract string name { owned get; }
    public abstract uint @class { get; }
    public abstract uint discoverable_timeout { get; }
    public abstract uint pairable_timeout { get; }

    public abstract void remove_device(ObjectPath device) throws Error;
    public abstract void set_discovery_filter(HashTable<string, Variant> properties) throws Error;
    public abstract async void start_discovery() throws Error;
    public abstract async void stop_discovery() throws Error;
}
