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

 namespace Budgie {

	[DBus (name = "org.budgie_desktop.BudgieOSD")]
	interface ShowOSD : GLib.Object {
		public abstract async void ShowOSD(HashTable<string,Variant> params) throws DBusError, IOError;
	}

	/*
	  Controls the OSD for various controllable items
	  volume
	  brightness
	  caps-lock
	  num-lock
	 */
	class OSDKeys : Object {

		// vars for the brightness handling
		GLib.DBusConnection conn = null;
		uint signal_id;
		ShowOSD osd = null;
		double current_brightness_level = 0.0;

		// vars for the caps/numlock changes
		unowned Gdk.Keymap? map;
		bool capslock;
		bool numlock;
		bool firstrun = false;

		// vars for the volume changes
		private Gvc.MixerControl? mixer;
		private Gvc.MixerStream? stream;
		private ulong notify_id;

		// need to handle initialisation of various methods so ensure the OSD is not accidently
		// activated when budgie-daemon is started.
		private bool initialising;

		public OSDKeys() {
			initialising = true;
			try {
				osd = Bus.get_proxy_sync (BusType.SESSION, "org.budgie_desktop.BudgieOSD",
															"/org/budgie_desktop/BudgieOSD");

			} catch (Error e) {
				warning("%s\n", e.message);
			}

			try {
				conn = Bus.get_sync(GLib.BusType.SESSION, null);
			}
			catch(IOError e) {
				info("%s", e.message);
			}

			signal_id = conn.signal_subscribe("org.gnome.SettingsDaemon.Power",
											  "org.freedesktop.DBus.Properties",
											  "PropertiesChanged", null, null,
											  DBusSignalFlags.NONE,
											  signal_powerchanges);

			mixer = new Gvc.MixerControl("BD Volume Mixer");
			mixer.state_changed.connect(on_mixer_state_change);
			mixer.default_sink_changed.connect(on_mixer_sink_changed);
			mixer.open();

			// wait a short while to allow the async mixer methods to complete otherwise
			// we see the volume OSD on startup accidently when keymap changes are invoked
			Timeout.add(200, () => {
				initialising = false;
				map = Gdk.Keymap.get_for_display(Gdk.Display.get_default());
				map.state_changed.connect(on_keymap_state_changed);
				return false;
			});
		}

		void on_mixer_sink_changed(uint id) {
			set_default_mixer();
		}

		void set_default_mixer() {
			if (stream != null) {
				SignalHandler.disconnect(stream, notify_id);
			}

			stream = mixer.get_default_sink();
			notify_id = stream.notify.connect(on_stream_notify);
			update_volume();
		}

		void on_stream_notify(Object? o, ParamSpec? p) {
			if (p.name == "volume" || p.name == "is-muted") {
				update_volume();
			}
		}

		/**
		 * Called when something changes on the mixer, i.e. we connected
		 * This is where we hook into the stream for changes
		 */
		void on_mixer_state_change(uint new_state) {
			if (new_state == Gvc.MixerControlState.READY) {
				set_default_mixer();
			}
		}

		/**
		* Update the OSD when something changes (volume/mute)
		*/
		void update_volume() {
			if (initialising) return;

			var vol_norm = mixer.get_vol_max_norm();
			var vol = stream.get_volume();

			/* Same maths as computed by volume.js in gnome-shell, carried over
			* from C->Vala port of budgie-panel */
			int n = (int) Math.floor(3*vol/vol_norm)+1;
			string image_name;

			// Work out an icon
			if (stream.get_is_muted() || vol <= 0) {
				image_name = "audio-volume-muted-symbolic";
			} else {
				switch (n) {
					case 1:
						image_name = "audio-volume-low-symbolic";
						break;
					case 2:
						image_name = "audio-volume-medium-symbolic";
						break;
					default:
						image_name = "audio-volume-high-symbolic";
						break;
				}
			}

			var pct = (float)vol / (float)vol_norm;
			if (pct > 1.0 && !stream.get_is_muted()) {
				image_name = "audio-volume-overamplified-symbolic";
			}

			HashTable<string,Variant> params;
			params = new HashTable<string,Variant>(null, null);
			params.set("level", new Variant.double(pct));
			params.set("icon", new Variant.string(image_name));

			osd.ShowOSD.begin(params);
		}

		/*
		  we allow Gtk keymap to control when to display capslock/numlock state
		  It does appear though that there is a bug under wayland where the
		  state of the capslock/numlock is not set until another keymap is activated
		  This can be ctrl/shift as well as the caps/numlock. If the latter is activated
		  this can mean the OSD for keymap state is not activated on first use; only on
		  subsequent keypresses.
		 */
		private void on_keymap_state_changed() {
			if (!firstrun) {
				capslock = map.get_caps_lock_state();
				numlock = map.get_num_lock_state();
				firstrun = true;
			}

			HashTable<string,Variant> params = new HashTable<string,Variant>(null, null);
			string caption = "";
			bool skip = false;
			if (map.get_caps_lock_state()) {
				if (!capslock) {
				params.set("icon", new Variant.string("caps-lock-symbolic"));
					caption = _("Caps Lock is on");
					params.set("icon", new Variant.string("caps-lock-on-symbolic"));
				}
				capslock = true;
				skip = true;
			} else {
				if (capslock) {
					caption = _("Caps Lock is off");
					params.set("icon", new Variant.string("caps-lock-off-symbolic"));
				}
				capslock = false;
				skip = true;
			}

			if (!skip) {
				if (map.get_num_lock_state()) {
					if (!numlock) {
						caption = _("Num Lock is on");
						params.set("icon", new Variant.string("num-lock-on-symbolic"));
					}
					numlock = true;
				} else {
					if (numlock) {
						caption = _("Num Lock is off");
						params.set("icon", new Variant.string("num-lock-off-symbolic"));
					}
					numlock = false;
				}
			}

			if (caption != "") {
				params.set("label", new Variant.string(caption));
				osd.ShowOSD.begin(params);
			}
		}

		private void signal_powerchanges(GLib.DBusConnection connection,
										 string? sender_name,
										 string object_path,
										 string interface_name,
										 string signal_name,
										 GLib.Variant parameters) {
			if (initialising) return;

			GLib.VariantDict dict = new GLib.VariantDict(parameters.get_child_value(1));
			GLib.Variant? brightness = dict.lookup_value("Brightness", GLib.VariantType.INT32);
			if (brightness == null || Screenlock.is_dimming) {
				return;
			}

			double level = (double) brightness.get_int32() / 100;
			// nothing has changed therefore quit
			// i.e. GSD power can and does signal more than just brightness changes
			if (current_brightness_level == level) return;

			current_brightness_level = level;

			string icon = "display-brightness-symbolic";
			if (level == 1.0) {
				icon = "display-brightness-high-symbolic";
			} else if (level == 0.0) {
				icon = "display-brightness-low-symbolic";
			}

			HashTable<string,Variant> params;
			params = new HashTable<string,Variant>(null, null);
			params.set("level", new Variant.double(level));
			params.set("icon", new Variant.string(icon));

			osd.ShowOSD.begin(params);
		}
	}
 }
