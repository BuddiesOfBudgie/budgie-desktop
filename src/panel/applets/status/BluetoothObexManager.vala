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

public class ObexManager : Object {
	public signal void transfer_added(string address, Transfer transfer);
	public signal void transfer_removed(Transfer transfer);
	public signal void transfer_active(string address);

	private DBusObjectManager object_manager;

	construct {
		create_manager.begin();
	}

	/**
	 * Creates our Obex DBus object manager and connects to its signals.
	 */
	private async void create_manager() {
		try {
			object_manager = yield new DBusObjectManagerClient.for_bus(
				BusType.SESSION,
				DBusObjectManagerClientFlags.NONE,
				"org.bluez.obex",
				"/",
				object_manager_proxy_get_type
			);

			// Get and add any current Transfers
			object_manager.get_objects().foreach((obj) => {
				obj.get_interfaces().foreach((iface) => interface_added(obj, iface));
			});

			// Connect signals for added/removed interfaces
			object_manager.interface_added.connect(interface_added);
			object_manager.interface_removed.connect(interface_removed);

			// Connect signals for added/removed objects
			object_manager.object_added.connect((obj) => {
				obj.get_interfaces().foreach((iface) => interface_added(obj, iface));
			});

			object_manager.object_removed.connect((obj) => {
				obj.get_interfaces().foreach((iface) => interface_removed(obj, iface));
			});
		} catch (Error e) {
			critical("Error getting DBus object manager for Obex: %s", e.message);
		}
	}

	[CCode (cname="transfer_proxy_get_type")]
	extern static Type get_obex_transfer_proxy_type();

	/**
	 * Get the type for our object manager interfaces.
	 */
	private Type object_manager_proxy_get_type(DBusObjectManagerClient manager, string object_path, string? interface_name) {
		if (interface_name == null) return typeof(DBusObjectProxy);

		if (interface_name == "org.bluez.obex.Transfer1") return get_obex_transfer_proxy_type();

		return typeof(DBusProxy);
	}

	/**
	 * Handles when an interface has been added.
	 */
	private void interface_added(DBusObject obj, DBusInterface iface) {
		if (iface is Transfer) {
			unowned Transfer transfer = iface as Transfer;
			Session? session = null;

			try {
				session = Bus.get_proxy_sync(
					BusType.SESSION,
					"org.bluez.obex",
					transfer.session
				);
			} catch (Error e) {
				critical("Error getting Obex session proxy: %s", e.message);
			}

			transfer_added(session.destination, transfer);

			((DBusProxy) transfer).g_properties_changed.connect((changed, invalid) => {
				transfer_active(session.destination);
			});
		}
	}

	/**
	 * Handles when an interface has been removed.
	 */
	private void interface_removed(DBusObject obj, DBusInterface iface) {
		if (iface is Transfer) {
			transfer_removed(iface as Transfer);
		}
	}
}
