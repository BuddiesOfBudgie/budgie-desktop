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
		private HashTable<string, DesktopAppInfo> started_applications;
		private HashTable<int64?, string> pids;

		private AppInfoMonitor monitor;
		private DBusConnection bus;

		private bool invalidated = false;

		construct {
			applications = new HashTable<string, DesktopAppInfo>(str_hash, str_equal);
			started_applications = new HashTable<string, DesktopAppInfo>(str_hash, str_equal);
			pids = new HashTable<int64?, string>(str_hash, str_equal);

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
			started_applications.remove_all();

			foreach (var app_info in AppInfo.get_all()) {
				var desktop_info = app_info as DesktopAppInfo;
				var desktop_id = desktop_info.get_id().down();

				if (desktop_info.get_startup_wm_class() != null) {
					started_applications[desktop_info.get_startup_wm_class().down()] = desktop_info;
				}

				applications[desktop_id] = desktop_info;
			}
		}

		private string? query_atom_string(ulong xid, Gdk.Atom atom, bool utf8) {
			uint8[]? data = null;
			Gdk.Atom a_type;
			int a_f; // TODO: wat?
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
				out a_type,
				out a_f,
				out data
			);

			// TODO: I feel like this could be made more readable
			return data != null ? (string) data : null;
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
			var gtk_id = query_atom_string((ulong) window.get_id(), Gdk.Atom.intern("_GTK_APPLICATION_ID", false), true);

			if (gtk_id != null) {
				var desktop_id = gtk_id.down() + ".desktop";

				if (desktop_id in applications) {
					return applications[desktop_id];
				}
			}

			unowned var wnck_window = Wnck.Window.@get((ulong) window.get_id());
			unowned var class_group_name = wnck_window.get_class_group_name();

			// Try to match the class group name to an application
			if (class_group_name != null) {
				if (class_group_name.down() in started_applications) {
					return started_applications[class_group_name.down()];
				}

				if (class_group_name.down() + ".desktop" in applications) {
					return applications[class_group_name.down() + ".desktop"];
				}
			}

			// Try to match the class instance name to an application
			unowned var instance_name = wnck_window.get_class_instance_name();

			if (instance_name != null) {
				if (instance_name.down() in started_applications) {
					return started_applications[instance_name.down()];
				}

				if (instance_name.down() + ".desktop" in applications) {
					return applications[instance_name.down() + ".desktop"];
				}
			}

			return null;
		}
	}
}
