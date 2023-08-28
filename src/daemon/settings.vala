/*
 * This file is part of budgie-desktop
 *
 * Copyright © Budgie Desktop Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

namespace Budgie {
	[DBus (name="org.gnome.SettingsDaemon.Power.Screen")]
	interface PowerScreen : GLib.Object {
		public abstract int32 brightness {owned get; set;}
	}

	/**
	* The button layout style as set in budgie
	*/
	public enum ButtonPosition {
		LEFT = 1 << 0,
		TRADITIONAL = 1 << 1,
	}
	/**
	* The SettingsManager currently only has a very simple job, and looks for
	* session wide settings changes to respond to
	*/
	public class SettingsManager {
		private unowned Application? _parent_app = null;
		public unowned Application parent_app {
			get { return _parent_app; }
			set { _parent_app = value; }
		}

		/**
		* All the settings
		*/
		private Settings? mutter_settings = null;
		private Settings? gnome_desktop_settings = null;
		private Settings? gnome_power_settings = null;
		private PowerScreen? gnome_power_props = null;
		private Settings? gnome_session_settings = null;
		private Settings? gnome_sound_settings = null;
		private Settings? gnome_wm_settings = null;
		private Settings? raven_settings = null;
		private Settings? wm_settings = null;
		private Settings? xoverrides = null;

		/**
		* Defaults for Caffeine Mode
		*/
		private int32? default_brightness = 30;
		private uint32? default_idle_delay = 0;
		private bool? default_idle_dim = false;
		private int? default_sleep_inactive_ac_timeout = 0;
		private int? default_sleep_inactive_battery_timeout = 0;

		/**
		* Other
		*/
		private string? caffeine_full_cup = "";
		private string? caffeine_empty_cup = "";
		private Notify.Notification? caffeine_notification = null;
		private bool temporary_notification_disabled = false;

		public SettingsManager() {
			set_supported_caffeine_icons(); // Set supported Caffeine icons will determine whether or not to use an IconTheme or Budgie caffeine icons

			/* Settings we need to write to */
			mutter_settings = new Settings("org.gnome.mutter");
			gnome_desktop_settings = new Settings("org.gnome.desktop.interface");
			gnome_power_settings = new Settings("org.gnome.settings-daemon.plugins.power");
			gnome_session_settings = new Settings("org.gnome.desktop.session");
			gnome_sound_settings = new Settings("org.gnome.desktop.sound");
			gnome_wm_settings = new Settings("org.gnome.desktop.wm.preferences");
			raven_settings = new Settings("com.solus-project.budgie-raven");
			xoverrides = new Settings("org.gnome.settings-daemon.plugins.xsettings");
			wm_settings = new Settings("com.solus-project.budgie-wm");

			try {
				gnome_power_props = Bus.get_proxy_sync(BusType.SESSION, "org.gnome.SettingsDaemon.Power", "/org/gnome/SettingsDaemon/Power");
			} catch (IOError e) {
				warning("Failed to acquire bus for org.gnome.SettingsDaemon.Power: %s\n", e.message);
			}

			fetch_defaults();

			enforce_mutter_settings(); // Call enforce mutter settings so we ensure we transition our Mutter settings over to BudgieWM
			raven_settings.changed["allow-volume-overdrive"].connect(this.on_raven_sound_overdrive_change);

			gnome_session_settings.changed["idle-delay"].connect(this.update_idle_delay);
			gnome_power_settings.changed["idle-dim"].connect(this.update_idle_dim);
			gnome_power_settings.changed["sleep-inactive-ac-timeout"].connect(this.update_ac_timeout);
			gnome_power_settings.changed["sleep-inactive-battery-timeout"].connect(this.update_battery_timeout);

			wm_settings.changed.connect(this.on_wm_settings_changed);
			this.on_wm_settings_changed("button-style");
		}

		/**
		* caffeine_settings_sync will call to sync / ensure write operations for session and power, which are relevant to Caffeine Mode
		*/
		private void caffeine_settings_sync() {
			gnome_session_settings.apply();
			gnome_power_settings.apply();
			Settings.sync(); // Ensure write operations are complete for session
			Settings.sync(); // Ensure write operations are complete for power
		}

		/**
		* change_brightness will attempt to change our brightness in the power properties
		*/
		private void change_brightness(int32 value) {
			if (this.gnome_power_props != null) {
				try {
					this.gnome_power_props.brightness = value;
				} catch {
					warning("Error: Failed to change change the brightness during Caffeine Mode toggle.");
				}
			}
		}

		/**
		* do_disable is triggered when our timeout is called
		*/
		private bool do_disable() {
			if (get_caffeine_mode()) { // Is still disabled by the time our timer gets triggered
				wm_settings.set_boolean("caffeine-mode", false);
				Settings.sync();
				reset_values(); // Immediately reset values
			}

			return false;
		}

		/**
		* do_disable_quietly will quietly disable Caffeine Mode
		*/
		public void do_disable_quietly() {
			temporary_notification_disabled = true;
			wm_settings.set_boolean("caffeine-mode", false);
			Settings.sync();
			reset_values(); // Immediately reset values
		}

		/**
		* enforce_mutter_settings will apply Mutter schema changes to BudgieWM for supported keys
		*/
		private void enforce_mutter_settings() {
			bool center_windows = mutter_settings.get_boolean("center-new-windows");
			wm_settings.set_boolean("center-windows", center_windows);
		}


		/**
		* fetch_defaults will fetch the default values for various idle, sleep, and brightness settings
		*/
		private void fetch_defaults() {
			if (get_caffeine_mode()) { // If Caffeine Mode was somehow left on during startup, we can't trust what we'll get for keys
				gnome_session_settings.reset("idle-delay");
				gnome_power_settings.reset("idle-dim");
				gnome_power_settings.reset("sleep-inactive-ac-timeout");
				gnome_power_settings.reset("sleep-inactive-battery-timeout");
				caffeine_settings_sync();

				temporary_notification_disabled = true;
				wm_settings.set_boolean("caffeine-mode", false); // Ensure Caffeine Mode is disabled by default
				Settings.sync();
			}

			get_power_defaults(); // Get our sleep ac and battery timeout defaults

			if (gnome_power_props != null) {
				try {
					default_brightness = gnome_power_props.brightness;
				} catch {
					warning("Could not set default value.");
				}
			}
		}

		/**
		* get_caffeine_mode will get the current Caffeine Mode status
		*/
		private bool get_caffeine_mode() {
			return wm_settings.get_boolean("caffeine-mode");
		}

		/**
		* get_power_defaults will call all of our update defaults functions
		*/
		private void get_power_defaults() {
			update_ac_timeout();
			update_battery_timeout();
			update_idle_delay();
			update_idle_dim();
		}

		/**
		* Create a new xsettings override based on the *Existing* key so that
		* we don't dump any settings like Gdk/ScaleFactor, etc.
		*/
		private Variant? new_filtered_xsetting(string button_layout) {
			/* These are the two new keys we want */
			var builder = new VariantBuilder(new VariantType("a{sv}"));
			builder.add("{sv}", "Gtk/ShellShowsAppMenu", new Variant.int32(0));
			builder.add("{sv}", "Gtk/DecorationLayout", new Variant.string(button_layout));

			Variant existing_vars = this.xoverrides.get_value("overrides");
			VariantIter it = existing_vars.iterator();
			string? k = null;
			Variant? v = null;
			while (it.next("{sv}", &k, &v)) {
				if (k == "Gtk/ShellShowsAppMenu" || k == "Gtk/DecorationLayout") {
					continue;
				}
				builder.add("{sv}", k, v);
			}
			return builder.end();
		}

		private void on_raven_sound_overdrive_change() {
			bool allow_volume_overdrive = raven_settings.get_boolean("allow-volume-overdrive"); // Get our overdrive value
			gnome_sound_settings.set_boolean("allow-volume-above-100-percent", allow_volume_overdrive); // Set it to allow-volume-above-100-percent
		}

		private void on_wm_settings_changed(string key) {
			switch (key) {
				case "attach-modal-dialogs": // Changed via Budgie Desktop Settings
					bool attach = wm_settings.get_boolean(key); // Get our attach value
					mutter_settings.set_boolean("attach-modal-dialogs", attach); // Update GNOME WM settings
					break;
				case "button-style":
					ButtonPosition style = (ButtonPosition)wm_settings.get_enum(key);
					this.set_button_style(style);
					break;
				case "center-windows":
					bool center = wm_settings.get_boolean(key);
					mutter_settings.set_boolean("center-new-windows", center);
					break;
				case "caffeine-mode":
					bool enabled = wm_settings.get_boolean(key); // Get the caffeine mode enabled value
					this.set_caffeine_mode(enabled);
					break;
				case "edge-tiling": // Changed via Budgie Desktop Settings
					bool edge_setting = wm_settings.get_boolean(key); // Get our edge tiling setting
					mutter_settings.set_boolean("edge-tiling", edge_setting); // // Update GNOME WM settings
					break;
				case "focus-mode":
					bool mode = wm_settings.get_boolean(key);
					this.set_focus_mode(mode);
					break;
				default:
					break;
			}
		}

		/**
		* reset_values will reset select power and session keys
		*/
		private void reset_values() {
			gnome_session_settings.set_uint("idle-delay", default_idle_delay);
			gnome_power_settings.set_boolean("idle-dim", default_idle_dim);
			gnome_power_settings.set_int("sleep-inactive-ac-timeout", default_sleep_inactive_ac_timeout);
			gnome_power_settings.set_int("sleep-inactive-battery-timeout", default_sleep_inactive_battery_timeout);
			caffeine_settings_sync();
		}

		/**
		* Set the button layout to one of left or traditional
		*/
		void set_button_style(ButtonPosition style) {
			Variant? xset = null;
			string? wm_set = null;

			switch (style) {
			case ButtonPosition.LEFT:
				xset = this.new_filtered_xsetting("close,minimize,maximize:menu");
				wm_set = "close,minimize,maximize:appmenu";
				break;
			case ButtonPosition.TRADITIONAL:
			default:
				xset = this.new_filtered_xsetting("menu:minimize,maximize,close");
				wm_set = "appmenu:minimize,maximize,close";
				break;
			}

			this.xoverrides.set_value("overrides", xset);
			this.wm_settings.set_string("button-layout", wm_set);
			this.gnome_wm_settings.set_value("button-layout", wm_set);
		}

		/**
		* set_caffeine_mode will set our various settings for caffeine mode
		*/
		private void set_caffeine_mode(bool enabled, bool disable_notification = false) {
			if (enabled) { // Enable Caffeine Mode
				gnome_power_settings.set_boolean("idle-dim", false);
				gnome_power_settings.set_int("sleep-inactive-ac-timeout", 0);
				gnome_power_settings.set_int("sleep-inactive-battery-timeout", 0);
				gnome_session_settings.set_uint("idle-delay", 0);
				caffeine_settings_sync();
			} else { // Disable Caffeine Mode
				if (gnome_session_settings.has_unapplied || gnome_power_settings.has_unapplied) { // There are unapplied settings
					Timeout.add_seconds(1, () => { // Delay reset a moment
						if (!gnome_session_settings.has_unapplied && !gnome_power_settings.has_unapplied) { // No longer unapplied settings
							reset_values();
							return false;
						} else { // Still unapplied, try again in a moment
							return true;
						}
					}, Priority.HIGH);
				} else {
					reset_values(); // Reset the values
				}
			}

			if (wm_settings.get_boolean("caffeine-mode-toggle-brightness")) { // Should toggle brightness
				int32 set_brightness = (int32) wm_settings.get_int("caffeine-mode-screen-brightness");
				change_brightness((enabled) ? set_brightness : default_brightness);
			}

			var time = wm_settings.get_int("caffeine-mode-timer"); // Get our timer number
			if (enabled && (time > 0)) { // If Caffeine Mode is enabled and we'll turn it off in a certain amount of time
				Timeout.add_seconds(time * 60, this.do_disable, Priority.HIGH);
				Timeout.add_seconds(60, () => {
					var countdown = wm_settings.get_int("caffeine-mode-timer");
					if (countdown != 0) {
						countdown -= 1;
						wm_settings.set_int("caffeine-mode-timer", countdown);
					}

					return (countdown != 0);
				});
			}

			if (wm_settings.get_boolean("caffeine-mode-notification") && !disable_notification && !temporary_notification_disabled && Notify.is_initted()) { // Should show a notification
				string title = (enabled) ? _("Turned on Caffeine Boost") : _("Turned off Caffeine Boost");
				string body = "";
				string icon = (enabled) ? caffeine_full_cup : caffeine_empty_cup;

				if (enabled && (time > 0)) {
					body = ngettext("Will turn off in a minute", "Will turn off in %d minutes", time).printf(time);
				}

				if (this.caffeine_notification == null) { // Caffeine Notification not yet created
					this.caffeine_notification = new Notify.Notification(title, body, icon);
					caffeine_notification.set_urgency(Notify.Urgency.CRITICAL);
				} else {
					try {
						this.caffeine_notification.close(); // Ensure previous is closed
					} catch (Error e) {
						warning("Failed to close previous notification: %s", e.message);
					}

					this.caffeine_notification.update(title, body, icon); // Update the Notification
				}

				try {
					this.caffeine_notification.show();
				} catch (Error e) {
					warning("Failed to send our Caffeine notification: %s", e.message);
				}
			}

			if (temporary_notification_disabled) { // If we've temporarily disabled the Notification (such as for not providing a notification during End Session DIalog opening)
				Timeout.add_seconds(60, () => { // Wait about a minute
					temporary_notification_disabled = false; // Turn back off
					return false;
				}, Priority.HIGH);
			}
		}

		/**
		* set_focus_mode will set the window focus mode
		*/
		void set_focus_mode(bool enable) {
			string gfocus_mode = "click";
			int raise_delay = (enable) ? 0 : 250; // Set auto raise to be instant on mouse move, 250ms on click

			if (enable) {
				gfocus_mode = "mouse";
			}

			this.gnome_wm_settings.set_value("focus-mode", gfocus_mode);
			this.gnome_wm_settings.set_boolean("auto-raise", enable); // Enable auto-raising on mouse move. This ensures windows are more reliably brought into focus
			this.gnome_wm_settings.set_int("auto-raise-delay", raise_delay); // Set our auto-raise-delay to improve perceived performance on focus changes
		}

		/**
		* set_supported_caffeine_icons will determine whether or not to use the current IconTheme's caffeine icons, if supported.
		* If it is not supported, it will fall back to our budgie vendored icons.
		*/
		private void set_supported_caffeine_icons() {
			Gtk.IconTheme current_theme = Gtk.IconTheme.get_default();
			string full = "caffeine-cup-full";
			string empty = "caffeine-cup-empty";
			caffeine_full_cup = current_theme.has_icon(full) ? full : "budgie-" + full;
			caffeine_empty_cup = current_theme.has_icon(empty) ? empty : "budgie-" + empty;
		}

		/**
		* update_ac_timeout will update our default sleep inactive ac timeout value, if it is a non-Caffeine mode value
		*/
		private void update_ac_timeout() {
			int current_ac_timeout = gnome_power_settings.get_int("sleep-inactive-ac-timeout");

			if ((current_ac_timeout != 0) || ((current_ac_timeout == 0) && !get_caffeine_mode())) { // Is a non-Caffeine value or is already set to 0 when Caffeine Mode is off
				default_sleep_inactive_ac_timeout = current_ac_timeout;
			}
		}

		/**
		* update_battery_timeout will update our default sleep inactive battery timeout, if it is a non-Caffeine mode value
		*/
		private void update_battery_timeout() {
			int current_battery_timeout = gnome_power_settings.get_int("sleep-inactive-battery-timeout");

			if ((current_battery_timeout != 0) || ((current_battery_timeout == 0) && !get_caffeine_mode())) { // Is a non-Caffeine value or is already set to 0 when Caffeine Mode is off
				default_sleep_inactive_battery_timeout = current_battery_timeout;
			}
		}

		/**
		* update_idle_delay will update our default idle delay, if it is a non-Caffeine mode value
		*/
		private void update_idle_delay() {
			uint current_idle_delay = gnome_session_settings.get_uint("idle-delay");

			if ((current_idle_delay != 0) || ((current_idle_delay == 0) && !get_caffeine_mode())) { // Is a non-Caffeine value or is already set to 0 when Caffeine Mode is off
				default_idle_delay = current_idle_delay;
			}
		}

		/**
		* update_idle_dim will update our default idle dim, if we are not in Caffeine Mode
		*/
		private void update_idle_dim() {
			if (!get_caffeine_mode()) { // If Caffeine Mode is off
				default_idle_dim = gnome_power_settings.get_boolean("idle-dim");
			}
		}
	}
}
