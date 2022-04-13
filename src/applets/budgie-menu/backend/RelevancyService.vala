/*
 * This file is part of budgie-desktop
 *
 * Copyright © 2015-2022 Budgie Desktop Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

/**
 * This class keeps track of how relevant each application
 * in the menu is with relation to a search term.
 */
public class RelevancyService : Object {
	/**
	 * Arbitrary threshold that scores have to be below to
	 * be considered "relevant."
	 */
	public const int THRESHOLD = 4;

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
		return mod.replace("\u00AD", "").ascii_down().strip();
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

		return this.get_score(app) < THRESHOLD;
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
		var score = 0;

		// If we don't have a match on the name...
		if (!term.match_string(name, true)) {
			// Calculate our Levenshtein distance
			score = this.get_levenshtein_distance(name, term);
		}

		string?[] fields = {
			app.generic_name,
			app.description,
			app.exec
		};

		// Check the various fields, and decrease the score
		// for every match
		if (array_contains(fields, term)) {
			score--;
		}

		// Check the application's keywords
		var keywords = app.keywords;
		if (keywords != null && keywords.length > 0) {
			// Decrease the score for every match
			if (array_contains(keywords, term)) {
				score--;
			}
		}

		// Set the score
		scores.set(app.desktop_id, score);
	}

	/**
	 * Calculates the Levenshtein Distance between two strings.
	 *
	 * The lower the returned score, the closer the match.
	 *
	 * This was adapted from https://gist.github.com/Davidblkx/e12ab0bb2aff7fd8072632b396538560,
	 * an implementation in C#.
	 */
	private int get_levenshtein_distance(string s1, string s2) {
		var matrix = new int[s1.length + 1, s2.length + 1];

		// If either term is empty, return the full length of the other
		if (s1.length == 0) {
			return s2.length;
		} else if (s2.length == 0) {
			return s1.length;
		}

		// Initialization of matrix with row size s1.length and column size s2.length
		for (int i = 0; i <= s1.length; matrix[i, 0] = i++) {}
		for (int j = 0; j <= s2.length; matrix[0, j] = j++) {}

		// Calculate row and column distances
		for (int i = 1; i <= s1.length; i++) {
			for (int j = 1; j <= s2.length; j++) {
				// If the chars at the current indices match, the cost is 0
				// else, the cost is 1, thus increasing the score
				var cost = (s2[j - 1] == s1[i - 1]) ? 0 : 1;

				// Set the score in the matrix at the current indices
				matrix[i, j] = int.min(
					int.min(matrix[i - 1, j] + 1, matrix[i, j - 1] + 1),
					matrix[i - 1, j - 1] + cost
				);
			}
		}

		// The final score is at the end of the matrix
		return matrix[s1.length, s2.length];
	}

	/* Helper ported from Brisk */
	private bool array_contains(string?[] array, string term) {
		foreach (string? field in array) {
			if (field == null) {
				continue;
			}
			string ct = searchable_string(field);
			if (term.match_string(ct, true)) {
				return true;
			}
			if (term in ct) {
				return true;
			}
		}
		return false;
	}
}
