/* girepository-2.0.vapi */

[CCode (cprefix = "GI", gir_namespace = "GIRepository", gir_version = "2.0", lower_case_cprefix = "gi_")]
namespace GI {
	[CCode (cheader_filename = "girepository/girepository.h", type_id = "g_base_info_gtype_get_type ()", ref_function = "g_base_info_ref", unref_function = "g_base_info_unref")]
	[Compact]
	public class BaseInfo {
	}
	
	[CCode (cheader_filename = "girepository/girepository.h", type_id = "g_base_info_gtype_get_type ()")]
	[Compact]
	public class InterfaceInfo : GI.BaseInfo {
	}
	
	[CCode (cheader_filename = "girepository/girepository.h", type_id = "g_base_info_gtype_get_type ()")]
	[Compact]
	public class EnumInfo : GI.BaseInfo {
	}
	
	[CCode (cheader_filename = "girepository/girepository.h", lower_case_csuffix = "irepository", type_id = "gi_repository_get_type ()")]
	public class Repository : GLib.Object {
		[CCode (has_construct_function = false)]
		public Repository ();
		
		public void prepend_search_path (string directory);
		public void prepend_library_path (string directory);
		
		[CCode (array_length_pos = 1.5, array_length_type = "size_t")]
		public unowned string[] get_search_path (out size_t n_paths_out);
		
		[CCode (array_length_pos = 1.5, array_length_type = "size_t")]
		public unowned string[] get_library_path (out size_t n_paths_out);
		
		public unowned string? load_typelib (GI.Typelib typelib, GI.RepositoryLoadFlags flags) throws GLib.Error;
		
		public bool is_registered (string namespace_, string? version);
		
		public unowned GI.BaseInfo? find_by_name (string namespace_, string name);
		
		[CCode (array_length_pos = 1.5, array_length_type = "size_t")]
		public string[] enumerate_versions (string namespace_, out size_t n_versions_out);
		
		public unowned GI.Typelib? require (string namespace_, string? version, GI.RepositoryLoadFlags flags) throws GLib.Error;
		
		public unowned GI.Typelib? require_private (string typelib_dir, string namespace_, string? version, GI.RepositoryLoadFlags flags) throws GLib.Error;
		
		[CCode (array_length_pos = 1.5, array_length_type = "size_t")]
		public string[] get_immediate_dependencies (string namespace_, out size_t n_dependencies_out);
		
		[CCode (array_length_pos = 1.5, array_length_type = "size_t")]
		public string[] get_dependencies (string namespace_, out size_t n_dependencies_out);
		
		[CCode (array_length_pos = 1.5, array_length_type = "size_t")]
		public string[] get_loaded_namespaces (out size_t n_namespaces_out);
		
		public unowned GI.BaseInfo? find_by_gtype (GLib.Type gtype);
		
		[CCode (array_length_pos = 2.5, array_length_type = "size_t")]
		public void get_object_gtype_interfaces (GLib.Type gtype, out size_t n_interfaces_out, out unowned GI.InterfaceInfo[] interfaces_out);
		
		public uint get_n_infos (string namespace_);
		
		public unowned GI.BaseInfo? get_info (string namespace_, uint idx);
		
		public unowned GI.EnumInfo? find_by_error_domain (GLib.Quark domain);
		
		public unowned string? get_typelib_path (string namespace_);
		
		[CCode (array_length_pos = 1.5, array_length_type = "size_t")]
		public unowned string[]? get_shared_libraries (string namespace_, out size_t out_n_elements);
		
		public unowned string? get_c_prefix (string namespace_);
		
		public unowned string? get_version (string namespace_);
		
		public static unowned GLib.OptionGroup get_option_group ();
		
		public static bool dump (string input_filename, string output_filename) throws GLib.Error;
	}
	
	[CCode (cheader_filename = "girepository/girepository.h", ref_function = "gi_typelib_ref", unref_function = "gi_typelib_unref", type_id = "gi_typelib_get_type ()")]
	[Compact]
	public class Typelib {
		[CCode (cname = "gi_typelib_new_from_bytes", has_construct_function = false)]
		public static GI.Typelib? new_from_bytes (GLib.Bytes bytes) throws GLib.Error;
		
		[CCode (cname = "gi_typelib_ref")]
		public unowned GI.Typelib @ref ();
		
		[CCode (cname = "gi_typelib_unref")]
		public void unref ();
		
		[CCode (cname = "gi_typelib_get_namespace")]
		public unowned string get_namespace ();
		
		[CCode (cname = "gi_typelib_symbol")]
		public bool symbol (string symbol_name, out void* symbol);
	}
	
	[CCode (cheader_filename = "girepository/girepository.h", cprefix = "GI_REPOSITORY_LOAD_FLAG_", has_type_id = false)]
	[Flags]
	public enum RepositoryLoadFlags {
		NONE,
		LAZY
	}
	
	[CCode (cheader_filename = "girepository/girepository.h", cprefix = "GI_REPOSITORY_ERROR_", has_type_id = false)]
	public errordomain RepositoryError {
		TYPELIB_NOT_FOUND,
		NAMESPACE_MISMATCH,
		NAMESPACE_VERSION_CONFLICT,
		LIBRARY_NOT_FOUND;
		
		[CCode (cname = "gi_repository_error_quark")]
		public static GLib.Quark quark ();
	}
	
	[CCode (cheader_filename = "girepository/girepository.h", cname = "gi_cclosure_marshal_generic")]
	public void cclosure_marshal_generic (GLib.Closure closure, GLib.Value return_gvalue, uint n_param_values, [CCode (array_length = false)] GLib.Value[] param_values, void* invocation_hint, void* marshal_data);
}

