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
 * Inspired by gnome-bluetooth.
 */

using GLib;
using Up;

const string BLUEZ_DBUS_NAME = "org.bluez";
const string BLUEZ_MANAGER_PATH = "/";
const string BLUEZ_ADAPTER_INTERFACE = "org.bluez.Adapter1";
const string BLUEZ_DEVICE_INTERFACE = "org.bluez.Device1";

const uint DEVICE_REMOVAL_TIMEOUT = 50;

enum AdapterChangeType {
	OWNER_UPDATE,
	REPLACEMENT,
	NEW_DEFAULT,
	REMOVED
}

[DBus (name="org.freedesktop.DBus.ObjectManager")]
public interface BluezManager : GLib.Object {
	public abstract HashTable<string,HashTable<string,HashTable<string,Variant>>> GetManagedObjects() throws GLib.DBusError, GLib.IOError;
}

class BluetoothClient : GLib.Object {
	Cancellable cancellable;
	ListStore list_store;

	DBusObjectManagerClient dbus_object_manager = null;

	public uint num_adapters { get; private set; default = 0; }
	public Adapter1 default_adapter { get; private set; default = null; }
	public PowerState default_adapter_state { get; private set; default = ABSENT; }
	public bool discovery_started { get; set; default = false; }
	public string default_adapter_name { get; private set; default = null; }
	public string default_adapter_address { get; private set; default = null; }

	private bool _default_adapter_powered = false;
	public bool default_adapter_powered {
		get { return _default_adapter_powered; }
		set {
			if (default_adapter == null) return;
			if (default_adapter.Powered == value) return;

			var proxy = default_adapter as DBusProxy;
			var variant = new Variant.boolean(value);
			proxy.call.begin(
				"org.freedesktop.DBus.Properties.Set",
				new Variant("(ssv)", "org.bluez.Adapter1", "Powered", variant),
				DBusCallFlags.NONE,
				-1,
				null,
				adapter_set_powered_cb
			);
		}
	}

	private bool _default_adapter_setup_mode = false;
	public bool default_adapter_setup_mode {
		get { return _default_adapter_setup_mode; }
		set { set_adapter_discovering(value); }
	}

	private Client upower_client;
	private bool bluez_devices_coldplugged = false;
	private bool has_power_state = true;

	private Queue<string> removed_devices;
	private uint removed_devices_id = 0;

	public signal void device_added(BluetoothDevice device);
	public signal void device_removed(string path);

	construct {
		this.cancellable = new Cancellable();
		this.list_store = new ListStore(typeof(Device1));
		removed_devices = new Queue<string>();

		// Set up our UPower client
		try {
			make_upower_client.begin(cancellable, make_upower_cb);
		} catch (Error e) {
			critical("error creating UPower client: %s", e.message);
			return;
		}

		// Begin creating our DBus Object Manager for Bluez
		try {
			this.make_dbus_object_manager.begin(make_client_cb);
		} catch (Error e) {
			critical("error getting DBusObjectManager for Bluez: %s", e.message);
			return;
		}
	}

	BluetoothClient() {
		Object();
	}

	~BluetoothClient() {
		if (cancellable != null) {
			cancellable.cancel();
		}
	}

	private Type get_proxy_type_func(DBusObjectManagerClient manager, string object_path, string? interface_name) {
		if (interface_name == null) {
			return typeof(DBusObjectProxy);
		}

		if (interface_name == BLUEZ_ADAPTER_INTERFACE) {
			return typeof(Adapter1);
		}

		if (interface_name == BLUEZ_DEVICE_INTERFACE) {
			return typeof(Device1);
		}

		return typeof(DBusProxy);
	}

	private async Client make_upower_client(Cancellable cancellable) throws Error {
		return yield new Client.async(cancellable);
	}

	private async DBusObjectManagerClient make_dbus_object_manager() throws Error {
		return yield new DBusObjectManagerClient.for_bus(
			BusType.SYSTEM,
			DBusObjectManagerClientFlags.DO_NOT_AUTO_START,
			BLUEZ_DBUS_NAME,
			BLUEZ_MANAGER_PATH,
			this.get_proxy_type_func,
			this.cancellable
		);
	}

