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

using GLib;
using Up;

/**
 * Wrapper for a Bluetooth device.
 */
public class BluetoothDevice : Object {
	public DBusProxy proxy { get; set; default = null; }
	public string address { get; set; }
	public string alias { get; set; }
	public string name { get; set; }
	public BluetoothType type { get; set; default = BluetoothType.ANY; }
	public string icon { get; set; }
	public bool paired { get; set; default = false; }
	public bool trusted { get; set; default = false; }
	public bool connected { get; set; default = false; }
	public bool legacy_pairing { get; set; default = false; }
	public string[] uuids { get; set; }
	public bool connectable { get; set; default = false; }
	public BatteryType battery_type { get; set; default = BatteryType.NONE; }
	[IntegerType (min = 0, max = 100)]
	public double battery_percentage { get; set; default = 0.0; }
	public DeviceLevel battery_level { get; set; default = DeviceLevel.UNKNOWN; }

	/**
	 * Create a new Bluetooth device wrapper object.
	 */
	public BluetoothDevice(Device1 device, BluetoothType type, string icon) {
		Object(
			proxy: device as DBusProxy,
			address: device.Address,
			alias: device.Alias,
			name: device.Name,
			type: type,
			icon: icon,
			legacy_pairing: device.LegacyPairing,
			uuids: device.UUIDs,
			paired: device.Paired,
			connected: device.Connected,
			trusted: device.Trusted
		);
	}

	/**
	 * Gets the object path for this Bluetooth device.
	 */
	public string? get_object_path() {
		if (proxy == null) {
			return null;
		}

		return proxy.get_object_path();
	}

	/**
	 * Get the associated UPower device for this Bluetooth device.
	 */
	public Device get_upower_device() {
		return get_data<Device>("up-device");
	}

	/**
	 * Set an association between this Bluetooth device and a UPower device.
	 */
	public void set_upower_device(Device? up_device) {
		set_data_full("up-device", up_device != null ? up_device.ref() : null, unref);
	}

	/**
	 * Updates battery levels from a UPower device.
	 */
	public void update_battery(Device up_device) {
		BatteryType type;

		if (up_device.battery_level == DeviceLevel.NONE) {
			type = BatteryType.PERCENTAGE;
		} else {
			type = BatteryType.COARSE;
		}

		battery_type = type;
		battery_level = up_device.battery_level as DeviceLevel;
		battery_percentage = up_device.percentage;
	}
}
