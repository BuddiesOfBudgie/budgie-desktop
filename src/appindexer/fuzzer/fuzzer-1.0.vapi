namespace Fuzzer {
	[CCode (cheader_filename="fuzzer.h")]
	public static int get_fuzzy_score(string text, string pattern, int max_distance);
}