	private void start_discovery_cb(Object? obj, AsyncResult? res) {
		try {
			default_adapter.StartDiscovery.end(res);
		} catch (Error e) {
			var proxy = default_adapter as DBusProxy;
			warning("Error calling StartDiscovery() on '%s' org.bluez.Adapter1: %s (%s %d)", proxy.get_object_path(), e.message, e.domain.to_string(), e.code);
			discovery_started = false;
		}
	}

	private void stop_discovery_cb(Object? obj, AsyncResult? res) {
		try {
			default_adapter.StopDiscovery.end(res);
		} catch (Error e) {
			var proxy = default_adapter as DBusProxy;
			warning("Error calling StopDiscovery() on '%s': %s (%s %d)", proxy.get_object_path(), e.message, e.domain.to_string(), e.code);
			discovery_started = false;
		}
	}

	private void set_discovery_filter_cb(Object? object, AsyncResult? res) {
		try {
			default_adapter.SetDiscoveryFilter.end(res);
		} catch (Error e) {
			warning("Error calling SetDiscoveryFilter() on interface org.bluez.Adapter1: %s (%s %d)", e.message, e.domain.to_string(), e.code);
			discovery_started = false;
			return;
		}

		var proxy = default_adapter as DBusProxy;
		debug("Starting discovery on %s", proxy.get_object_path());
		default_adapter.StartDiscovery.begin(start_discovery_cb);
	}

	private void set_adapter_discovering(bool discovering) {
		if (discovery_started) return;
		if (default_adapter == null) return;

		var proxy = default_adapter as DBusProxy;

		discovery_started = discovering;

		if (discovering) {
			var properties = new HashTable<string, Variant>(str_hash, str_equal);
			properties["Discoverable"] = discovering;
			default_adapter.SetDiscoveryFilter.begin(properties, set_discovery_filter_cb);
		} else {
			debug("Stopping discovery on %s", proxy.get_object_path());
			default_adapter.StopDiscovery.begin(stop_discovery_cb);
		}
	}

	/**
	 * Get the device in our list model with the given path.
	 *
	 * If no device is found with the same path, `null` is returned.
	 */
	private BluetoothDevice? get_device_for_path(string path) {
		BluetoothDevice? device = null;

		var num_items = list_store.get_n_items();
		for (int i = 0; i < num_items; i++) {
			var d = list_store.get_item(i) as BluetoothDevice;
			if (path == d.get_object_path()) {
				device = d;
				break;
			}
		}

		return device;
	}

	/**
	 * Get the device in our list model with the given address.
	 *
	 * If no device is found with the same address, `null` is returned.
	 */
	private BluetoothDevice? get_device_for_address(string address) {
		BluetoothDevice? device = null;

		var num_items = list_store.get_n_items();
		for (int i = 0; i < num_items; i++) {
			var d = list_store.get_item(i) as BluetoothDevice;
			if (address == d.address) {
				device = d;
				break;
			}
		}

		return device;
	}

	/**
	 * Get the device in our list model with the given UPower device path.
	 *
	 * If no device is found with the same path, `null` is returned.
	 */
	private BluetoothDevice? get_device_for_upower_device(string path) {
		BluetoothDevice? device = null;

		var num_items = list_store.get_n_items();
		for (int i = 0; i < num_items; i++) {
			var d = list_store.get_item(i) as BluetoothDevice;
			var up_device = d.get_upower_device();

			if (up_device == null) {
				continue;
			}
			if (up_device.get_object_path() == path) {
				device = d;
			}
		}

		return device;
	}

	/**
	 * Tries to get an icon name present in GTK themes for a Bluetooth type.
	 *
	 * Not all types have relevant icons. Any type that doesn't have an icon
	 * will return `null`.
	 */
	private string? get_icon_for_type(BluetoothType type) {
		switch (type) {
			case COMPUTER:
				return "computer";
			case HEADSET:
				return "audio-headset";
			case HEADPHONES:
				return "audio-headphones";
			case KEYBOARD:
				return "input-keyboard";
			case MOUSE:
				return "input-mouse";
			case PRINTER:
				return "printer";
			case JOYPAD:
				return "input-gaming";
			case TABLET:
				return "input-tablet";
			case SPEAKERS:
				return "audio-speakers";
			case PHONE:
				return "phone";
			case DISPLAY:
				return "video-display";
			case SCANNER:
				return "scanner";
			default:
				return null;
		}
	}

