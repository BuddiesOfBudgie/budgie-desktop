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
	* Represents a category of applications.
	*/
	public class Category : Object {
		/** The name of this category. */
		public string name { get; construct; }

		/**
		* True if this category should be a catch-all for applicatiosn that
		* that don't go in any other category.
		*/
		public bool misc_category { get; construct; }

		public string[] included_categories;
		public string[] excluded_categories;
		public string[] excluded_applications;

		/** The list of applications in this category. */
		public Gee.ArrayList<Application> apps { get; private set; default = new Gee.ArrayList<Application>(); }

		/**
		* Create a new category with a name.
		*
		* Optionally mark this category as a miscellaneous catch-all category
		* by passing in `true` for the `misc` parameter.
		*/
		public Category(string name, bool misc = false) {
			Object(name: name, misc_category: misc);
		}

		/**
		 * Create a new category from a file.
		 *
		 * Errors are thrown if the file doesn't exist or is a directory,
		 * or if the input stream is closed while reading the file.
		 */
		public static Category? new_for_file(File file) throws Error {
			// Make sure we have a default name
			var name = _("New Category");

			// Open the file
			var input_stream = file.read(null);
			var data_stream = new DataInputStream(input_stream);

			// Read the lines
			string line = null;
			while ((line = data_stream.read_line()) != null) {
				// Look for a name to set
				if (line.has_prefix("Name=")) {
					name = line.substring(5).strip();
					break;
				}
			}

			return new Category(name) {
				included_categories = { name }
			};
		}

		/**
		* Add an application to this category if the app belongs in
		* this category.
		*
		* Returns `true` if the application should be in this category,
		* otherwise `false`.
		*/
		public bool maybe_add_app(Application app) {
			// Check if the application is excluded from this category
			if (app.desktop_id in excluded_applications) {
				return false;
			}

			// Get the categories for this application
			unowned var categories = app.categories;
			if (categories == null) {
				if (!this.misc_category) {
					return false;
				}

				// Add the app if this is the misc category and no categories are set
				this.apps.add(app);
				return true;
			}

			// Split the categories and see if this category is in the list
			bool found_category = false;
			foreach (unowned var category in categories.split(";")) {
				// Don't include the application if the sub-category is excluded from this category
				if (category in excluded_categories) {
					return false;
				}

				if (category in included_categories) {
					// Mark that we found a fitting category
					found_category = true;
				}
			}

			// Category found, add the application
			if (found_category) {
				debug("Adding '%s' to category '%s'", app.name, this.name);

				this.apps.add(app);
				return true;
			}

			// If this category is a misc category, add the app anyways
			if (this.misc_category) {
				debug("Adding '%s' to category '%s'", app.name, this.name);

				this.apps.add(app);
				return true;
			}

			return false;
		}
	}
}
