namespace Cogl {
	public struct Color {
		[Version (since = "1.4")]
		[CCode (cname="cogl_color_init_from_4f")]
		public Color.from_4f (float red, float green, float blue, float alpha);
		[Version (since = "1.4")]
		[CCode (cname="cogl_color_init_from_4fv")]
		public Color.from_4fv (float color_array);
		[Version (since = "1.4")]
		[CCode (cname="cogl_color_init_from_4ub")]
		public Color.from_4ub (uint8 red, uint8 green, uint8 blue, uint8 alpha);
		[Version (since = "1.16")]
		[CCode (cname="cogl_color_init_from_hsl")]
		public Color.from_hsl (float hue, float saturation, float luminance);
	}

	[Compact]
	[CCode (cname = "CoglHandle", cheader_filename = "cogl/cogl.h", type_id = "cogl_handle_get_gtype ()", ref_function = "cogl_object_ref", unref_function = "cogl_object_unref")]
	public class Shader : Cogl.Handle {
	}

	[CCode (cheader_filename = "cogl/cogl.h", type_id = "cogl_primitive_get_gtype ()")]
	public class Primitive : Cogl.Object {
		[CCode (has_construct_function = false)]
		protected Primitive ();
		[Version (since = "1.10")]
		public Cogl.Primitive copy ();
		[Version (since = "1.16")]
		public void draw (Cogl.Framebuffer framebuffer, Cogl.Pipeline pipeline);
		public int get_first_vertex ();
		public Cogl.VerticesMode get_mode ();
		[Version (since = "1.8")]
		public int get_n_vertices ();
		[CCode (has_construct_function = false)]
		[Version (since = "1.6")]
		public Primitive.p2 (Cogl.Context context, Cogl.VerticesMode mode, [CCode (array_length_cname = "n_vertices", array_length_pos = 2.5)] Cogl.VertexP2[] data);
		[CCode (has_construct_function = false)]
		[Version (since = "1.6")]
		public Primitive.p2c4 (Cogl.Context context, Cogl.VerticesMode mode, [CCode (array_length_cname = "n_vertices", array_length_pos = 2.5)] Cogl.VertexP2C4[] data);
		[CCode (has_construct_function = false)]
		[Version (since = "1.6")]
		public Primitive.p2t2 (Cogl.Context context, Cogl.VerticesMode mode, [CCode (array_length_cname = "n_vertices", array_length_pos = 2.5)] Cogl.VertexP2T2[] data);
		[CCode (has_construct_function = false)]
		[Version (since = "1.6")]
		public Primitive.p2t2c4 (Cogl.Context context, Cogl.VerticesMode mode, [CCode (array_length_cname = "n_vertices", array_length_pos = 2.5)] Cogl.VertexP2T2C4[] data);
		[CCode (has_construct_function = false)]
		[Version (since = "1.6")]
		public Primitive.p3 (Cogl.Context context, Cogl.VerticesMode mode, [CCode (array_length_cname = "n_vertices", array_length_pos = 2.5)] Cogl.VertexP3[] data);
		[CCode (has_construct_function = false)]
		[Version (since = "1.6")]
		public Primitive.p3c4 (Cogl.Context context, Cogl.VerticesMode mode, [CCode (array_length_cname = "n_vertices", array_length_pos = 2.5)] Cogl.VertexP3C4[] data);
		[CCode (has_construct_function = false)]
		[Version (since = "1.6")]
		public Primitive.p3t2 (Cogl.Context context, Cogl.VerticesMode mode, [CCode (array_length_cname = "n_vertices", array_length_pos = 2.5)] Cogl.VertexP3T2[] data);
		[CCode (has_construct_function = false)]
		[Version (since = "1.6")]
		public Primitive.p3t2c4 (Cogl.Context context, Cogl.VerticesMode mode, [CCode (array_length_cname = "n_vertices", array_length_pos = 2.5)] Cogl.VertexP3T2C4[] data);
		public void set_first_vertex (int first_vertex);
		public void set_mode (Cogl.VerticesMode mode);
		[Version (since = "1.8")]
		public void set_n_vertices (int n_vertices);
	}

	[Compact]
	[CCode (cname = "CoglHandle", cheader_filename = "cogl/cogl.h", type_id = "cogl_handle_get_gtype ()", ref_function = "cogl_object_ref", unref_function = "cogl_object_unref")]
	public class Program : Cogl.Handle {
	}

	[Compact]
	[CCode (cheader_filename = "cogl/cogl.h", type_id = "cogl_handle_get_gtype ()", ref_function = "cogl_object_ref", unref_function = "cogl_object_unref")]
	public class Handle {
		[CCode (cheader_filename = "cogl/cogl.h", cname="cogl_is_material")]
		[Version (deprecated = true, deprecated_since = "1.16")]
		public bool is_material ();
		[CCode (cheader_filename = "cogl/cogl.h", cname="cogl_is_program")]
		[Version (deprecated = true, deprecated_since = "1.16")]
		public bool is_program (Cogl.Handle handle);
		[CCode (cheader_filename = "cogl/cogl.h", cname="cogl_is_shader")]
		[Version (deprecated = true, deprecated_since = "1.16")]
		public bool is_shader ();
		[CCode (cheader_filename = "cogl/cogl.h", cname="cogl_is_texture")]
		public bool is_texture ();
	}

	[CCode (cheader_filename = "cogl/cogl.h", has_type_id = false)]
	[Version (since = "1.6")]
	public struct VertexP2 {
		public float x;
		public float y;
	}
	[CCode (cheader_filename = "cogl/cogl.h", has_type_id = false)]
	[Version (since = "1.6")]
	public struct VertexP2C4 {
		public float x;
		public float y;
		public uint8 r;
		public uint8 g;
		public uint8 b;
		public uint8 a;
	}
	[CCode (cheader_filename = "cogl/cogl.h", has_type_id = false)]
	[Version (since = "1.6")]
	public struct VertexP2T2 {
		public float x;
		public float y;
		public float s;
		public float t;
	}
	[CCode (cheader_filename = "cogl/cogl.h", has_type_id = false)]
	[Version (since = "1.6")]
	public struct VertexP2T2C4 {
		public float x;
		public float y;
		public float s;
		public float t;
		public uint8 r;
		public uint8 g;
		public uint8 b;
		public uint8 a;
	}
	[CCode (cheader_filename = "cogl/cogl.h", has_type_id = false)]
	[Version (since = "1.6")]
	public struct VertexP3 {
		public float x;
		public float y;
		public float z;
	}
	[CCode (cheader_filename = "cogl/cogl.h", has_type_id = false)]
	[Version (since = "1.6")]
	public struct VertexP3C4 {
		public float x;
		public float y;
		public float z;
		public uint8 r;
		public uint8 g;
		public uint8 b;
		public uint8 a;
	}
	[CCode (cheader_filename = "cogl/cogl.h", has_type_id = false)]
	[Version (since = "1.6")]
	public struct VertexP3T2 {
		public float x;
		public float y;
		public float z;
		public float s;
		public float t;
	}
	[CCode (cheader_filename = "cogl/cogl.h", has_type_id = false)]
	[Version (since = "1.6")]
	public struct VertexP3T2C4 {
		public float x;
		public float y;
		public float z;
		public float s;
		public float t;
		public uint8 r;
		public uint8 g;
		public uint8 b;
		public uint8 a;
	}
}