	/**
	 * Get the type of a Bluetooth device, and use that type to get an icon for it.
	 */
	private void get_type_and_icon_for_device(Device1 device, out BluetoothType? type, out string? icon) {
		if (type != 0 || icon != null) {
			warning("Attempted to get type and icon for device '%s', but type or icon is not 0 or null", device.Name);
			return;
		}

		// Special case these joypads
		if (device.Name == "ION iCade Game Controller" || device.Name == "8Bitdo Zero GamePad") {
			type = BluetoothType.JOYPAD;
			icon = "input-gaming";
			return;
		}

		// First, try to match the appearance of the device
		if (type == BluetoothType.ANY) {
			type = appearance_to_type(device.Appearance);
		}
		// Match on the class if the appearance failed
		if (type == BluetoothType.ANY) {
			type = class_to_type(device.Class);
		}

		// Try to get an icon now
		icon = get_icon_for_type(type);

		// Fallback to the device's specified icon
		if (icon == null) {
			icon = device.Icon;
		}

		// Fallback to a generic icon
		if (icon == null) {
			icon = "bluetooth";
		}
	}

	/**
	 * Handle property changes for a Bluetooth device.
	 */
	private void device_notify_cb(Object obj, ParamSpec pspec) {
		Device1 device1 = obj as Device1;
		DBusProxy proxy = device1 as DBusProxy;
		var property = pspec.name;

		var path = proxy.get_object_path();
		var device = get_device_for_path(path);

		if (device == null) {
			debug("Device '%s' not found, ignoring property change for '%s'", path, property);
			return;
		}

		switch (property) {
			case "name":
				device.name = device1.Name;
				break;
			case "alias":
				device.alias = device1.Alias;
				break;
			case "paired":
				device.trusted = device1.Trusted;
				break;
			case "connected":
				device.connected = device1.Connected;
				break;
			case "uuids":
				device.uuids = device1.UUIDs;
				break;
			case "legacy-pairing":
				device.legacy_pairing = device1.LegacyPairing;
				break;
			case "icon":
			case "class":
			case "appearance":
				BluetoothType type = BluetoothType.ANY;
				string? icon = null;

				get_type_and_icon_for_device(device1, out type, out icon);

				device.type = type;
				device.icon = icon;
			default:
				debug("Not handling property '%s'", property);
		}
	}

	private void add_devices_to_list_store() {
		var coldplug_upower = !bluez_devices_coldplugged && upower_client != null;

		debug("Emptying device list store since default adapter changed");
		list_store.remove_all();

		DBusProxy proxy = default_adapter as DBusProxy;
		var default_adapter_path = proxy.get_object_path();

		debug("Coldplugging devices for new default adapter");

		bluez_devices_coldplugged = true;
		var object_list = dbus_object_manager.get_objects();

		// Add each device from DBus
		foreach (var obj in object_list) {
			var iface = obj.get_interface(BLUEZ_DEVICE_INTERFACE);
			if (iface == null) {
				continue;
			}

			Device1 device = iface as Device1;

			if (device.Adapter != default_adapter_path) {
				continue;
			}

			// Connect device 'notify' signal for property changes
			device.notify.connect(device_notify_cb);

			// Resolve device type and icon
			BluetoothType type = BluetoothType.ANY;
			string? icon = null;
			get_type_and_icon_for_device(device, out type, out icon);

			debug("Adding device '%s' on adapter '%s' to list store", device.Address, device.Adapter);

			// Create Device object
			var device_obj = new BluetoothDevice(device, type, icon);

			// Append to list_store
			list_store.append(device_obj);

			// Emit device-added signal
			device_added(device_obj);
		}

		if (coldplug_upower) {
			coldplug_client();
		}
	}

