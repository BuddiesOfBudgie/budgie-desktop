 namespace libxfce4windowing {
	[CCode (cheader_filename = "libxfce4windowing/libxfce4windowing.h", cname = "XfwApplication", type_id = "xfw_application_get_type ()")]
	public abstract class Application : GLib.Object {
		[CCode (cname = "xfw_application_get_instance")]
		public unowned libxfce4windowing.ApplicationInstance? get_instance (libxfce4windowing.Window window);
    }

    [CCode (cheader_filename = "libxfce4windowing/libxfce4windowing.h", cname = "XfwWorkspace", type_id = "xfw_workspace_get_type ()")]
	public interface Workspace : GLib.Object {
        [CCode (cname = "xfw_workspace_assign_to_workspace_group")]
        public bool assign_to_workspace_group (libxfce4windowing.WorkspaceGroup group) throws GLib.Error;
    }
 }