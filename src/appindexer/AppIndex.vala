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
	* This holds all of the application and category state for all
	* installed applications on the system.
	*/
	public class AppIndex : Object {
		private static AppIndex _instance;

		/**
		 * List of all categories with apps in them.
		 */
		private Gee.ArrayList<Category> categories;
		private Category misc_category;

		private AppInfoMonitor monitor;
		private FileMonitor file_monitor;
		private uint timeout_id = 0;

		/**
		* Signal emitted whenever a change to the application state
		* occurs.
		*/
		public signal void changed();

		private AppIndex() {
			Object();
		}

		construct {
			this.categories = new Gee.ArrayList<Category>();

			// Create our misc category, but don't add it to the list until it actually has apps in it
			this.misc_category = new Category(_("Other"), true) {
				excluded_categories = { "Core", "Screensaver", "Settings" },
				// All of these should be in Utilities
				excluded_applications = { "htop.desktop", "onboard.desktop", "org.gnome.FileRoller.desktop", "org.gnome.font-viewer.desktop" }
			};

			this.monitor = AppInfoMonitor.@get();
			this.monitor.changed.connect(() => {
				this.queue_refresh();
			});

			// Start watching the desktop-directories folder for custom category support
			var path = Path.build_path(Path.DIR_SEPARATOR_S, Environment.get_home_dir(), ".local", "share", "desktop-directories");
			var directory_file = File.new_for_path(path);
			try {
				this.file_monitor = directory_file.monitor_directory(FileMonitorFlags.NONE, null);
				this.file_monitor.changed.connect(() => {
					// Refresh the index when there is a category file change
					this.queue_refresh();
				});
			} catch (IOError e) {
				debug("Failed to create monitor for desktop directory: %s", e.message);
			}

			// Start building the tree right now
			this.refresh();
		}

		/**
		 * Gets the shared static AppIndex instance.
		 *
		 * If it has not yet been created, this function will
		 * create it and return it.
		 */
		public static new AppIndex @get() {
			if (_instance == null) {
				_instance = new AppIndex();
			}

			return _instance;
		}

		/**
		 * Get all of the registered categories with applications in them.
		 */
		public Gee.ArrayList<Category> get_categories() {
			if (categories == null) {
				warning("Trying to access application categories, but it is null!");
				categories = new Gee.ArrayList<Category>();
			}

			return categories;
		}

		/**
		* Queue an update of the application system to run.
		*
		* The time to wait before refreshing can be set by passing
		* in the number of seconds. By default the time is 3 seconds.
		*/
		public void queue_refresh(int seconds = 3) {
			// Reset the refresh timer if an update is already queued
			if (this.timeout_id != 0) {
				Source.remove(this.timeout_id);
				this.timeout_id = 0;
			}

			// Update the application system after the timeout
			this.timeout_id = Timeout.add(seconds, () => {
				this.refresh();
				this.timeout_id = 0;
				return Source.REMOVE;
			});
		}

		/**
		* Rebuild the entire app and category indexes.
		*
		* This iterates over all AppInfos on the system, so it is likely to be
		* costly to call this function.
		*/
		private void refresh() {
			if (categories == null) {
				warning("Trying to refresh the application index, but it is null!");
				categories = new Gee.ArrayList<Category>();
			}

			categories.clear();
			this.misc_category.apps.clear();

			/*
			* Add our categories, adhearing to the Freedesktop Menu spec.
			*
			* Inclusions and exclusions are sourced from multiple places,
			* including the UbuntuBudgie fork of applications-menu, gnome-menus,
			* the Freedeskop Menus spec, and by ourselves.
			*/

			categories.add(new Category(_("Accessories")) {
				included_categories = { "Utility" },
				/*
				* The spec states that Accessibility must have either the Utility or Settings categories,
				* and we have a separate accessibility category, so don't put those applications here.
				*/
				excluded_categories = { "Accessibility", "System" },
				excluded_applications = { "plank.desktop" }
			});

			categories.add(new Category(_("Education")) {
				included_categories = { "Education" },
				excluded_categories = { "Science" }
			});

			categories.add(new Category(_("Games")) {
				included_categories = { "Game" }
			});

			categories.add(new Category(_("Graphics")) {
				included_categories = { "Graphics" },
				// Evince should be in the Office category
				excluded_applications = {
					"org.gnome.Evince.desktop"
				}
			});

			categories.add(new Category(_("Internet")) {
				included_categories = { "Network" },
				excluded_applications = { "vinagre.desktop" }
			});

			categories.add(new Category(_("Office")) {
				included_categories = { "Office" }
			});

			categories.add(new Category(_("Programming")) {
				included_categories = { "Development" }
			});

			categories.add(new Category(_("Science")) {
				included_categories = { "Science", "Education" },
				// LibreOffice Math is an office application, not a science application
				excluded_applications = { "libreoffice-math.desktop" }
			});

			categories.add(new Category(_("Sound & Video")) {
				included_categories = { "AudioVideo" }
			});

			categories.add(new Category(_("System Tools")) {
				included_categories = { "Administration", "Settings", "System" },
				excluded_categories = { "Games" },
				// OnBoard applications should go in the Universal Access section
				excluded_applications = {
					"onboard.desktop",
					"onboard-settings.desktop"
				}
			});

			categories.add(new Category(_("Universal Access")) {
				included_categories = { "Accessibility" }
			});

			// See if there are any user-custom categories
			this.create_custom_categories();

			// Iterate over all registered AppInfos and try to put them in categories
			foreach (var app in AppInfo.get_all()) {
				unowned var desktop_app = app as DesktopAppInfo;
				if (desktop_app == null) {
					continue;
				}

				// Sort the application based on its DesktopAppInfo
				this.sort_application(desktop_app);
			}

			// Add the misc category if there are apps in it
			if (this.misc_category.apps.size > 0) {
				this.categories.add(this.misc_category);
			}

			// Emit our signal for changes
			this.changed();
		}

		/**
		 * Read files in `~/.local/share/desktop-directories` and add a new category
		 * for each of them.
		 */
		private void create_custom_categories() {
			var path = Path.build_path(Path.DIR_SEPARATOR_S, Environment.get_home_dir(), ".local", "share", "desktop-directories");
			var directory_file = File.new_for_path(path);

			// desktop-directories dir doesn't exist, skip custom categories
			if (!directory_file.query_exists()) {
				return;
			}

			try {
				// Enumerate all of the files in the desktop-directories dir
				var children = directory_file.enumerate_children(FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE, null);

				// Iterate over all of the children
				FileInfo child = null;
				while ((child = children.next_file(null)) != null) {
					var file_path = Path.build_path(Path.DIR_SEPARATOR_S, path, child.get_name());

					// Make sure that this is a file for a category/directory
					if (!child.get_name().has_suffix(".directory")) {
						continue;
					}

					try {
						// Try to build the category from the file
						var file = File.new_for_path(file_path);
						var category = Category.new_for_file(file);

						debug("Adding custom category '%s'", category.name);
						this.categories.add(category);
					} catch (Error e) {
						// There was an error reading the file, skip
						warning("Error creating category from '%s': %s", child.get_name(), e.message);
						continue;
					}
				}
			} catch (Error e) {
				warning("Error enumerating files in desktop-directories: %s", e.message);
			}
		}

		/**
		 * Sort a single application into the proper categories.
		 */
		private void sort_application(DesktopAppInfo app_info) {
			// Check if this is a control center panel
			var control_center = "budgie-control-center";
			bool is_control_center_panel = (
				app_info.get_commandline() != null &&
				control_center in app_info.get_commandline() &&
				app_info.get_commandline().length != control_center.length
			);

			// Check if we should not add this application to the index.
			// We have to make sure to add BCC panel items because they
			// have NoDisplay set, so this would otherwise exclude them.
			// Showing/hiding them is handled by the UI layer.
			bool should_skip = (!app_info.should_show() && !is_control_center_panel) ||
								(app_info.get_boolean("Terminal"));

			if (should_skip) {
				return;
			}

			var application = new Application(app_info);

			// Try to get the best category for this app
			bool category_found = false;
			// Iterate over all of this application's categories
			foreach (var category in this.categories) {
				if (category.maybe_add_app(application)) {
					category_found = true; // Don't break because apps can be in multiple categories
				}
			}

			// No suitable category was found, so add it to the misc category
			if (!category_found) {
				this.misc_category.maybe_add_app(application);
			}
		}
	}
}
