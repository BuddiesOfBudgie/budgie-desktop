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

namespace Budgie.Windowing {
	public class WindowMapper : GLib.Object {

		private HashTable<string, DesktopAppInfo> applications;
		private HashTable<string, DesktopAppInfo> startup_infos;
		private HashTable<string, string> simpletons;
		private HashTable<int64?, string> pids;

		private AppInfoMonitor monitor;
		private DBusConnection bus;

		private bool invalidated = false;

		construct {
			applications = new HashTable<string, DesktopAppInfo>(str_hash, str_equal);
			startup_infos = new HashTable<string, DesktopAppInfo>(str_hash, str_equal);
			simpletons = new HashTable<string, string>(str_hash, str_equal);
			pids = new HashTable<int64?, string>(str_hash, str_equal);

			simpletons["google-chrome-stable"] = "google-chrome";
			simpletons["calibre-gui"] = "calibre";
			simpletons["code - oss"] = "vscode-oss";
			simpletons["code"] = "vscode";
			simpletons["psppire"] = "pspp";
			simpletons["gnome-twitch"] = "com.vinszent.gnometwitch";
			simpletons["anoise.py"] = "anoise";

			Bus.@get.begin(BusType.SESSION, null, on_dbus_get);

			monitor = AppInfoMonitor.get();

			monitor.changed.connect(() => {
				Idle.add(() => {
					lock (invalidated) {
						invalidated = true;
					}

					return Source.REMOVE;
				});
			});

			load_app_infos();
		}

		private void on_dbus_get(Object? object, AsyncResult? res) {
			try {
				bus = Bus.@get.end(res);

				bus.signal_subscribe(
					null,
					"org.gtk.gio.DesktopAppInfo",
					"Launched",
					"/org/gtk/gio/DesktopAppInfo",
					null,
					0,
					app_launched
				);
			} catch (Error e) {
				critical("Unable to get Session bus: %s", e.message);
			}
		}

		private void app_launched(
			DBusConnection conn,
			string? sender,
			string object_path,
			string interface_name,
			string signal_name,
			Variant parameters
		) {
			Variant desktop_variant;
			int64 pid;

			parameters.get("(@aysxas@a{sv})", out desktop_variant, null, out pid, null, null);

			var desktop_file = desktop_variant.get_bytestring();

			if (desktop_file == "" || pid == 0) return;

			pids[pid] = desktop_file;
		}

		/**
		* We lazily check if at some point we became invalidated. In most cases
		* a package operation or similar modified a desktop file, i.e. making it
		* available or unavailable.
		*
		* Instead of immediately reloading the appsystem we wait until something
		* is actually requested again, check if we're invalidated, reload and then
		* set us validated again.
		*/
		private void check_invalidated() {
			if (invalidated) {
				lock (invalidated) {
					load_app_infos();

					invalidated = false;
				}
			}
		}

		/**
		* Reload and cache all the desktop IDs.
		*/
		private void load_app_infos() {
			applications.remove_all();
			startup_infos.remove_all();

			// Load all of the applications that set StartupWMClass in their .desktop files
			foreach (var app_info in AppInfo.get_all()) {
				var desktop_info = app_info as DesktopAppInfo;
				var desktop_id = desktop_info.get_id().down();

				if (desktop_info.get_startup_wm_class() != null) {
					startup_infos[desktop_info.get_startup_wm_class().down()] = desktop_info;
				}

				applications[desktop_id] = desktop_info;
			}
		}

		/**
		 * Try to get application group from its WM_CLASS property or fallback to using
		 * the app name when WM_CLASS isn't set (e.g. LibreOffice, Google Chrome, Android Studio emulator, maybe others)
		 */
		private string get_group_name(libxfce4windowing.Window window) {
			if (libxfce4windowing.windowing_get() == libxfce4windowing.Windowing.WAYLAND) {
				return window.get_class_ids()[0] ?? window.get_name();
			}

			// Get the Wnck window from the libx4w window
			unowned var wnck_window = Wnck.Window.@get((ulong) window.x11_get_xid());

			// Try to use class group name from WM_CLASS as it's the most precise
			// (Firefox Beta is a known offender, its class group will be the same as standard Firefox).
			string name = wnck_window.get_class_group_name();

			// Fallback to using class instance name (still from WM_CLASS),
			// less precise, if app is part of a "family", like libreoffice,
			// instance will always be libreoffice.
			if (name == null || name == "") {
				name = wnck_window.get_class_instance_name();
			}

			// Fallback to using name (when WM_CLASS isn't set).
			// i.e. Chrome profile launcher, android studio emulator
			if (name == null || name == "") {
				name = window.get_name();
			}

			if (name != null) {
				name = name.down();
			}

			// Chrome profile launcher doesn't have WM_CLASS, so name is used
			// instead and is not the same as the group of the window opened afterward.
			// Unfortunately there will still be a bit of a mess when using Chrome
			// simultaneously with Chrome Beta or Canary as they have the same WM_NAME: "google chrome"
			if (name == "google chrome") {
				name = "google-chrome";
			}

			return name;
		}

