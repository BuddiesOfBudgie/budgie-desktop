/*
 * This file is part of budgie-desktop
 *
 * Copyright © 2015-2022 Budgie Desktop Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

public class MprisRavenPlugin : Budgie.RavenPlugin, Peas.ExtensionBase {
	public Budgie.RavenWidget new_widget_instance(string uuid, GLib.Settings? settings) {
		return new MprisRavenWidget(uuid, settings);
	}

	public bool supports_settings() {
		return false;
	}
}

public class MprisRavenWidget : Budgie.RavenWidget {
	private MprisDBusImpl impl;

	private HashTable<string, MprisClientWidget> ifaces;
	private Gtk.Box? content = null;
	private Gtk.Label? placeholder = null;

	private int our_width = 250;

	public MprisRavenWidget(string uuid, GLib.Settings? settings) {
		initialize(uuid, settings);

		content = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
		add(content);

		placeholder = new Gtk.Label(_("Nothing is playing."));
		placeholder.get_style_context().add_class("raven-header");
		content.pack_start(placeholder, false, false, 0);

		ifaces = new HashTable<string,MprisClientWidget>(str_hash, str_equal);

		setup_dbus.begin();

		size_allocate.connect(on_size_allocate);
		show_all();
	}

	void on_size_allocate() {
		int w = get_allocated_width();
		if (w > our_width) {
			our_width = w;

			// Notify every client of the updated size. Idle needs to be used
			// to prevent any 'queue_resize' triggered from being ignored
			Idle.add(notify_clients_on_width_change);
		}
	}

	bool notify_clients_on_width_change() {
		var iter = HashTableIter<string,MprisClientWidget>(ifaces);
		MprisClientWidget? widget = null;
		while (iter.next(null, out widget)) {
			widget.update_width(our_width);
		}
		return false;
	}

	/**
	 * Add an interface handler/widget to known list and UI
	 *
	 * @param name DBUS name (object path)
	 * @param iface The constructed MprisClient instance
	 */
	void add_iface(string name, MprisClient iface) {
		MprisClientWidget widg = new MprisClientWidget(iface, our_width);
		widg.show_all();
		if (content.get_children().index(placeholder) != -1) {
			content.remove(placeholder);
		}
		content.pack_start(widg, false, false, 0);
		ifaces.insert(name, widg);
	}

	/**
	 * Destroy an interface handler and remove from UI
	 *
	 * @param name DBUS name to remove handler for
	 */
	void destroy_iface(string name) {
		var widg = ifaces[name];
		if (widg != null) {
			content.remove(widg);
			ifaces.remove(name);
		}

		if (ifaces.size() == 0) {
			content.pack_start(placeholder, false, false, 0);
		}
	}

	void on_name_owner_changed(string? n, string? o, string? ne) {
		if (!n.has_prefix("org.mpris.MediaPlayer2.")) {
			return;
		}
		if (o == "") {
			new_iface.begin(n, (o, r) => {
				var iface = new_iface.end(r);
				if (iface != null) {
					add_iface(n, iface);
				}
			});
		} else {
			Idle.add(() => {
				destroy_iface(n);
				return false;
			});
		}
	}

	/**
	 * Do basic dbus initialisation
	 */
	public async void setup_dbus() {
		try {
			impl = yield Bus.get_proxy(BusType.SESSION, "org.freedesktop.DBus", "/org/freedesktop/DBus");
			var names = yield impl.list_names();

			/* Search for existing players (launched prior to our start) */
			foreach (var name in names) {
				if (name.has_prefix("org.mpris.MediaPlayer2.")) {
					var iface = yield new_iface(name);
					if (iface != null) {
						add_iface(name, iface);
					}
				}
			}

			/* Also check for new mpris clients coming up while we're up */
			impl.name_owner_changed.connect(on_name_owner_changed);
		} catch (Error e) {
			warning("Failed to initialise dbus: %s", e.message);
		}
	}
}

[ModuleInit]
public void peas_register_types(TypeModule module) {
	// boilerplate - all modules need this
	var objmodule = module as Peas.ObjectModule;
	objmodule.register_extension_type(typeof(Budgie.RavenPlugin), typeof(MprisRavenPlugin));
}
