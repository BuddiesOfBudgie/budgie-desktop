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
 *
 * Inspired by gnome-bluetooth and Elementary.
 */

using GLib;
using Up;

const string BLUEZ_DBUS_NAME = "org.bluez";
const string BLUEZ_MANAGER_PATH = "/";
const string BLUEZ_ADAPTER_INTERFACE = "org.bluez.Adapter1";
const string BLUEZ_DEVICE_INTERFACE = "org.bluez.Device1";
const string BLUETOOTH_ADDRESS_PREFIX = "/org/bluez/";
const string RFKILL_DBUS_NAME = "org.gnome.SettingsDaemon.Rfkill";
const string RFKILL_DBUS_PATH = "/org/gnome/SettingsDaemon/Rfkill";

class BluetoothClient : GLib.Object {
	private Cancellable cancellable;

	private DBusObjectManagerClient object_manager;
	private Client upower_client;
	private Rfkill rfkill;

	public bool has_adapter { get; private set; default = false; }
	public bool retrieve_finished { get; private set; default = false; }

	/** Signal emitted when a Bluetooth device has been added. */
	public signal void device_added(Device1 device);
	/** Signal emitted when a Bluetooth device has been removed. */
	public signal void device_removed(Device1 device);
	/** Signal emitted when a UPower device for a Bluetooth device has been detected. */
	public signal void upower_device_added(Up.Device up_device);
	/** Signal emitted when a UPower device for a Bluetooth device has been removed. */
	public signal void upower_device_removed(string object_path);
	/** Signal emitted when airplane mode state has been changed. */
	public signal void airplane_mode_changed();

	construct {
		cancellable = new Cancellable();

		// Get our RFKill proxy
		create_rfkill_proxy();

		// Set up our UPower client
		create_upower_client.begin();

		// Creating our DBus Object Manager for Bluez
		create_object_manager.begin();
	}

	~BluetoothClient() {
		if (cancellable != null) {
			cancellable.cancel();
		}
	}

	[CCode (cname = "adapter1_proxy_get_type")]
	extern static Type get_adapter_proxy_type();

	[CCode (cname = "device1_proxy_get_type")]
	extern static Type get_device_proxy_type();

	private Type get_proxy_type_func(DBusObjectManagerClient manager, string object_path, string? interface_name) {
		if (interface_name == null) return typeof(DBusObjectProxy);

		if (interface_name == BLUEZ_ADAPTER_INTERFACE) return get_adapter_proxy_type();

		if (interface_name == BLUEZ_DEVICE_INTERFACE) return get_device_proxy_type();

		return typeof(DBusProxy);
	}

	/**
	 * Create and setup our UPower client.
	 */
	private async void create_upower_client() {
		try {
		upower_client = yield new Client.async(cancellable);

		// Connect the signals
		upower_client.device_added.connect(upower_device_added_cb);
		upower_client.device_removed.connect(upower_device_removed_cb);

		coldplug_client();
		} catch (Error e) {
			critical("Error creating UPower client: %s", e.message);
		}
	}

	/**
	 * Create and setup our Bluez DBus object manager client.
	 */
	private async void create_object_manager() {
		try {
			object_manager = yield new DBusObjectManagerClient.for_bus(
				BusType.SYSTEM,
				DBusObjectManagerClientFlags.NONE,
				BLUEZ_DBUS_NAME,
				BLUEZ_MANAGER_PATH,
				this.get_proxy_type_func,
				this.cancellable
			);

			// Add all of the current interfaces
			object_manager.get_objects().foreach((object) => {
				object.get_interfaces().foreach((iface) => on_interface_added(object, iface));
			});

			// Connect the signals
			object_manager.interface_added.connect(on_interface_added);
			object_manager.interface_removed.connect(on_interface_removed);

			object_manager.object_added.connect((object) => {
				object.get_interfaces().foreach((iface) => on_interface_added(object, iface));
			});
			object_manager.object_removed.connect((object) => {
				object.get_interfaces().foreach((iface) => on_interface_removed(object, iface));
			});
		} catch (Error e) {
			critical("Error getting DBus Object Manager: %s", e.message);
		}

		retrieve_finished = true;
	}