	/**
	 * Get the power state of the current default adapter.
	 */
	private PowerState get_state() {
		if (default_adapter == null) {
			return PowerState.ABSENT;
		}

		var state = default_adapter.PoweredState;

		// Check if we have a valid power state
		if (state == null) {
			has_power_state = false;

			// Fallback to either on or off
			return default_adapter.Powered ? PowerState.ON : PowerState.OFF;
		}

		return PowerState.from_string(state);
	}

	private bool is_default_adapter(Adapter1? adapter) {
		if (this.default_adapter == null) {
			return false;
		}

		if (adapter == null) {
			return false;
		}

		DBusProxy adapter_proxy = adapter as DBusProxy;
		DBusProxy default_proxy = default_adapter as DBusProxy;

		return (adapter_proxy.get_object_path() == default_proxy.get_object_path());
	}

	private bool should_be_default_adapter(Adapter1 adapter) {
		DBusProxy proxy = adapter as DBusProxy;
		DBusProxy default_proxy = this.default_adapter as DBusProxy;

		return proxy.get_object_path() == default_proxy.get_object_path();
	}

	/**
	 * Reset the default_adapter properties to their defaults.
	 */
	private void reset_default_adapter_props() {
		default_adapter = null;
		default_adapter_address = null;
		default_adapter_powered = false;
		default_adapter_state = PowerState.ABSENT;
		discovery_started = false;
		default_adapter_name = null;
	}

	/**
	 * Updates the default_adapter_* properties from the current default adapter.
	 */
	private void update_default_adapter_props() {
		default_adapter_address = default_adapter.Address;
		default_adapter_powered = default_adapter.Powered;
		default_adapter_state = PowerState.from_string(default_adapter.PoweredState);
		discovery_started = default_adapter.Discovering;
		default_adapter_name = default_adapter.Name;
	}

	/**
	 * Handles when the default Bluetooth adapter changes.
	 */
	private void default_adapter_changed(DBusProxy proxy, AdapterChangeType change_type) {
		Adapter1 adapter = proxy as Adapter1;

		switch (change_type) {
			case REMOVED:
				reset_default_adapter_props();
				list_store.remove_all();
				return;
			case REPLACEMENT:
				list_store.remove_all();
				set_adapter_discovering(false);
				default_adapter = null;
				break;
			default: // Handles new default and owner update cases
				default_adapter = null;
				break;
		}

		default_adapter = adapter;
		adapter.notify.connect(adapter_notify_cb);

		// Bail if the change was only an update
		if (change_type == OWNER_UPDATE) {
			return;
		}

		add_devices_to_list_store();
		update_default_adapter_props();
	}

	private void adapter_set_powered_cb(Object? obj, AsyncResult? res) {
		var proxy = default_adapter as DBusProxy;

		try {
			proxy.call.end(res);
		} catch (Error e) {
			warning("Error setting property 'Powered' on %s: %s (%s, %d)", proxy.get_object_path(), e.message, e.domain.to_string(), e.code);
		}
	}

	/**
	 * Process the device removal queue, removing all devices with paths
	 * in the queue from our list store.
	 */
	private bool unqueue_device_removal() {
		if (removed_devices == null || removed_devices.is_empty()) return Source.REMOVE;

		// Iterate over the queue
		string? path = null;
		while ((path = removed_devices.pop_head()) != null) {
			var found = false;
			var num_items = list_store.get_n_items();

			debug("Processing '%s' in removal queue", path);

			// Iterate over our list store to try to find the correct device
			for (var i = 0; i < num_items; i++) {
				var device = list_store.get_item(i) as BluetoothDevice;

				// Check if the path for this device matches the current queue item
				if (path != device.get_object_path()) continue;

				// Matching device was found, remove it
				device_removed(path);
				list_store.remove(i);
				found = true;
				break;
			}

			if (!found) debug("Device %s not known, ignoring", path);
		}

		// Clear any remaining devices from the queue
		removed_devices.clear();
		return Source.REMOVE;
	}

