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
	private HashTable<Transfer, string> active_transfers;

	construct {
		active_transfers = new HashTable<Transfer, string>(direct_hash, direct_equal);
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
			foreach (var obj in object_manager.get_objects()) {
				foreach (var iface in obj.get_interfaces()) {
					interface_added(obj, iface);
				}
			}

			// Connect signals for added/removed interfaces
			object_manager.interface_added.connect(interface_added);
			object_manager.interface_removed.connect(interface_removed);

			// Connect signals for added/removed objects
			object_manager.object_added.connect(on_object_added);

			object_manager.object_removed.connect(on_object_removed);
		} catch (Error e) {
			critical("Error getting DBus object manager for Obex: %s", e.message);
		}
	}

	private void on_object_added(DBusObject obj) {
		foreach (var iface in obj.get_interfaces()) {
			interface_added(obj, iface);
		}
	}

	private void on_object_removed(DBusObject obj) {
		foreach (var iface in obj.get_interfaces()) {
			interface_removed(obj, iface);
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

	/** Stores session destination for each transfer for use in the signal handler. */
	private HashTable<Transfer, string> transfer_sessions = new HashTable<Transfer, string>(direct_hash, direct_equal);

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
				return; // Cannot proceed without valid session
			}

			// Verify session was successfully created
			if (session == null) {
				critical("Bluetooth Obex session is null after proxy creation");
				return;
			}

			active_transfers[transfer] = session.destination;
			transfer_sessions[transfer] = session.destination;
			((DBusProxy) transfer).g_properties_changed.connect(on_transfer_properties_changed);
			transfer_added(session.destination, transfer);
		}
	}

	private void on_transfer_properties_changed(DBusProxy proxy, Variant changed, string[] invalid) {
		unowned Transfer transfer = (Transfer) proxy;
		var destination = transfer_sessions[transfer];
		if (destination != null) {
			transfer_active(destination);
		}
	}

	/**
	 * Handles when an interface has been removed.
	 */
	private void interface_removed(DBusObject obj, DBusInterface iface) {
		if (iface is Transfer) {
			unowned Transfer transfer = (Transfer) iface;
			if (active_transfers.contains(transfer)) {
				active_transfers.remove(transfer);
			}
			transfer_sessions.remove(transfer);
			transfer_removed(transfer);
		}
	}
}
