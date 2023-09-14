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

[DBus (name = "org.bluez.obex.Error")]
public errordomain BluezObexError {
	REJECTED,
	CANCELED
}

[DBus (name = "org.bluez.obex.Agent1")]
public class Bluetooth.Obex.Agent : GLib.Object {
	/* one confirmation for many files in one session */
	private ObjectPath many_files;

	public signal void response_notify(string address, ObjectPath object_path);
	public signal void response_accepted(string address, ObjectPath object_path);
	public signal void transfer_view(string session_path);
	public signal void response_canceled(ObjectPath? object_path = null);

	public Agent() {
		Bus.own_name(
			BusType.SESSION,
			"org.bluez.obex.Agent1",
			BusNameOwnerFlags.NONE,
			on_name_get
		);
	}

	private void on_name_get(DBusConnection conn) {
		try {
			conn.register_object("/org/bluez/obex/budgie", this);
		} catch (Error e) {
			error("Error registering DBus name: %s", e.message);
		}
	}

	public void transfer_active(string session_path) throws Error {
		transfer_view(session_path);
	}

	/**
	 * release:
	 *
	 * This method gets called when the service daemon
	 * unregisters the agent. An agent can use it to do
	 * cleanup tasks. There is no need to unregister the
	 * agent, because when this method gets called it has
	 * already been unregistered.
	 */
	public void release() throws Error {}

	/**
	 * authorize_push:
	 * @object_path: The path to a Bluez #Transfer object.
	 *
	 * This method gets called when the service daemon
	 * needs to accept/reject a Bluetooth object push request.
	 *
	 * Returns: The full path (including the filename) or the
	 * folder name suffixed with '/' where the object shall
	 * be stored. The transfer object will contain a Filename
	 * property that contains the default location and name
	 * that can be returned.
	 */
	public async string authorize_push(ObjectPath object_path) throws Error {
		SourceFunc callback = authorize_push.callback;
		BluezObexError? obex_error = null;
		Bluetooth.Obex.Transfer transfer = Bus.get_proxy_sync(BusType.SESSION, "org.bluez.obex", object_path);

		if (transfer.name == null) {
			throw new BluezObexError.REJECTED("File transfer rejected");
		}

		Bluetooth.Obex.Session session = Bus.get_proxy_sync(BusType.SESSION, "org.bluez.obex", transfer.session);

		// Register application action to accept a file transfer
		var accept_action = new SimpleAction("btaccept", VariantType.STRING);
		GLib.Application.get_default().add_action(accept_action);
		accept_action.activate.connect((parameter) => {
			response_accepted(session.destination, object_path);
			if (callback != null) {
				Idle.add((owned) callback);
			}
		});

		// Register application action to reject a file transfer
		var cancel_action = new SimpleAction("btcancel", VariantType.STRING);
		GLib.Application.get_default().add_action(cancel_action);
		cancel_action.activate.connect((parameter) => {
			obex_error = new BluezObexError.CANCELED("File transfer cancelled");
			response_canceled(object_path);
			if (callback != null) {
				Idle.add((owned) callback);
			}
		});

		// Automatically accept the transfer if there are multiple files for
		// the one transfer
		if (many_files == object_path) {
			Idle.add(()=>{
				response_accepted(session.destination, object_path);

				if (callback != null) {
					Idle.add((owned) callback);
				}

				return Source.REMOVE;
			});
		} else {
			// Not multple files, ask to accept or reject
			response_notify(session.destination, object_path);
		}

		yield;

		if (obex_error != null) throw obex_error;

		many_files = object_path;
		return transfer.name;
	}

	/**
	 * cancel:
	 *
	 * This method gets called to indicate that the agent
	 * request failed before a reply was returned. It cancels
	 * the previous request.
	 */
	public void cancel() throws Error {
		response_canceled();
	}
}
