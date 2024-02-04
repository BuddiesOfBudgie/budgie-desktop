/*
 * This file is part of budgie-desktop
 *
 * Copyright Budgie Desktop Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * Inspired by gnome-bluetooth.
 */

/**
 * The type of battery reporting supported by the device.
 */
public enum BatteryType {
	/** No battery reporting. */
	NONE,
	/** Battery level reported in percentage. */
	PERCENTAGE,
	/** Battery level reported coarsely. */
	COARSE
}

/**
 * The type of a Bluetooth device.
 */
[Flags]
public enum BluetoothType {
	ANY = 1 << 0,
	PHONE = 1 << 1,
	MODEM = 1 << 2,
	COMPUTER = 1 << 3,
	NETWORK = 1 << 4,
	HEADSET = 1 << 5,
	HEADPHONES = 1 << 6,
	OTHER_AUDIO = 1 << 7,
	KEYBOARD = 1 << 8,
	MOUSE = 1 << 9,
	CAMERA = 1 << 10,
	PRINTER = 1 << 11,
	JOYPAD = 1 << 12,
	TABLET = 1 << 13,
	VIDEO = 1 << 14,
	REMOTE_CONTROL = 1 << 15,
	SCANNER = 1 << 16,
	DISPLAY = 1 << 17,
	WEARABLE = 1 << 18,
	TOY = 1 << 19,
	SPEAKERS = 1 << 20
}

/**
 * A more precise power state for a Bluetooth adapter.
 */
public enum PowerState {
	/** Bluetooth adapter is missing. */
	ABSENT = 0,
	/** Bluetooth adapter is on. */
	ON,
	/** Bluetooth adapter is being turned on. */
	TURNING_ON,
	/** Bluetooth adapter is being turned off. */
	TURNING_OFF,
	/** Bluetooth adapter is off. */
	OFF;

	/**
	 * Try to match a string to a PowerState.
	 *
	 * If no match is found, returns PowerState.ABSENT.
	 */
	public static PowerState from_string(string state) {
		switch (state) {
			case "on": return ON;
			case "off-enabling": return TURNING_ON;
			case "on-disabling": return TURNING_OFF;
			case "off":
			case "off-blocked": return OFF;
			default: return ABSENT;
		}
	}
}
