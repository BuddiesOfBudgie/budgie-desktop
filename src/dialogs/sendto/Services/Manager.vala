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

public class Bluetooth.ObjectManager : Object {
	public bool has_object { get; private set; default = false; }

    private GLib.DBusObjectManagerClient object_manager;

    public signal void device_added(Bluetooth.Device device);
    public signal void device_removed(Bluetooth.Device device);
    public signal void status_discovering();

    construct {
        create_manager.begin();
        register_obex_agentmanager();
    }

    public async void create_manager() {
        try {
            object_manager = yield new GLib.DBusObjectManagerClient.for_bus.begin(
                BusType.SYSTEM,
                GLib.DBusObjectManagerClientFlags.NONE,
                "org.bluez",
                "/",
                object_manager_proxy_get_type,
                null
            );

            object_manager.get_objects().foreach((object) => {
                object.get_interfaces().foreach((iface) => on_interface_added(object, iface));
            });

            object_manager.interface_added.connect(on_interface_added);

            object_manager.interface_removed.connect(on_interface_removed);

            object_manager.object_added.connect((object) => {
                object.get_interfaces().foreach((iface) => on_interface_added(object, iface));
            });

            object_manager.object_removed.connect((object) => {
                object.get_interfaces().foreach((iface) => on_interface_removed(object, iface));
            });
        } catch (Error e) {
            critical("Error getting Bluez object manager: %s", e.message);
        }
    }

    //TODO: Do not rely on this when it is possible to do it natively in Vala
    [CCode (cname="bluetooth_device_proxy_get_type")]
    extern static GLib.Type get_device_proxy_type();

    [CCode (cname="bluetooth_adapter_proxy_get_type")]
    extern static GLib.Type get_adapter_proxy_type();

    private GLib.Type object_manager_proxy_get_type(DBusObjectManagerClient manager, string object_path, string? interface_name) {
        if (interface_name == null) return typeof (GLib.DBusObjectProxy);

        switch (interface_name) {
            case "org.bluez.Device1":
                return get_device_proxy_type();
            case "org.bluez.Adapter1":
                return get_adapter_proxy_type();
            default:
                return typeof(GLib.DBusProxy);
        }
    }

    private void register_obex_agentmanager() {
        try {
            var connection = GLib.Bus.get_sync(BusType.SESSION);
            connection.call.begin(
				"org.bluez.obex",
				"/org/bluez/obex",
				"org.bluez.obex.AgentManager1",
				"RegisterAgent", // TODO: Do we need to worry about unregistering?
				new Variant("(o)", "/org/bluez/obex/budgie"),
				null,
				GLib.DBusCallFlags.NONE,
				-1);
        } catch (Error e) {
            critical("Error registering Obex agent manager: %s", e.message);
        }
    }

    private void on_interface_added(GLib.DBusObject object, GLib.DBusInterface iface) {
        if (iface is Bluetooth.Device) {
            unowned var device = (Bluetooth.Device) iface;
            device_added(device);
        } else if (iface is Bluetooth.Adapter) {
            unowned var adapter = (Bluetooth.Adapter) iface;
            has_object = true;
            ((DBusProxy) adapter).g_properties_changed.connect((changed, invalid) => {
                var discovering = changed.lookup_value("Discovering", GLib.VariantType.BOOLEAN);
                if (discovering != null) {
                    status_discovering();
                }
            });
        }
    }

    private void on_interface_removed(GLib.DBusObject object, GLib.DBusInterface iface) {
        if (iface is Bluetooth.Device) {
            device_removed((Bluetooth.Device) iface);
        } else if (iface is Bluetooth.Adapter) {
            has_object = !get_adapters().is_empty;
        }
    }

    public Gee.LinkedList<Bluetooth.Adapter> get_adapters() requires (object_manager != null) {
        var adapters = new Gee.LinkedList<Bluetooth.Adapter>();

        object_manager.get_objects().foreach((object) => {
            GLib.DBusInterface? iface = object.get_interface("org.bluez.Adapter1");
            if (iface == null) return;

            adapters.add(((Bluetooth.Adapter) iface));
        });

        return (owned) adapters;
    }

    public Gee.Collection<Bluetooth.Device> get_devices() requires (object_manager != null) {
        var devices = new Gee.LinkedList<Bluetooth.Device>();

        object_manager.get_objects().foreach((object) => {
            GLib.DBusInterface? iface = object.get_interface("org.bluez.Device1");
            if (iface == null) return;

            devices.add(((Bluetooth.Device) iface));
        });

        return (owned) devices;
    }

    public async void start_discovery() {
        var adapters = get_adapters();

        foreach (var adapter in adapters) {
            try {
                adapter.discoverable = true;
                yield adapter.start_discovery();
            } catch (Error e) {
                critical("Error starting discovery on Bluetooth adapter '%s': %s", adapter.name, e.message);
            }
        }
    }

    public bool check_discovering() {
        var adapters = get_adapters();

        foreach (var adapter in adapters) {
            return adapter.discovering;
        }

        return false;
    }

    public async void stop_discovery() {
        var adapters = get_adapters();

        foreach (var adapter in adapters) {
            adapter.discoverable = false;

            try {
                if (adapter.powered && adapter.discovering) {
                    yield adapter.stop_discovery();
                }
            } catch (Error e) {
                critical("Error stopping discovery on Bluetooth adapter '%s': %s", adapter.name, e.message);
            }
        }
    }

    public Bluetooth.Adapter? get_adapter_from_path(string path) {
        GLib.DBusObject? object = object_manager.get_object(path);

        if (object != null) {
            return (Bluetooth.Adapter?) object.get_interface("org.bluez.Adapter1");
        }

        return null;
    }

    public Bluetooth.Device? get_device(string address) {
        var devices = get_devices();

        foreach (var device in devices) {
            if (device.address == address) {
                return device;
            }
        }

        return null;
    }
}