	private void create_rfkill_proxy() {
		try {
			rfkill = Bus.get_proxy_sync<Rfkill>(
				BusType.SESSION,
				RFKILL_DBUS_NAME,
				RFKILL_DBUS_PATH,
				DBusProxyFlags.NONE,
				cancellable
			);

			((DBusProxy) rfkill).g_properties_changed.connect((changed, invalid) => {
				var variant = changed.lookup_value("BluetoothAirplaneMode", new VariantType("b"));
				if (variant == null) return;
				airplane_mode_changed();
			});
		} catch (Error e) {
			critical("Error getting RFKill proxy: %s", e.message);
		}
	}

	/**
	 * Handles the addition of a DBus object interface.
	 */
	private void on_interface_added(DBusObject object, DBusInterface iface) {
		if (iface is Adapter1) {
			has_adapter = true;
		} else if (iface is Device1) {
			unowned Device1 device = iface as Device1;
			device_added(device);
		}
	}

	/**
	 * Handles the removal of a DBus object interface.
	 */
	private void on_interface_removed(DBusObject object, DBusInterface iface) {
		if (iface is Adapter1) {
			// FIXME: GLib.List has an is_empty() function, but for some reason it's not found
			// when used in this subdir.
			has_adapter = get_adapters().length() > 0;
		} else if (iface is Device1) {
			device_removed(iface as Device1);
		}
	}

	/**
	 * Handle when a UPower device is being added.
	 */
	private void upower_device_added_cb(Device up_device) {
		var serial = up_device.serial;

		// Make sure the device has a valid Bluetooth address
		if (serial == null || !is_valid_address(serial)) return;

		if (!up_device.native_path.has_prefix(BLUETOOTH_ADDRESS_PREFIX)) return;

		upower_device_added(up_device);
	}

	/**
	 * Handles the removal of a UPower device.
	 *
	 * The Bluetooth device corresponding to the UPower device will have its
	 * association removed, and its battery properties reset.
	 */
	private void upower_device_removed_cb(string object_path) {
		if (!object_path.has_prefix(BLUETOOTH_ADDRESS_PREFIX)) return;

		upower_device_removed(object_path);
	}

	/**
	 * Gets the result of the asynchronous UPower get_devices call and
	 * calls our device_added function to try to map them to Bluetooth
	 * devices.
	 */
	private void upower_get_devices_cb(Object? obj, AsyncResult? res) {
		try {
			GenericArray<Up.Device> devices = upower_client.get_devices_async.end(res);

			if (devices == null) {
				warning("No UPower devices found");
				return;
			}

			// Add each UPower device
			foreach (var device in devices) {
				upower_device_added_cb(device);
			}
		} catch (Error e) {
			warning("Error getting UPower devices: %s", e.message);
		}
	}

	/**
	 * Gets all UPower devices for the current Upower client, and tries to associate
	 * each UPower device with the corresponding Bluetooth device.
	 */
	private void coldplug_client() {
		if (upower_client == null) {
			return;
		}

		// Get the UPower devices asynchronously
		upower_client.get_devices_async.begin(cancellable, upower_get_devices_cb);
	}

	/**
	 * Check if a Bluetooth address is valid.
	 */
	private bool is_valid_address(string address) {
		if (address.length != 17) {
			return false;
		}

		for (var i = 0; i < 17; i++) {
			if (((i + 1) % 3) == 0) {
				if (address[i] != ':') {
					return false;
				}
				continue;
			}

			if (!address[i].isxdigit()) {
				return false;
			}
		}

		return true;
	}

	/**
	 * Get all Bluetooth adapters from our Bluez object manager.
	 */
	private List<Adapter1> get_adapters() {
		var adapters = new List<Adapter1>();

		object_manager.get_objects().foreach((object) => {
			var iface = object.get_interface(BLUEZ_ADAPTER_INTERFACE);
			if (iface == null) return;
			adapters.append(iface as Adapter1);
		});

		return (owned) adapters;
	}

	/**
	 * Get whether or not Bluetooth airplane mode is enabled.
	 */
	public bool airplane_mode_enabled() {
		return rfkill.bluetooth_airplane_mode;
	}

	/**
	 * Set whether or not Bluetooth airplane mode is enabled.
	 */
	public void set_airplane_mode(bool enabled) {
		rfkill.bluetooth_airplane_mode = enabled;
	}
}