	/**
	 * Adds a new Bluetooth device to our list store, or updates an
	 * existing one if it already exists.
	 */
	private void add_device(Device1 device) {
		var adapter_path = device.Adapter;
		var default_adapter_proxy = default_adapter as DBusProxy;
		var default_adapter_path = default_adapter_proxy.get_object_path();

		// Ensure that the device is on the current default adapter
		if (adapter_path != default_adapter_path) return;

		device.notify.connect(device_notify_cb);

		var device_proxy = device as DBusProxy;
		var device_path = device_proxy.get_object_path();
		var device_object = get_device_for_path(device_path);

		// Update the device if it's already been added
		if (device_object != null) {
			debug("Updating proxy for device '%s'", device_path);
			device_object.proxy = device_proxy;
			return;
		}

		BluetoothType type = 0;
		string? icon = null;
		get_type_and_icon_for_device(device, out type, out icon);

		debug("Adding device '%s' to adapter '%s'", device.Address, adapter_path);

		device_object = new BluetoothDevice(device, type, icon);
		list_store.append(device_object);
		device_added(device_object);
	}

	/**
	 * Adds a device to the queue for removal.
	 */
	private void queue_remove_device(string path) {
		debug("Queueing removal of device %s", path);
		removed_devices.push_head(path);

		// Remove the current task to process the queue, if any
		if (removed_devices_id != 0) {
			Source.remove(removed_devices_id);
		}

		// Add a task to process the queue
		removed_devices_id = Timeout.add(DEVICE_REMOVAL_TIMEOUT, unqueue_device_removal);
	}

	/**
	 * Handles property changes on a Bluetooth adapter.
	 *
	 * If the adapter is not the current default adapter, then
	 * nothing is updated.
	 */
	private void adapter_notify_cb(Object obj, ParamSpec pspec) {
		Adapter1 adapter = obj as Adapter1;
		DBusProxy proxy = adapter as DBusProxy;

		var property = pspec.name;
		var adapter_path = proxy.get_object_path();

		if (default_adapter == null) {
			debug("Property '%s' changed on adapter '%s', but default adapter not set yet", property, adapter_path);
			return;
		}

		if (adapter != default_adapter) {
			debug("Ignoring property change '%s' change on non-default adapter '%s'", property, adapter_path);
			return;
		}

		debug("Property change received for adapter '%s': %s", adapter_path, property);

		// Update the client property that changed on the adapter
		switch (property) {
			case "alias":
				default_adapter_name = adapter.Alias;
			case "discovering":
				discovery_started = adapter.Discovering;
			case "powered":
				default_adapter_powered = adapter.Powered;
				if (!has_power_state) {
					default_adapter_state = get_state();
				}
			case "power-state":
				default_adapter_state = get_state();
		}
	}

	private void add_adapter(Adapter1 adapter) {
		DBusProxy proxy = adapter as DBusProxy;

		var name = proxy.get_name_owner();
		var iface = proxy.get_interface_name();
		var path = proxy.get_object_path();

		if (this.default_adapter == null) {
			debug("Adding adapter %s %s %s", name, path, iface);
			default_adapter_changed(proxy, NEW_DEFAULT);
		} else if (is_default_adapter(adapter)) {
			debug("Updating default adapter with new proxy %s %s %s", name, path, iface);
			default_adapter_changed(proxy, OWNER_UPDATE);
		} else if (should_be_default_adapter(adapter)) {
			var default_proxy = default_adapter as DBusProxy;
			debug("Replacing adapter %s with %s %s %s", default_proxy.get_name_owner(), name, path, iface);
			default_adapter_changed(proxy, REPLACEMENT);
		} else {
			debug("Ignoring non-default adapter %s %s %s", name, path, iface);
			return;
		}

		this.num_adapters++;
	}

