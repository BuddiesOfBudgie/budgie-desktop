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

public class MediaControlsRavenPlugin : Budgie.RavenPlugin, Peas.ExtensionBase {
	public Budgie.RavenWidget new_widget_instance(string uuid, GLib.Settings? settings) {
		return new MediaControlsRavenWidget(uuid, settings);
	}

	public bool supports_settings() {
		return false;
	}
}

public class MediaControlsRavenWidget : Budgie.RavenWidget {
	private MprisTracker mpris_tracker;

	private HashTable<string, MprisClientWidget> widgets;
	private Gtk.Box? content = null;
	private StartListening? placeholder = null;

	private int our_width = 250;

	public MediaControlsRavenWidget(string uuid, GLib.Settings? settings) {
		initialize(uuid, settings);

		content = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
		add(content);

		placeholder = new StartListening();
		placeholder.get_style_context().add_class("raven-header");
		content.pack_start(placeholder, false, false, 0);

		widgets = new HashTable<string, MprisClientWidget>(str_hash, str_equal);

		// Use the shared MprisTracker
		mpris_tracker = new MprisTracker();
		mpris_tracker.client_added.connect(on_client_added);
		mpris_tracker.client_removed.connect(on_client_removed);

		size_allocate.connect(on_size_allocate);
		show_all();
	}

	private void on_size_allocate() {
		int w = get_allocated_width();
		if (w > our_width) {
			our_width = w;

			// Notify every client of the updated size. Idle needs to be used
			// to prevent any 'queue_resize' triggered from being ignored
			Idle.add(notify_clients_on_width_change);
		}
	}

	private bool notify_clients_on_width_change() {
		var iter = HashTableIter<string, MprisClientWidget>(widgets);
		MprisClientWidget? widget = null;
		while (iter.next(null, out widget)) {
			widget.update_width(our_width);
		}
		return false;
	}

	private void on_client_added(MprisClient client) {
		var widget = new MprisClientWidget(client, our_width);
		widget.show_all();

		if (content.get_children().index(placeholder) != -1) {
			content.remove(placeholder);
		}

		content.pack_start(widget, false, false, 0);
		widgets.insert(client.bus_name, widget);
	}

	private void on_client_removed(MprisClient client) {
		var widget = widgets.lookup(client.bus_name);
		if (widget != null) {
			content.remove(widget);
			widgets.remove(client.bus_name);
		}

		if (widgets.size() == 0) {
			content.pack_start(placeholder, false, false, 0);
		}
	}
}

private class StartListening : Gtk.Box {
	private AppInfo? music_app = null; // Our current default music player that handles audio/ogg
	private bool has_music_player; // Private bool of whether or not we have a music player installed
	private Gtk.Button start_listening; // Our button to start listening to music

	public StartListening() {
		Object(orientation: Gtk.Orientation.VERTICAL, spacing: 8);

		var label = new Gtk.Label(_("No apps are currently playing audio.")) {
			wrap = true,
			wrap_mode = Pango.WrapMode.WORD_CHAR,
			max_width_chars = 1,
			justify = Gtk.Justification.CENTER,
			hexpand = true,
		};
		label.margin_top = 4;

		start_listening = new Gtk.Button.with_label(_("Play some music"));
		start_listening.halign = Gtk.Align.CENTER;
		start_listening.margin_bottom = 4;
		start_listening.hexpand = false;

		pack_start(label, false, false, 0);
		pack_start(start_listening, false, false, 0);

		var monitor = AppInfoMonitor.get(); // Get our AppInfoMonitor, which monitors the app info database for changes
		monitor.changed.connect(check_music_support); // Recheck music support

		start_listening.clicked.connect(launch_music_player);

		check_music_support(); // Do our initial check
	}

	/*
	* check_music_support will check if we have an application that supports vorbis.
	* We're checking for vorbis since it's more likely the end user has open source vorbis support than alternative codecs like MP3
	*/
	private void check_music_support() {
		music_app = AppInfo.get_default_for_type("audio/vorbis", false);
		has_music_player = (music_app != null);
		start_listening.set_visible(has_music_player); // Set the visibility of the button based on if we have a music player
	}

	private void launch_music_player() {
		if (music_app == null) {
			return;
		}

		try {
			music_app.launch(null, null);
		} catch (Error e) {
			warning("Unable to launch %s: %s", music_app.get_name(), e.message);
		}
	}
}

[ModuleInit]
public void peas_register_types(TypeModule module) {
	// boilerplate - all modules need this
	var objmodule = module as Peas.ObjectModule;
	objmodule.register_extension_type(typeof(Budgie.RavenPlugin), typeof(MediaControlsRavenPlugin));
}
