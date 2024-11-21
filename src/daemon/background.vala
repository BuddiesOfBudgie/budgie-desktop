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
	public const string BACKGROUND_SCHEMA = "org.gnome.desktop.background";
	public const string ACCOUNTS_SCHEMA = "org.freedesktop.Accounts";
	public const string GNOME_COLOR_HACK = "budgie-control-center/pixmaps/noise-texture-light.png";

	public class Background  {
		private Settings? settings = null;

		const int BACKGROUND_TIMEOUT = 850;

		/* Ensure we're efficient with changed queries and dont update
		* a bunch of times
		*/
		Gnome.BG? gnome_bg;
		Subprocess? bg = null;

		/**
		* Determine if the wallpaper is a colour wallpaper or not
		*/
		private bool is_color_wallpaper(string bg_filename) {
			if (gnome_bg.get_placement() == GDesktop.BackgroundStyle.NONE || bg_filename.has_suffix(GNOME_COLOR_HACK)) {
				return true;
			}
			return false;
		}

		public Background() {
			settings = new Settings(BACKGROUND_SCHEMA);
			gnome_bg = new Gnome.BG();

			/* If the background keys change, proxy it to libgnomedesktop */
			settings.change_event.connect(() => {
				gnome_bg.load_from_preferences(this.settings);
				return false;
			});

			gnome_bg.changed.connect(() => {
				this.update();
			});

			/* Do the initial load */
			gnome_bg.load_from_preferences(this.settings);
		}

		/**
		* call accountsservice dbus with the background file name
		* to update the greeter background if the display
		* manager supports the dbus call.
		*/
		void set_accountsservice_user_bg(string background) {
			DBusConnection bus;
			Variant variant;

			try {
				bus = Bus.get_sync(BusType.SYSTEM);
			} catch (IOError e) {
				warning("Failed to get system bus: %s", e.message);
				return;
			}

			try {
				variant = bus.call_sync(ACCOUNTS_SCHEMA, "/org/freedesktop/Accounts", ACCOUNTS_SCHEMA, "FindUserByName",
					new Variant("(s)", Environment.get_user_name()), new VariantType("(o)"), DBusCallFlags.NONE, -1, null);
			} catch (Error e) {
				warning("Could not contact accounts service to look up '%s': %s", Environment.get_user_name(), e.message);
				return;
			}

			string object_path = variant.get_child_value(0).get_string();

			try {
				bus.call_sync(ACCOUNTS_SCHEMA, object_path, "org.freedesktop.DBus.Properties", "Set",
					new Variant("(ssv)", "org.freedesktop.DisplayManager.AccountsService", "BackgroundFile",
						new Variant.string(background)
					), new VariantType("()"), DBusCallFlags.NONE, -1, null);
			} catch (Error e) {
				warning("Failed to set the background '%s': %s", background, e.message);
			}
		}

		void update() {
			string? bg_filename = gnome_bg.get_filename();;
			/* Set background image when appropriate, and for now dont parse .xml files */
			if (!this.is_color_wallpaper(bg_filename) && !bg_filename.has_suffix(".xml")) {
				// we use swaybg to define the wallpaper - we need to keep track
				// of what we create so that we kill it the next time a background is defined
				string[] cmdline = { "swaybg", "-i", bg_filename };
				Subprocess new_bg;
				try {
					new_bg = new Subprocess.newv(cmdline, SubprocessFlags.NONE);
					Timeout.add(BACKGROUND_TIMEOUT, () => {
						// use a delay to allow process termination to complete
						if (bg != null) {
							bg.force_exit();
						}
						bg = new_bg;
						return false;
					});
				} catch (Error e) {
					warning("Error starting swaybg: %s", e.message);
				}
				set_accountsservice_user_bg(bg_filename);
			}
		}
	}
}