	private void adapter_removed(string path) {
		DBusProxy default_proxy = this.default_adapter as DBusProxy;
		DBusProxy new_default_adapter = null;
		bool was_default = false;

		// Check if this is the path to the current default adapter
		if (strcmp(path, default_proxy.get_object_path()) == 0) {
			was_default = true;
		}

		if (was_default) {
			this.num_adapters--;
			return;
		}

		// Look through the list of DBus objects for a new default adapter
		var object_list = this.dbus_object_manager.get_objects();
		foreach (var object in object_list) {
			var iface = object.get_interface(BLUEZ_ADAPTER_INTERFACE);
			if (iface != null) {
				new_default_adapter = iface as DBusProxy;
				break;
			}
		}

		// Decide if we have a removal, or if we have a new default
		var change_type = new_default_adapter == null ? AdapterChangeType.REMOVED : AdapterChangeType.NEW_DEFAULT;

		// Handle a removal
		if (change_type == REMOVED) {
			// TODO: Clear the removed_devices queue
		}

		default_adapter_changed(new_default_adapter, change_type);
		this.num_adapters--;
	}

	private void interface_added(DBusObject object, DBusInterface iface) {
		if (iface.get_type() == typeof(Adapter1)) {
			Adapter1 adapter = iface as Adapter1;
			add_adapter(adapter);
		} else if (iface.get_type() == typeof(Device1)) {
			Device1 device = iface as Device1;
			add_device(device);
		}
	}

	private void interface_removed(DBusObject object, DBusInterface iface) {
		if (iface.get_type() == typeof(Adapter1)) {
			adapter_removed(object.get_object_path());
		} else if (iface.get_type() == typeof(Device1)) {
			queue_remove_device(object.get_object_path());
		}
	}

	private void object_added(DBusObject object) {
		var ifaces = object.get_interfaces();
		foreach (var iface in ifaces) {
			interface_added(object, iface);
		}
	}

	private void object_removed(DBusObject object) {
		var ifaces = object.get_interfaces();
		foreach (var iface in ifaces) {
			interface_removed(object, iface);
		}
	}

	private List<DBusInterface>? filter_adapter_list(List<DBusObject> object_list) {
		List<DBusInterface> ret = null;

		foreach (var object in object_list) {
			var iface = object.get_interface(BLUEZ_ADAPTER_INTERFACE);
			if (iface != null) ret.append(iface);
		}

		return ret;
	}

	private void make_client_cb(Object? obj, AsyncResult? res) {
		try {
			dbus_object_manager = make_dbus_object_manager.end(res);
		} catch (Error e) {
			if (!e.matches(DBusError.IO_ERROR, IOError.CANCELLED)) {
				critical("error getting DBusObjectManager for Bluez: %s", e.message);
			}
			return;
		}

		// Connect manager signals
		dbus_object_manager.interface_added.connect(interface_added);
		dbus_object_manager.interface_removed.connect(interface_removed);

		dbus_object_manager.object_added.connect(object_added);
		dbus_object_manager.object_removed.connect(object_removed);

		// Create the adapter list
		var object_list = dbus_object_manager.get_objects();
		var adapter_list = filter_adapter_list(object_list);

		// Reverse sort the adapter list
		adapter_list.sort((a, b) => {
			DBusProxy adapter_a = a as DBusProxy;
			DBusProxy adapter_b = b as DBusProxy;

			return adapter_b.get_object_path().collate(adapter_a.get_object_path());
		});

		// Add all of the adapters
		debug("Adding adapters from DBus Object Manager");
		foreach (var adapter in adapter_list) {
			add_adapter(adapter as Adapter1);
		}
	}

	/**
	 * Handle when a UPower device is being added.
	 */
	private void upower_device_added_cb(Device up_device) {
		var serial = up_device.serial;

		// Make sure the device has a valid Bluetooth address
		if (serial == null || !is_valid_address(serial)) {
			return;
		}

		var device = get_device_for_address(serial);

		if (device == null) {
			warning("Could not find Bluetooth device for UPower device with serial '%s'", serial);
			return;
		}

		// Connect signals
		up_device.notify["battery-level"].connect(() => device.update_battery(up_device));
		up_device.notify["percentage"].connect(() => device.update_battery(up_device));

		// Update the power properties
		device.set_upower_device(up_device);
		device.update_battery(up_device);
	}

