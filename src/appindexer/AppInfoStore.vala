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
	/**
	 * Holds the installed desktop applications for every consumer in the
	 * process, and reloads them when the installed applications change.
	 */
	public class AppInfoStore : Object {
		private static AppInfoStore? instance = null;

		private AppInfoMonitor monitor;
		private List<DesktopAppInfo> apps = new List<DesktopAppInfo>();
		private bool loaded = false;

		/**
		 * Emitted when the installed applications change. The next call to
		 * get_apps() loads the new set.
		 */
		public signal void changed();

		private AppInfoStore() {
			Object();
		}

		construct {
			monitor = AppInfoMonitor.@get();
			monitor.changed.connect(on_monitor_changed);
		}

		/**
		 * Gets the shared AppInfoStore instance, creating it on first use.
		 */
		public static unowned AppInfoStore get_default() {
			if (instance == null) {
				instance = new AppInfoStore();
			}

			return instance;
		}

		/**
		 * Get the installed desktop applications, in the order GIO lists them.
		 */
		public unowned List<DesktopAppInfo> get_apps() {
			if (!loaded) {
				foreach (var app_info in AppInfo.get_all()) {
					var desktop_info = app_info as DesktopAppInfo;
					if (desktop_info != null) apps.append(desktop_info);
				}

				loaded = true;
			}

			return apps;
		}

		private void on_monitor_changed() {
			apps = new List<DesktopAppInfo>();
			loaded = false;

			changed();
		}
	}
}
