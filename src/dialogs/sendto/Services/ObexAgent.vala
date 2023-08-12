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

[DBus (name = "org.bluez.obex.Error")]
public errordomain BluezObexError {
    REJECTED,
    CANCELED
}

[DBus (name = "org.bluez.obex.Agent1")]
public class Bluetooth.Obex.Agent : GLib.Object {
	/*one confirmation for many files in one session */
    private GLib.ObjectPath many_files;

    public signal void response_notify(string address, GLib.ObjectPath objectpath);
    public signal void response_accepted(string address, GLib.ObjectPath objectpath);
    public signal void transfer_view(string session_path);
    public signal void response_canceled();

    public Agent() {
        Bus.own_name(
            BusType.SESSION,
            "org.bluez.obex.Agent1",
            GLib.BusNameOwnerFlags.NONE,
            on_name_get
        );
    }

	private void on_name_get(GLib.DBusConnection conn) {
		try {
			conn.register_object ("/org/bluez/obex/budgie", this);
		} catch (Error e) {
			error (e.message);
		}
	}

    public void transfer_active(string session_path) throws GLib.Error {
        transfer_view(session_path);
    }

    public void release() throws GLib.Error {}

    public async string authorize_push(GLib.ObjectPath objectpath) throws Error {
        SourceFunc callback = authorize_push.callback;
        BluezObexError? obex_error = null;
        Bluetooth.Obex.Transfer transfer = Bus.get_proxy_sync(BusType.SESSION, "org.bluez.obex", objectpath);

        if (transfer.name == null) {
            throw new BluezObexError.REJECTED("Authorize Reject");
        }

        Bluetooth.Obex.Session session = Bus.get_proxy_sync(BusType.SESSION, "org.bluez.obex", transfer.session);
        var accept_action = new SimpleAction("btaccept", VariantType.STRING);
        GLib.Application.get_default().add_action(accept_action);
        accept_action.activate.connect((parameter) => {
            response_accepted(session.destination, objectpath);
            if (callback != null) {
                Idle.add((owned) callback);
            }
        });

        var cancel_action = new SimpleAction("btcancel", VariantType.STRING);
        GLib.Application.get_default().add_action(cancel_action);
        cancel_action.activate.connect((parameter) => {
            obex_error = new BluezObexError.CANCELED("Authorize Cancel");
            response_canceled();
            if (callback != null) {
                Idle.add((owned) callback);
            }
        });

        if (many_files == objectpath) {
            Idle.add(()=>{
                response_accepted(session.destination, objectpath);
                if (callback != null) {
                    Idle.add((owned) callback);
                }
                return GLib.Source.REMOVE;
            });
        } else {
            response_notify(session.destination, objectpath);
        }

        yield;

        if (obex_error != null) throw obex_error;

        many_files = objectpath;
        return transfer.name;
    }

    public void cancel() throws GLib.Error {
        response_canceled();
    }
}