	/**
	 * Handles the removal of a UPower device.
	 *
	 * The Bluetooth device corresponding to the UPower device will have its
	 * association removed, and its battery properties reset.
	 */
	private void upower_device_removed_cb(string object_path) {
		var device = get_device_for_upower_device(object_path);

		if (device == null) {
			return;
		}

		debug("Removing Upower Device '%s' for Bluetooth device '%s'", object_path, device.get_object_path());

		// Reset device power properties
		device.set_upower_device(null);
		device.battery_type = BatteryType.NONE;
		device.battery_level = DeviceLevel.NONE;
		device.battery_percentage = 0.0f;
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

	private void make_upower_cb(Object? obj, AsyncResult? res) {
		try {
			upower_client = make_upower_client.end(res);
		} catch (Error e) {
			critical("Error creating UPower client: %s", e.message);
			return;
		}

		upower_client.device_added.connect(upower_device_added_cb);
		upower_client.device_removed.connect(upower_device_removed_cb);

		// Maybe coldplug UPower devices
		if (bluez_devices_coldplugged) {
			coldplug_client();
		}
	}

	/**
	* Gets the type of Bluetooth device based on its appearance value.
	* This is usually found in the GAP service.
	*/
	private BluetoothType appearance_to_type(uint16 appearance) {
		switch ((appearance & 0xffc0) >> 6) {
			case 0x01:
				return PHONE;
			case 0x02:
				return COMPUTER;
			case 0x05:
				return DISPLAY;
			case 0x0a:
				return OTHER_AUDIO;
			case 0x0b:
				return SCANNER;
			case 0x0f: /* HID Generic */
				switch (appearance & 0x3f) {
				case 0x01:
					return KEYBOARD;
				case 0x02:
					return MOUSE;
				case 0x03:
				case 0x04:
					return JOYPAD;
				case 0x05:
					return TABLET;
				case 0x08:
					return SCANNER;
				}
				break;
			case 0x21:
				return SPEAKERS;
			case 0x25: /* Audio */
				switch (appearance & 0x3f) {
				case 0x01:
				case 0x02:
				case 0x04:
					return HEADSET;
				case 0x03:
					return HEADPHONES;
				default:
					return OTHER_AUDIO;
				}
				break;
		}

		return ANY;
	}

	/**
	* Gets the type of a Bluetooth device based on its class.
	*/
	private BluetoothType class_to_type(uint32 klass) {
		switch ((klass & 0x1f00) >> 8) {
			case 0x01:
				return COMPUTER;
			case 0x02:
				switch ((klass & 0xfc) >> 2) {
					case 0x01:
					case 0x02:
					case 0x03:
					case 0x05:
						return PHONE;
					case 0x04:
						return MODEM;
				}
				break;
			case 0x03:
				return NETWORK;
			case 0x04:
				switch ((klass & 0xfc) >> 2) {
					case 0x01:
					case 0x02:
						return HEADSET;
					case 0x05:
						return SPEAKERS;
					case 0x06:
						return HEADPHONES;
					case 0x0b: /* VCR */
					case 0x0c: /* Video Camera */
					case 0x0d: /* Camcorder */
						return VIDEO;
					default:
						return OTHER_AUDIO;
				}
				break;
			case 0x05:
				switch ((klass & 0xc0) >> 6) {
					case 0x00:
						switch ((klass & 0x1e) >> 2) {
						case 0x01:
						case 0x02:
							return JOYPAD;
						case 0x03:
							return REMOTE_CONTROL;
					}
					break;
				case 0x01:
					return KEYBOARD;
				case 0x02:
					switch ((klass & 0x1e) >> 2) {
						case 0x05:
							return TABLET;
						default:
							return MOUSE;
					}
				}
				break;
			case 0x06:
				if ((klass & 0x80) == 1)
					return PRINTER;
				if ((klass & 0x40) == 1)
					return SCANNER;
				if ((klass & 0x20) == 1)
					return CAMERA;
				if ((klass & 0x10) == 1)
					return DISPLAY;
				break;
			case 0x07:
				return WEARABLE;
			case 0x08:
				return TOY;
		}

		return ANY;
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
}
