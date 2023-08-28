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
	* This class keeps track of how relevant each application
	* in the menu is with relation to a search term.
	*/
	public class RelevancyService : Object {
		/**
		* Arbitrary threshold that scores have to be below to
		* be considered "relevant."
		*/
		public const int THRESHOLD = 16;

		/** Static map of desktop IDs to scores. */
		private static Gee.HashMap<string, int> scores;

		static construct {
			scores = new Gee.HashMap<string, int>();
		}

		/**
		* Return a string suitable for working on.
		* This works around the issue of GNOME Control Center and others deciding to
		* use soft hyphens in their .desktop files.
		*/
		public static string? searchable_string(string input) {
			/* Force dup in vala */
			string mod = "" + input;
			return mod.replace("\u00AD", "").casefold().strip();
		}

		/**
		* Get the current relevancy score for an application.
		*
		* The lower the score, the more relevant it is.
		*/
		public int get_score(Application app) {
			if (scores == null) {
				warning("Relevancy HashMap has not been initialized!");
				return int.MAX;
			}

			return scores.get(app.desktop_id);
		}

		/**
		* Check if an application's relevancy score is below our
		* relevancy threshold.
		*/
		public bool is_app_relevant(Application app) {
			if (scores == null) {
				warning("Relevancy HashMap has not been initialized!");
				return false;
			}

			var score = get_score(app);

			return score >= 0 && score < THRESHOLD;
		}

		/**
		* Clears our relevancy mappings.
		*/
		public void reset() {
			if (scores == null) {
				return;
			}

			scores.clear();
		}

		/**
		* Determine a score in relation to a given search term.
		*
		* Somewhat unintuitively, the lower the score returned,
		* the more relevant this item is. This is because we take
		* the Levenshtein Distance between the term and the name
		* into account, and it's way easier to have an arbitrary
		* threshold when you have a set minimum value.
		*
		* This was inspired by prior art from Brisk Menu.
		*/
		public void update_relevancy(Application app, string term) {
			if (scores == null) {
				warning("Relevancy HashMap has not been initialized!");
				return;
			}

			// Unset this application if it exists
			scores.unset(app.desktop_id);

			// Term is blank, no work required
			if (term == "") {
				return;
			}

			string name = searchable_string(app.name);
			string _term = term.casefold();

			// Get a initial score based on the fuzzy match of the name
			var score = Fuzzer.get_fuzzy_score(name, _term, 1);

			// If the term is considered to be an exact match, bail early
			if (score == 0) {
				// Prioritize matches where the name starts with the term
				if (!name.has_prefix(_term)) {
					score++;
				}

				scores.set(app.desktop_id, score);
				return;
			}

			// Score is less than 0, disqualified
			if (score < 0) {
				scores.set(app.desktop_id, score);
				return;
			}

			string?[] fields = {
				app.generic_name,
				app.description,
				app.exec
			};

			// Check the various fields, and decrease the score
			// for every match
			if (array_contains(fields, _term)) {
				score--;
			}

			// Check the application's keywords
			var keywords = app.keywords;
			if (keywords != null && keywords.length > 0) {
				// Decrease the score for every match
				if (array_contains(keywords, _term)) {
					score--;
				}
			}

			// Check if the application is the default handler for its supported
			// MIME types
			if (name.contains(_term) && is_default_handler(app)) {
				debug("Application '%s' is default handler", app.name);
				score--;
			}

			// Set the score
			scores.set(app.desktop_id, int.max(score, 0));
		}

		/* Helper ported from Brisk */
		private bool array_contains(string?[] array, string term) {
			foreach (string? field in array) {
				if (field == null) {
					continue;
				}
				string ct = searchable_string(field);
				if (ct.match_string(term, true)) {
					return true;
				}
			}
			return false;
		}

		/**
		 * Check if an application is the default handler for
		 * any of its supported MIME types.
		 */
		private bool is_default_handler(Application app) {
			foreach (var content_type in app.content_types) {
				var default_app = AppInfo.get_default_for_type(content_type, false);
				if (default_app == null) continue;
				if (default_app.get_id() == app.desktop_id) return true;
			}

			return false;
		}
	}
}
