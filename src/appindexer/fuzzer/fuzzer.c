#include <limits.h>
#include <stdlib.h>
#include <string.h>

#include "fuzzer.h"

/**
 * fuzzer_get_fuzzy_score:
 * @text: the text to compare to
 * @pattern: the text being used to search
 * @max_distance: the maximum distance between the strings to still be considered equal
 *
 * Fuzzily matches two strings using the Fuzzy Bitap Algorithm.
 *
 * The algorithm tells whether a given text contains a substring
 * which is "approximately equal" to a given pattern, where approximate
 * equality is defined in terms of Levenshtein distance.
 *
 * The algorithm begins by precomputing a set of bitmasks containing one
 * bit for each element of the pattern. Then it is able to do most of the
 * work with bitwise operations, which are extremely fast.
 *
 * Adapted from here: https://www.programmingalgorithms.com/algorithm/fuzzy-bitap-algorithm/
 *
 * Return value: a score based on the closeness of the texts
 */
gint fuzzer_get_fuzzy_score(const gchar *text, const gchar *pattern, gint max_distance) {
	gint result = -1;
	gint pattern_length;
	guint64 *bit_array = NULL;
	guint64 pattern_mask[CHAR_MAX + 1];
	gint i, d;

	g_return_val_if_fail(text != NULL, -1);
	g_return_val_if_fail(pattern != NULL, -1);

	pattern_length = strlen(pattern);

	if (g_strcmp0(pattern, "") == 0) return 0; // Pattern is empty
	if (pattern_length > 31) return -1; // Error: pattern too long

	/* Initialize the bit array */
	bit_array = (guint64 *) malloc((max_distance + 1) * sizeof(*bit_array));
	for (i = 0; i <= max_distance; ++i) bit_array[i] = ~1;

	/* Initialize the pattern masks */
	for (i = 0; i <= 127; ++i) pattern_mask[i] = ~0;

	for (i = 0; i < pattern_length; ++i) pattern_mask[pattern[i]] &= ~(1UL << i);

	/* Calculating the score */

	for (i = 0; text[i] != '\0'; ++i) {
		/* Update the bit arrays */
		guint64 old_Rd1 = bit_array[0];

		bit_array[0] |= pattern_mask[text[i]];
		bit_array[0] <<= 1;

		for (d = 1; d <= max_distance; ++d) {
			guint64 tmp = bit_array[d];

			/* Only look for substitutions */
			bit_array[d] = (old_Rd1 & (bit_array[d] | pattern_mask[text[i]])) << 1;
			old_Rd1 = tmp;
		}

		if (0 == (bit_array[max_distance] & (1UL << pattern_length))) {
			result = (i - pattern_length) + 1;
			break;
		}
	}

	g_free(bit_array);

	return result;
}
