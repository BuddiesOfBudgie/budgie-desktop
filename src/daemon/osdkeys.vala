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
		public abstract async void Show(HashTable<string,Variant> params) throws DBusError, IOError;
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
		ShowOSD osd = null;
		private BrightnessManager? brightness_manager = null;

		// vars for the caps/numlock changes
		unowned Gdk.Keymap? map;
		bool capslock;
		bool numlock;
		bool firstrun = false;

		// vars for the volume changes
		private Gvc.MixerControl? mixer;
		private Gvc.MixerStream? stream;
		private ulong notify_id;

		// var for wm settings changes
		private Settings? wm_settings = null;
		private bool caffeine_was_enabled = false;

		// need to handle initialisation of various methods so ensure the OSD is not accidently
		// activated when budgie-daemon is started.
		private bool initialising;

		/**
		 * Set up connection to OSD service with retry logic
		 */
		private async void setup_osd_proxy() {
			int retry_count = 0;
			const int MAX_RETRIES = 10;
			const int RETRY_DELAY_MS = 1000;

			while (retry_count < MAX_RETRIES) {
				try {
					debug("Attempting to connect to BudgieOSD service (attempt %d/%d)",
						retry_count + 1, MAX_RETRIES);

					osd = yield Bus.get_proxy(
						BusType.SESSION,
						"org.budgie_desktop.BudgieOSD",
						"/org/budgie_desktop/BudgieOSD"
					);

					debug("Successfully connected to BudgieOSD service");
					return;

				} catch (Error e) {
					retry_count++;
					if (retry_count >= MAX_RETRIES) {
						warning("Failed to connect to BudgieOSD after %d attempts: %s",
							MAX_RETRIES, e.message);
						return;
					}

					warning("Failed to connect to BudgieOSD (attempt %d/%d): %s, retrying...",
						retry_count, MAX_RETRIES, e.message);

					// Wait before retrying
					Timeout.add(RETRY_DELAY_MS, () => {
						setup_osd_proxy.begin();
						return false;
					});
					return;
				}
			}
		}

		public OSDKeys() {
			initialising = true;

			// Connect to OSD service asynchronously with retry logic
			setup_osd_proxy.begin();

			// Initialize brightness manager
			debug("Creating BrightnessManager...");
			brightness_manager = new BrightnessManager();

			// Connect to ready signal to know when it's actually available
			brightness_manager.ready.connect(() => {
				debug("BrightnessManager is ready");
				if (brightness_manager.is_available()) {
					brightness_manager.brightness_changed.connect(on_brightness_changed);
					debug("Connected to brightness_changed signal");
				} else {
					warning("BrightnessManager not available after initialization");
				}
			});

			// Also check if it's already ready (in case ready() fired before we connected)
			if (brightness_manager.is_ready) {
				debug("BrightnessManager already ready");
				if (brightness_manager.is_available()) {
					brightness_manager.brightness_changed.connect(on_brightness_changed);
					debug("Connected to brightness_changed signal");
				}
			}

			mixer = new Gvc.MixerControl("BD Volume Mixer");
			mixer.state_changed.connect(on_mixer_state_change);
			mixer.default_sink_changed.connect(on_mixer_sink_changed);
			mixer.open();

			// wait a short while to allow the async mixer methods to complete otherwise
			// we see the volume OSD on startup accidently when keymap changes are invoked
			Timeout.add(200, () => {
				initialising = false;
				debug("Initialization complete");
				map = Gdk.Keymap.get_for_display(Gdk.Display.get_default());
				map.state_changed.connect(on_keymap_state_changed);
				return false;
			});

			wm_settings = new Settings("com.solus-project.budgie-wm");
			wm_settings.changed["caffeine-mode"].connect(on_caffeine_mode);
		}

		/**
		 * Called when brightness changes
		 */
		private void on_brightness_changed(double level) {
			debug("Brightness changed to %.2f%% (initialising=%s, dimming=%s, caffeine=%s, osd=%s)",
				level * 100,
				initialising ? "true" : "false",
				Screenlock.is_dimming ? "true" : "false",
				caffeine_was_enabled ? "true" : "false",
				osd != null ? "connected" : "null");

			if (initialising || Screenlock.is_dimming || caffeine_was_enabled) {
				warning("Skipping brightness OSD (initializing or dimming or caffeine)");
				return;
			}

			if (osd == null) {
				warning("Skipping brightness OSD (OSD service not connected yet)");
				return;
			}

			string icon = "display-brightness-symbolic";
			if (level >= 0.9) {
				icon = "display-brightness-high-symbolic";
			} else if (level <= 0.1) {
				icon = "display-brightness-low-symbolic";
			}

			HashTable<string,Variant> params;
			params = new HashTable<string,Variant>(null, null);
			params.set("level", new Variant.double(level));
			params.set("icon", new Variant.string(icon));

			debug("Showing brightness OSD with icon=%s, level=%.2f", icon, level);
			osd.Show.begin(params);
		}

		/* handle brightness changes due to caffeine mode - we
		    don't want the brightness OSD to display when caffeine with brightness
			changes is enabled
		*/
		void on_caffeine_mode() {
			if (wm_settings.get_boolean("caffeine-mode")) {
				caffeine_was_enabled = true;
				debug("Caffeine mode enabled");
				return;
			}

			/* switching caffeine mode on/off invokes a series of events that can
			   inadvertently trigger the brightness OSD.  We workaround this
			   by letting caffeine events to complete first
			*/
			debug("Caffeine mode disabled, waiting for events to settle...");
			Timeout.add(1000, () => {
				caffeine_was_enabled = false;
				debug("Caffeine mode fully disabled");
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

			if (osd == null) {
				warning("Skipping volume OSD (OSD service not connected yet)");
				return;
			}

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

			osd.Show.begin(params);
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

			if (osd == null) {
				return;  // OSD service not ready yet
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
				osd.Show.begin(params);
			}
		}
	}
 }
