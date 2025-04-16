using Budgie;
using GLib;
using Peas;

[CCode (cprefix = "Budgie", lower_case_cprefix = "budgie_")]
namespace Budgie {
	[CCode (cheader_filename = "plugin/plugin-manager.h", cprefix = "BUDGIE_", cname = "BUDGIE_APPLET_PREFIX")]
	public const string APPLET_PREFIX;
	[CCode (cheader_filename = "plugin/plugin-manager.h", cprefix = "BUDGIE_", cname = "BUDGIE_APPLET_SCHEMA")]
	public const string APPLET_SCHEMA;

	[CCode (cheader_filename = "plugin/plugin-manager.h", cname = "BudgiePanelPluginManagerError", cprefix = "BUDGIE_PANEL_PLUGIN_MANAGER_ERROR_", has_type_id = false)]
	public errordomain PanelPluginManagerError {
		INVALID,
		LOAD_FAILED,
		NOT_FOUND,
		NOT_LOADED
	}

	[CCode (cheader_filename = "plugin/plugin-manager.h", cname = "BudgiePanelPluginManager", type_id = "budgie_panel_plugin_manager_get_type ()")]
	public class PanelPluginManager : GLib.Object {
		[CCode (cname = "budgie_panel_plugin_manager_new")]
		public PanelPluginManager ();

		[CCode (cname = "budgie_panel_plugin_manager_is_plugin_loaded")]
		public bool is_plugin_loaded (string name);

		[CCode (cname = "budgie_panel_plugin_manager_is_plugin_valid")]
		public bool is_plugin_valid (string name);

		[CCode (cname = "budgie_panel_plugin_manager_get_all_plugins")]
		public GLib.List<Peas.PluginInfo> get_all_plugins ();

		[CCode (cname = "budgie_panel_plugin_manager_rescan_plugins")]
		public void rescan_plugins ();

		[CCode (cname = "budgie_panel_plugin_manager_modprobe")]
		public void modprobe (string name);

		[CCode (cname = "budgie_panel_plugin_manager_load_applet_instance")]
		public Budgie.AppletInfo? load_applet_instance (string uuid, GLib.Settings? settings, out string name) throws Budgie.PanelPluginManagerError;

		[CCode (cname = "budgie_panel_plugin_manager_create_applet")]
		public Budgie.AppletInfo? create_applet (string name, string uuid) throws Budgie.PanelPluginManagerError;

		public signal void extension_loaded(string name);
	}
}
