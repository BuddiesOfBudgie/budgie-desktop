/*
 * This file is part of budgie-desktop
 *
 * Copyright © 2022 Budgie Desktop Developers
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
		/**
		 * List of all categories with apps in them.
		 * This is `static` because the class is intended to be used
		 * in multiple places, and we really only ever want one instance
		 * of the index.
		 */
		private static Gee.ArrayList<Category> categories;

		private AppInfoMonitor monitor;
		private uint timeout_id = 0;

		/**
		* Signal emitted whenever a change to the application state
		* occurs.
		*/
		public signal void changed();

		public AppIndex() {
			Object();
		}

		static construct {
			categories = new Gee.ArrayList<Category>();
		}

		construct {
			this.monitor = AppInfoMonitor.@get();
			this.monitor.changed.connect(() => {
				this.queue_refresh();
			});

			// Start building the tree right now
			this.refresh();
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
				excluded_categories = { "Accessibility", "System", "X-GNOME-Utilities" },
				excluded_applications = {
					"eog.desktop",
					"gucharmap.desktop",
					"org.gnome.DejaDup.desktop",
					"org.gnome.Dictionary.desktop",
					"org.gnome.DiskUtility.desktop",
					"org.gnome.Evince.desktop",
					"org.gnome.FileRoller.desktop",
					"org.gnome.font-viewer.desktop",
					"org.gnome.Screenshot.desktop",
					"org.gnome.seahorse.Application.desktop",
					"org.gnome.Terminal.desktop",
					"org.gnome.tweaks.desktop",
					"org.gnome.Usage.desktop",
					"plank.desktop",
					"simple-scan.desktop",
					"vinagre.desktop",
					"yelp.desktop"
				}
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
				excluded_applications = {
					"org.gnome.Evince.desktop",
					"simple-scan.desktop"
				}
			});

			categories.add(new Category(_("Internet")) {
				included_categories = { "Network" },
				excluded_applications = { "vinagre.desktop" }
			});

			categories.add(new Category(_("Office")) {
				included_categories = { "Office" },
				excluded_applications = { "org.gnome.Dictionary.desktop", "org.gnome.Evince.desktop" }
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
				excluded_categories = { "Games", "X-GNOME-Utilities" },
				excluded_applications = {
					"onboard.desktop",
					"onboard-settings.desktop",
					"org.gnome.baobab.desktop",
					"org.gnome.Usage.desktop"
				}
			});

			categories.add(new Category(_("Universal Access")) {
				included_categories = { "Accessibility" }
			});

			categories.add(new Category(_("Utilities")) {
				included_categories = { "X-GNOME-Utilities" }
			});

			// Create our misc category, but don't add it to the list until it actually has apps in it
			var misc_category = new Category(_("Other"), true) {
				excluded_categories = { "Core", "Screensaver", "Settings" },
				// All of these should be in Utilities
				excluded_applications = { "htop.desktop", "onboard.desktop", "org.gnome.FileRoller.desktop", "org.gnome.font-viewer.desktop" }
			};

			// Iterate over all registered AppInfos and try to put them in categories
			foreach (var app in AppInfo.get_all()) {
				unowned var desktop_app = app as DesktopAppInfo;
				if (desktop_app == null) {
					continue;
				}

				// Check if this is a control center panel
				var control_center = "budgie-control-center";
				bool is_control_center_panel = (
					app.get_commandline() != null &&
					control_center in app.get_commandline() &&
					app.get_commandline().length != control_center.length
				);

				// Check if we should not add this application to the index.
				// We have to make sure to add BCC panel items because they
				// have NoDisplay set, so this would otherwise exclude them.
				// Showing/hiding them is handled by the UI layer.
				bool should_skip = (!desktop_app.should_show() && !is_control_center_panel) ||
									(desktop_app.get_boolean("Terminal"));

				if (should_skip) {
					continue;
				}

				// Try to get the best category for this app
				bool category_found = false;
				foreach (var category in categories) {
					if (category.maybe_add_app(desktop_app)) {
						category_found = true; // Don't break because apps can be in multiple categories
					}
				}

				// No suitable category for this app was found, so add it
				// to the misc category
				if (!category_found) {
					misc_category.maybe_add_app(desktop_app);
				}
			}

			// Add the misc category if there are apps in it
			if (misc_category.apps.size > 0) {
				categories.add(misc_category);
			}

			// Emit our signal for changes
			this.changed();
		}
	}
}
