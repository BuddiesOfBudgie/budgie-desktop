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

class BluetoothClient : GLib.Object {
	private Cancellable cancellable;

	private DBusObjectManagerClient object_manager;
	private Client upower_client;

	private HashTable<string, Up.Device?> upower_devices;

	private bool bluez_devices_coldplugged = false;

	public bool has_adapter { get; private set; default = false; }
	public bool is_connected { get; private set; default = false; }
	public bool is_enabled { get; private set; default = false; }
	public bool is_powered { get; private set; default = false; }
	public bool retrieve_finished { get; private set; default = false; }

	/** Signal emitted when a Bluetooth device has been added. */
	public signal void device_added(Device1 device);
	/** Signal emitted when a Bluetooth device has been removed. */
	public signal void device_removed(Device1 device);
	/** Signal emitted when our powered or connected state changes. */
	public signal void global_state_changed(bool enabled, bool connected);

	construct {
		cancellable = new Cancellable();
		upower_devices = new HashTable<string, Up.Device?>(str_hash, str_equal);

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

		// Maybe coldplug UPower devices
		if (bluez_devices_coldplugged) {
			coldplug_client();
		}
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

	//  private BluetoothDevice? get_device_with_address(string address) {
	//  	var num_items = devices.get_n_items();

	//  	for (var i = 0; i < num_items; i++) {
	//  		var device = devices.get_item(i) as BluetoothDevice;
	//  		if (device.address == address) return device;
	//  	}

	//  	return null;
	//  }

	//  private BluetoothDevice? get_device_with_object_path(string object_path) {
	//  	var num_items = devices.get_n_items();

	//  	for (var i = 0; i < num_items; i++) {
	//  		var device = devices.get_item(i) as BluetoothDevice;
	//  		if (device.get_object_path() == object_path) return device;
	//  	}

	//  	return null;
	//  }

	/**
	 * Handles the addition of a DBus object interface.
	 */
	private void on_interface_added(DBusObject object, DBusInterface iface) {
		if (iface is Adapter1) {
			unowned Adapter1 adapter = iface as Adapter1;

			((DBusProxy) adapter).g_properties_changed.connect((changed, invalid) => {
				var powered = changed.lookup_value("Powered", new VariantType("b"));
				if (powered == null) return;
				set_last_powered.begin();
			});

			if (!adapter.powered) return;

			// Set the discovery filter
			var properties = new HashTable<string,Variant>(str_hash, str_equal);
			properties["Discoverable"] = new Variant.boolean(true);
			adapter.set_discovery_filter.begin(properties, (obj, res) => {
				try {
					adapter.set_discovery_filter.end(res);

					// Start Bluetooth discovery
					adapter.start_discovery.begin((obj, res) => {
						try {
							adapter.start_discovery.end(res);
						} catch (Error e) {
							warning("Error beginning discovery on adapter %s: %s", adapter.alias, e.message);
						}
					});
				} catch (Error e) {
					warning("Error setting discovery filter on %s: %s", adapter.alias, e.message);
				}
			});
		} else if (iface is Device1) {
			unowned Device1 device = iface as Device1;
			device_added(device);

			((DBusProxy) device).g_properties_changed.connect((changed, invalid) => {
				check_powered();
			});

			check_powered();
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
		message("upower_device_added_cb");

		// Make sure the device has a valid Bluetooth address
		if (serial == null || !is_valid_address(serial)) {
			return;
		}

		// Get the device with the address
		string? key = null;
		Device? value = null;
		var found = upower_devices.lookup_extended(up_device.get_object_path(), out key, out value);
		if (found) message("Key in HashTable found: %s", key);
		else message("Key not found. Sadge :(");

		//  if (device == null) {
		//  	warning("Could not find Bluetooth device for UPower device with serial '%s'", serial);
		//  	return;
		//  }

		//  // Connect signals
		//  up_device.notify["battery-level"].connect(() => device.update_battery(up_device));
		//  up_device.notify["percentage"].connect(() => device.update_battery(up_device));

		//  // Update the power properties
		//  device.set_upower_device(up_device);
		//  device.update_battery(up_device);
	}

	/**
	 * Handles the removal of a UPower device.
	 *
	 * The Bluetooth device corresponding to the UPower device will have its
	 * association removed, and its battery properties reset.
	 */
	private void upower_device_removed_cb(string object_path) {
		//  var device = get_device_with_object_path(object_path);

		//  if (device == null) {
		//  	return;
		//  }

		//  debug("Removing Upower Device '%s' for Bluetooth device '%s'", object_path, device.get_object_path());

		//  // Reset device power properties
		//  device.set_upower_device(null);
		//  device.battery_type = BatteryType.NONE;
		//  device.battery_level = DeviceLevel.NONE;
		//  device.battery_percentage = 0.0f;
	}

	/**
	 * Gets the result of the asynchronous UPower get_devices call and
	 * calls our device_added function to try to map them to Bluetooth
	 * devices.
	 */
	private void upower_get_devices_cb(Object? obj, AsyncResult? res) {
		GenericArray<Up.Device> devices = null;

		try {
			devices = upower_client.get_devices_async.end(res);
		} catch (Error e) {
			warning("Error getting UPower devices: %s", e.message);
			return;
		}

		if (devices == null) {
			warning("No UPower devices found");
			return;
		}

		debug("Found %d UPower devices", devices.length);

		// Add each UPower device
		foreach (var device in devices) {
			upower_device_added_cb(device);
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
	public List<Adapter1> get_adapters() {
		var adapters = new List<Adapter1>();

		object_manager.get_objects().foreach((object) => {
			var iface = object.get_interface(BLUEZ_ADAPTER_INTERFACE);
			if (iface == null) return;
			adapters.append(iface as Adapter1);
		});

		return (owned) adapters;
	}

	/**
	 * Get all Bluetooth devices from our Bluez object manager.
	 */
	public List<Device1> get_devices() {
		var devices = new List<Device1>();

		object_manager.get_objects().foreach((object) => {
			var iface = object.get_interface(BLUEZ_DEVICE_INTERFACE);
			if (iface == null) return;
			devices.append(iface as Device1);
		});

		return (owned) devices;
	}

	/**
	 * Check if any adapter is currently connected.
	 */
	public bool get_connected() {
		var devices = get_devices();

		foreach (var device in devices) {
			if (device.connected) return true;
		}

		return false;
	}

	/**
	 * Check if any adapter is powered on.
	 */
	public bool get_powered() {
		var adapters = get_adapters();

		foreach (var adapter in adapters) {
			if (adapter.powered) return true;
		}

		return false;
	}

	/**
	 * Check if any Bluetooth adapter is powered and connected, and update our
	 * Bluetooth state accordingly.
	 */
	public void check_powered() {
		// This is called usually as a signal handler, so start an Idle
		// task to prevent race conditions.
		Idle.add(() => {
			// Get current state
			var connected = get_connected();
			var powered = get_powered();

			debug("connected: %s new_connected: %s | powered: %s new_powered: %s",
				is_connected ? "yes" : "no", connected ? "yes" : "no",
				is_powered ? "yes" : "no", powered ? "yes" : "no"
			);

			// Do nothing if the state hasn't changed
			if (connected == is_connected && powered == is_powered) return Source.REMOVE;

			// Set the new state
			is_connected = connected;
			is_powered = powered;

			// Emit changed signal
			global_state_changed(powered, connected);

			return Source.REMOVE;
		});
	}

	/**
	 * Set the powered state of all adapters. If being powered off and an adapter has
	 * devices connected to it, they will be disconnected.
	 *
	 * It is intended to use `check_powered()` as a callback to this async function.
	 * As such, this function does not set our global state directly.
	 */
	public async void set_all_powered(bool powered) {
		// Set the adapters' powered state
		var adapters = get_adapters();
		foreach (var adapter in adapters) {
			adapter.powered = powered;
		}

		is_enabled = powered;

		if (powered) return;

		// If the power is being turned off, disconnect from all devices
		var devices = get_devices();
		foreach (var device in devices) {
			if (device.connected) {
				try {
					yield device.disconnect();
				} catch (Error e) {
					warning("Error disconnecting Bluetooth device: %s", e.message);
				}
			}
		}
	}

	public async void set_last_powered() {
		yield set_all_powered(is_enabled);
		check_powered();
	}
}