		private string? query_atom_string(ulong xid, Gdk.Atom atom, bool utf8) {
			uint8[]? data = null;
			Gdk.Atom type;
			int format;
			Gdk.X11.Display display = (Gdk.X11.Display) Gdk.Display.get_default();

			Gdk.Atom req_type;

			if (utf8) {
				req_type = Gdk.Atom.intern("UTF8_STRING", false);
			} else {
				req_type = Gdk.Atom.intern("STRING", false);
			}

			// Attempt to gain foreign window connection
			Gdk.Window? foreign = new Gdk.X11.Window.foreign_for_display(display, xid);

			// Bail if we don't have a window
			if (foreign == null) return null;

			// Get the property we want
			Gdk.property_get(
				foreign,
				atom,
				req_type,
				0,
				(ulong)long.MAX,
				0,
				out type,
				out format,
				out data
			);

			return data != null ? (string) data : null;
		}

		/**
		 * Try to get the DesktopAppInfo for a name by looking at our
		 * list of simpletons. This function also tries some special
		 * cases to try to get the correct match.
		 */
		private DesktopAppInfo? query_simpletons(string name) {
			DesktopAppInfo? info = null;
			string? desktop_name = null;

			// Check if the name we've been given is in our list of simpletons
			if (name.down() in simpletons) {
				desktop_name = simpletons[name.down()] + ".desktop";

				if (desktop_name in applications) {
					info = applications[desktop_name];
				} else if (desktop_name in startup_infos) {
					info = startup_infos[desktop_name];
				}
			}

			// The name wasn't, so now it's time for dirty hacks until Wayland
			if (info == null) {
				switch (name) {
					case "google-chrome": // Flatpak is different from official sources
						desktop_name = "com.google.Chrome";
						info = new DesktopAppInfo(desktop_name + ".desktop");
						break;
					case "google-chrome-unstable": // Flatpak is different from official sources
						desktop_name = "com.google.ChromeDev";
						info = new DesktopAppInfo(desktop_name + ".desktop");
						break;
					default: // Do nothing
						break;
				}
			}

			return info;
		}

		/**
		 * Try to get the DesktopAppInfo for a name. The name used
		 * is generally the window's class group name or instance name.
		 *
		 * The function looks at our started applications and cached
		 * applications. If both of those fail, then it looks at
		 * the simpleton applications.
		 */
		private DesktopAppInfo? query_name(string name) {
			if (name.down() in startup_infos) {
				return startup_infos[name.down()];
			}

			if (name.down() + ".desktop" in applications) {
				return applications[name.down() + ".desktop"];
			}

			var simpleton = query_simpletons(name);

			if (simpleton != null) {
				return simpleton;
			}

			return null;
		}

		/**
		* Attempt to gain the DesktopAppInfo relating to a given window.
		*/
		public DesktopAppInfo? query_window(libxfce4windowing.Window window) {
			unowned var instance = window.application.get_instance(window);

			if (instance == null) return null;

			var pid = instance.get_pid();

			// Check if the PID of the application is in our cache
			if (pid in pids) {
				var file_name = pids[pid];

				return new DesktopAppInfo.from_filename(file_name);
			}

			// Check if we have to reload caches for the next part
			check_invalidated();

			// Try to get the application based on GtkApplication ID
			var gtk_id = query_atom_string((ulong) window.x11_get_xid(), Gdk.Atom.intern("_GTK_APPLICATION_ID", false), true);

			if (gtk_id != null) {
				var desktop_id = gtk_id.down() + ".desktop";

				if (desktop_id in applications) return applications[desktop_id];
			}

			unowned var wnck_window = Wnck.Window.@get((ulong) window.x11_get_xid());
			var class_group_name = wnck_window.get_class_group_name();

			if (class_group_name == null) {
				class_group_name = get_group_name(window);
			}

			// Try to match the class group name to an application
			if (class_group_name != null) {
				var info = query_name(class_group_name);

				if (info != null) return info;
			}

			// Try to match the class instance name to an application
			unowned var instance_name = wnck_window.get_class_instance_name();

			if (instance_name != null) {
				var info = query_name(instance_name);

				if (info != null) return info;
			}

			return null;
		}
	}
}
