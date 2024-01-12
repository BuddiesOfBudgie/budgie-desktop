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
	public const string MUTTER_EDGE_TILING = "edge-tiling";
	public const string MUTTER_MODAL_ATTACH = "attach-modal-dialogs";
	public const string MUTTER_BUTTON_LAYOUT = "button-layout";
	public const string EXPERIMENTAL_DIALOG = "experimental-enable-run-dialog-as-menu";
	public const string WM_ENABLE_UNREDIRECT = "enable-unredirect";
	public const string WM_SCHEMA = "com.solus-project.budgie-wm";

	public const bool CLUTTER_EVENT_PROPAGATE = false;
	public const bool CLUTTER_EVENT_STOP = true;

	public const string RAVEN_DBUS_NAME = "org.budgie_desktop.Raven";
	public const string RAVEN_DBUS_OBJECT_PATH = "/org/budgie_desktop/Raven";

	public const string PANEL_DBUS_NAME = "org.budgie_desktop.Panel";
	public const string PANEL_DBUS_OBJECT_PATH = "/org/budgie_desktop/Panel";

	public const string LOGIND_DBUS_NAME = "org.freedesktop.login1";
	public const string LOGIND_DBUS_OBJECT_PATH = "/org/freedesktop/login1";

	public const string POWER_DIALOG_DBUS_NAME = "org.buddiesofbudgie.PowerDialog";
	public const string POWER_DIALOG_DBUS_OBJECT_PATH = "/org/buddiesofbudgie/PowerDialog";

	/** Menu management */
	public const string MENU_DBUS_NAME = "org.budgie_desktop.MenuManager";
	public const string MENU_DBUS_OBJECT_PATH = "/org/budgie_desktop/MenuManager";

	public const string SWITCHER_DBUS_NAME = "org.budgie_desktop.TabSwitcher";
	public const string SWITCHER_DBUS_OBJECT_PATH = "/org/budgie_desktop/TabSwitcher";

	public const string SCREENSHOTCONTROL_DBUS_NAME = "org.buddiesofbudgie.BudgieScreenshotControl";
	public const string SCREENSHOTCONTROL_DBUS_OBJECT_PATH = "/org/buddiesofbudgie/ScreenshotControl";

	[Flags]
	public enum PanelAction {
		NONE = 1 << 0,
		MENU = 1 << 1,
		MAX = 1 << 2
	}

	public enum AnimationState {
		MAP = 1 << 0,
		MINIMIZE = 1 << 1,
		UNMINIMIZE = 1 << 2,
		DESTROY = 1 << 3
	}

	public class ScreenTilePreview : Clutter.Actor {
		public Meta.Rectangle tile_rect;

		construct {
			set_background_color(Clutter.Color.get_static(Clutter.StaticColor.SKY_BLUE));
			set_opacity(100);

			tile_rect = Meta.Rectangle();
		}
	}


	[DBus (name="org.budgie_desktop.Raven")]
	public interface RavenRemote : GLib.Object {
		public abstract bool GetExpanded() throws Error;
		public abstract async void Toggle() throws Error;
		public abstract async void ToggleNotificationsView() throws Error;
		public abstract async void ClearNotifications() throws Error;
		public abstract async void ToggleAppletView() throws Error;
		public abstract async void Dismiss() throws Error;
	}

	[DBus (name="org.budgie_desktop.Panel")]
	public interface PanelRemote : GLib.Object {
		public abstract async void ActivateAction(int flags) throws Error;
	}

	[DBus (name="org.freedesktop.login1.Manager")]
	public interface LoginDRemote : GLib.Object {
		public signal void PrepareForSleep(bool suspending);
	}

	/**
	* Allows us to invoke desktop menus without directly using GTK+ ourselves
	*/
	[DBus (name="org.budgie_desktop.MenuManager")]
	public interface MenuManager: GLib.Object {
		public abstract async void ShowDesktopMenu(uint button, uint32 timestamp) throws Error;
		public abstract async void ShowWindowMenu(uint32 xid, uint button, uint32 timestamp) throws Error;
	}

	/**
	* Allows us to display the tab switcher without Gtk
	*/
	[DBus (name="org.budgie_desktop.TabSwitcher")]
	public interface Switcher: GLib.Object {
		public abstract async void PassItem(uint32 xid, uint32 timestamp) throws Error;
		public abstract async void ShowSwitcher(bool backwards) throws Error;
		public abstract async void StopSwitcher() throws Error;
	}

	/**
	* Allows us to invoke the screenshot client without directly using GTK+ ourselves
	*/
	[DBus (name = "org.buddiesofbudgie.BudgieScreenshotControl")]
	public interface ScreenshotControl : GLib.Object {
		public async abstract void StartMainWindow() throws GLib.Error;
		public async abstract void StartAreaSelect() throws GLib.Error;
		public async abstract void StartWindowScreenshot() throws GLib.Error;
		public async abstract void StartFullScreenshot() throws GLib.Error;
	}

	/**
	 * Allows us to toggle the visibility of the Power Dialog
	 */
	[DBus (name="org.buddiesofbudgie.PowerDialog")]
	public interface PowerDialog: GLib.Object {
		public abstract async void Toggle() throws Error;
	}

	public class MinimizeData {
		public float scale_x;
		public float scale_y;
		public float place_x;
		public float place_y;
		public float old_x;
		public float old_y;

		public MinimizeData(float sx, float sy, float px, float py, float ox, float oy) {
			scale_x = sx;
			scale_y = sy;
			place_x = px;
			place_y = py;
			old_x = ox;
			old_y = oy;
		}
	}

	public class BudgieWM : Meta.Plugin {
		static Meta.PluginInfo info;

		public bool use_animations { public set ; public get ; default = true; }
		public static string[]? old_args;
		public static bool wayland = false;

		static Graphene.Point PV_CENTER;
		static Graphene.Point PV_NORM;

		private Meta.BackgroundGroup? background_group;

		private KeyboardManager? keyboard = null;

		Settings? settings = null;
		Settings? gnome_desktop_prefs = null;
		RavenRemote? raven_proxy = null;
		ShellShim? shim = null;
		BudgieWMDBUS? focus_interface = null;
		ScreenshotManager? screenshot = null;
		ScreenshotControl? screenshotcontrol_proxy = null;
		PanelRemote? panel_proxy = null;
		LoginDRemote? logind_proxy = null;
		MenuManager? menu_proxy = null;
		Switcher? switcher_proxy = null;
		PowerDialog? power_proxy = null;

		Settings? iface_settings = null;

		public bool enable_unredirect = true;

		HashTable<Meta.WindowActor?, AnimationState?> state_map;
		Clutter.Actor? display_group;
		bool enabled_experimental_run_diag_as_menu = false;

		construct {
			info = Meta.PluginInfo() {
				name = "Budgie WM",
				version = Budgie.VERSION,
				author = "Buddies of Budgie",
				license = "GPL-2.0-only",
				description = "Budgie Window Manager"
			};
			PV_CENTER = Graphene.Point();
			PV_NORM = Graphene.Point();
			PV_CENTER.x = 0.5f;
			PV_CENTER.y = 0.5f;
			PV_NORM.x = 0.0f;
			PV_NORM.y = 0.0f;
		}

		bool have_logind() {
			return FileUtils.test("/run/systemd/seats", FileTest.EXISTS);
		}

		/* Hold onto our ScreenshotControl proxy ref */
		void on_screenshotcontrol_get(Object? o, AsyncResult? res) {
			try {
				screenshotcontrol_proxy = Bus.get_proxy.end(res);
			} catch (Error e) {
				warning("Failed to gain ScreenshotControl proxy: %s", e.message);
			}
		}

		/* Hold onto our Raven proxy ref */
		void on_raven_get(Object? o, AsyncResult? res) {
			try {
				raven_proxy = Bus.get_proxy.end(res);
			} catch (Error e) {
				warning("Failed to gain Raven proxy: %s", e.message);
			}
		}

		/* Obtain Panel manager */
		void on_panel_get(Object? o, AsyncResult? res) {
			try {
				panel_proxy = Bus.get_proxy.end(res);
			} catch (Error e) {
				warning("Failed to get Panel proxy: %s", e.message);
			}
		}

		void lost_panel() {
			panel_proxy = null;
		}

		void has_panel() {
			if (panel_proxy == null) {
				Bus.get_proxy.begin<PanelRemote>(BusType.SESSION, PANEL_DBUS_NAME, PANEL_DBUS_OBJECT_PATH, 0, null, on_panel_get);
			}
		}

		/* Obtain Menu manager */
		void on_menu_get(Object? o, AsyncResult? res) {
			try {
				menu_proxy = Bus.get_proxy.end(res);
			} catch (Error e) {
				warning("Failed to get Menu proxy: %s", e.message);
			}
		}

		void lost_menu() {
			menu_proxy = null;
		}

		void has_menu() {
			if (menu_proxy == null) {
				Bus.get_proxy.begin<MenuManager>(BusType.SESSION, MENU_DBUS_NAME, MENU_DBUS_OBJECT_PATH, 0, null, on_menu_get);
			}
		}

		/* Obtain login manager */
		void on_logind_get(Object? o, AsyncResult? res) {
			try {
				logind_proxy = Bus.get_proxy.end(res);
				if (logind_proxy != null && this.is_nvidia()) {
					logind_proxy.PrepareForSleep.connect(prepare_for_sleep);
				}
			} catch (Error e) {
				warning("Failed to get LoginD proxy: %s", e.message);
			}
		}

		/* Kudos to gnome-shell guys here: https://bugzilla.gnome.org/show_bug.cgi?id=739178 */
		void prepare_for_sleep(bool suspending) {
			if (suspending) return;
			Meta.Background.refresh_all();
		}

		void get_logind() {
			if (logind_proxy == null) {
				Bus.get_proxy.begin<LoginDRemote>(BusType.SYSTEM, LOGIND_DBUS_NAME, LOGIND_DBUS_OBJECT_PATH, 0, null, on_logind_get);
			}
		}

		void lost_switcher() {
			switcher_proxy = null;
		}

		void on_switcher_get(Object? o, AsyncResult? res) {
			try {
				switcher_proxy = Bus.get_proxy.end(res);
			} catch (Error e) {
				warning("Failed to get Switcher proxy: %s", e.message);
			}
		}

		void has_switcher() {
			if (switcher_proxy == null) {
				Bus.get_proxy.begin<Switcher>(BusType.SESSION, SWITCHER_DBUS_NAME, SWITCHER_DBUS_OBJECT_PATH, 0, null, on_switcher_get);
			}
		}

		void has_power_dialog() {
			if (power_proxy == null) {
				Bus.get_proxy.begin<PowerDialog>(BusType.SESSION, POWER_DIALOG_DBUS_NAME, POWER_DIALOG_DBUS_OBJECT_PATH, 0, null, on_power_dialog_get);
			}
		}

		void on_power_dialog_get(Object? o, AsyncResult? res) {
			try {
				power_proxy = Bus.get_proxy.end(res);
			} catch (Error e) {
				warning("Failed to get Power Dialog proxy: %s", e.message);
			}
		}

		void lost_power_dialog() {
			power_proxy = null;
		}

		/* Binding for showing the Power Dialog */
		void on_show_power_dialog(Meta.Display display, Meta.Window? window, Clutter.KeyEvent? event, Meta.KeyBinding binding) {
			if (power_proxy == null) return;

			power_proxy.Toggle.begin((obj, res) => {
				try {
					power_proxy.Toggle.end(res);
				} catch (Error e) {
					warning("Unable to toggle Power Dialog: %s", e.message);
				}
			});
		}

		/* Binding for take-full-screenshot */
		void on_take_full_screenshot(Meta.Display display, Meta.Window? window, Clutter.KeyEvent? event, Meta.KeyBinding binding) {
			try {
				string cmd=this.settings.get_string("full-screenshot-cmd");
				if (cmd != "") {
					Process.spawn_command_line_async(cmd);
				} else {
					screenshotcontrol_proxy.StartFullScreenshot.begin((obj,res) => {
						try {
							screenshotcontrol_proxy.StartFullScreenshot.end(res);
						} catch (Error e) {
							message("Failed to StartFullScreenshot: %s", e.message);
						}
					});
				}

			} catch (SpawnError e) {
				print("Error: %s\n", e.message);
			}
		}

		/* Binding for take-region-screenshot */
		void on_take_region_screenshot(Meta.Display display, Meta.Window? window, Clutter.KeyEvent? event, Meta.KeyBinding binding) {
			try {
				string cmd=this.settings.get_string("take-region-screenshot-cmd");
				if (cmd != "") {
					Process.spawn_command_line_async(cmd);
				} else {
					screenshotcontrol_proxy.StartAreaSelect.begin((obj,res) => {
						try {
							screenshotcontrol_proxy.StartAreaSelect.end(res);
						} catch (Error e) {
							message("Failed to StartAreaSelect: %s", e.message);
						}
					});
				}

			} catch (SpawnError e) {
				print("Error: %s\n", e.message);
			}
		}

		/* Binding for take-window-screenshot */
		void on_take_window_screenshot(Meta.Display display, Meta.Window? window, Clutter.KeyEvent? event, Meta.KeyBinding binding) {
			try {
				string cmd=this.settings.get_string("take-window-screenshot-cmd");
				if (cmd != "") {
					Process.spawn_command_line_async(cmd);
				} else {
					screenshotcontrol_proxy.StartWindowScreenshot.begin((obj,res) => {
						try {
							screenshotcontrol_proxy.StartWindowScreenshot.end(res);
						} catch (Error e) {
							message("Failed to StartWindowScreenshot: %s", e.message);
						}
					});
				}
			} catch (SpawnError e) {
				print("Error: %s\n", e.message);
			}
		}

		/* Binding for clear-notifications activated */
		void on_raven_notification_clear(Meta.Display display,
										Meta.Window? window, Clutter.KeyEvent? event,
										Meta.KeyBinding binding) {
			if (raven_proxy == null) {
				warning("Raven does not appear to be running!");
				return;
			}

			raven_proxy.ClearNotifications.begin((obj,res) => {
				try {
					raven_proxy.ClearNotifications.end(res);
				} catch (Error e) {
					warning("Unable to ClearNotifications() in Raven: %s", e.message);
				}
			});
		}

		/* Binding for toggle-raven activated */
		void on_raven_main_toggle(Meta.Display display,
								Meta.Window? window, Clutter.KeyEvent? event,
								Meta.KeyBinding binding) {
			if (raven_proxy == null) {
				warning("Raven does not appear to be running!");
				return;
			}

			raven_proxy.ToggleAppletView.begin((obj,res) => {
				try {
					raven_proxy.ToggleAppletView.end(res);
				} catch (Error e) {
					warning("Unable to ToggleAppletView() in Raven: %s", e.message);
				}
			});
		}

		/* Binding for toggle-notifications activated */
		void on_raven_notification_toggle(Meta.Display display,
										Meta.Window? window, Clutter.KeyEvent? event,
										Meta.KeyBinding binding) {
			if (raven_proxy == null) {
				warning("Raven does not appear to be running!");
				return;
			}

			raven_proxy.ToggleNotificationsView.begin((obj,res) => {
				try {
					raven_proxy.ToggleNotificationsView.end(res);
				} catch (Error e) {
					warning("Unable to ToggleNotificationsView() in Raven: %s", e.message);
				}
			});
		}

		/* Set up the proxy when screenshotcontrol appears */
		void has_screenshotcontrol() {
			if (screenshotcontrol_proxy == null) {
				Bus.get_proxy.begin<ScreenshotControl>(BusType.SESSION, SCREENSHOTCONTROL_DBUS_NAME, SCREENSHOTCONTROL_DBUS_OBJECT_PATH, 0, null, on_screenshotcontrol_get);
			}
		}

		void lost_screenshotcontrol() {
			screenshotcontrol_proxy = null;
		}

		/* Set up the proxy when raven appears */
		void has_raven() {
			if (raven_proxy == null) {
				Bus.get_proxy.begin<RavenRemote>(BusType.SESSION, RAVEN_DBUS_NAME, RAVEN_DBUS_OBJECT_PATH, 0, null, on_raven_get);
			}
		}

		void lost_raven() {
			raven_proxy = null;
		}

		public override unowned Meta.PluginInfo? plugin_info() {
			return info;
		}

		void on_overlay_key() {
			if (panel_proxy == null) return;
			if (enabled_experimental_run_diag_as_menu) { // Use Budgie Run Dialog
				try {
					Process.spawn_command_line_async("budgie-run-dialog");
				} catch (Error e) {
					message("Failed to launch Budgie Run Dialog: %s", e.message);
				}
			} else {
				Idle.add(() => {
					panel_proxy.ActivateAction.begin((int) PanelAction.MENU, (obj,res) => {
						try {
							panel_proxy.ActivateAction.end(res);
						} catch (Error e) {
							message("Unable to ActivateAction for menu: %s", e.message);
						}
					});

					return false;
				});
			}
		}

		void launch_menu(Meta.Display display,
						Meta.Window? window, Clutter.KeyEvent? event,
						Meta.KeyBinding binding) {
			on_overlay_key();
		}

		void launch_rundialog(Meta.Display display,
								Meta.Window? window, Clutter.KeyEvent? event,
								Meta.KeyBinding binding) {
			try {
				Process.spawn_command_line_async("budgie-run-dialog");
			} catch (Error e) {}
		}

		void on_dialog_closed(Pid pid, int status) {
			bool ok = false;
			try {
				ok = Process.check_exit_status(status);
			} catch (Error e) {
			}
			this.complete_display_change(ok);
		}

		/*
		 * This is a rewrite of Meta.Util.show_dialog because question dialogs via zenity do not have the --no-wrap parameter
		 * which leads to derpy looking dialogs with text squashed into one button column.
		 */
		private Pid show_dialog(string type, string message, string timeout, string ok_text, string cancel_text, string icon_name) {
			Pid child_pid;

			try {
#if HAVE_NEW_ZENITY
				string[] spawn_args = {
					"zenity", type, "--no-wrap",  "--title", "", "--text", message,
					"--timeout", timeout, "--ok-label", ok_text, "--cancel-label", cancel_text, "--icon", icon_name
				};
#else
				string[] spawn_args = {
					"zenity", type, "--no-wrap", "--class", "mutter-dialog", "--title", "", "--text", message,
					"--timeout", timeout, "--ok-label", ok_text, "--cancel-label", cancel_text, "--icon-name", icon_name
				};
#endif
				Process.spawn_async("/",
					spawn_args,
					null,
					SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
					null,
					out child_pid);
			} catch (SpawnError e) {
				warning("Error: %s\n", e.message);
			}

			return child_pid;
		}

		public override void confirm_display_change() {
			Pid pid = show_dialog("--question",
							"Does the display look OK?\n\nRequires a restart to apply all changes.",
							"20",
							"_Keep This Configuration",
							"_Restore Previous Configuration",
							"preferences-desktop-display");

			ChildWatch.add(pid, on_dialog_closed);
		}

		delegate unowned string GlQueryFunc(uint id);
		const uint GL_VENDOR = 0x1F00;

		private bool is_nvidia() {
			var ptr = (GlQueryFunc)Cogl.get_proc_address("glGetString");

			if (ptr == null) return false;

			unowned string? ret = ptr(GL_VENDOR);
			if (ret != null && "NVIDIA Corporation" in ret) {
				return true;
			}
			return false;
		}

		public override void start() {
			var display = this.get_display();
			display_group = Meta.Compositor.get_window_group_for_display(display);
			var stage = Meta.Compositor.get_stage_for_display(display);

			state_map = new HashTable<Meta.WindowActor?, AnimationState?>(direct_hash, direct_equal);

			iface_settings = new Settings("org.gnome.desktop.interface");
			iface_settings.bind("enable-animations", this, "use-animations", SettingsBindFlags.DEFAULT);

			settings = new Settings(WM_SCHEMA);
			gnome_desktop_prefs = new Settings("org.gnome.desktop.wm.preferences");
			this.settings.changed.connect(this.on_wm_schema_changed);
			this.on_wm_schema_changed(EXPERIMENTAL_DIALOG);
			this.on_wm_schema_changed(WM_ENABLE_UNREDIRECT);

			this.update_workspace_count(); // Update (create if necessary) our workspaces
			gnome_desktop_prefs.changed["num-workspaces"].connect(this.update_workspace_count);

			/* Custom keybindings */
			display.add_keybinding("clear-notifications", settings, Meta.KeyBindingFlags.NONE, on_raven_notification_clear);
			display.add_keybinding("take-full-screenshot", settings, Meta.KeyBindingFlags.NONE, on_take_full_screenshot);
			display.add_keybinding("take-region-screenshot", settings, Meta.KeyBindingFlags.NONE, on_take_region_screenshot);
			display.add_keybinding("take-window-screenshot", settings, Meta.KeyBindingFlags.NONE, on_take_window_screenshot);
			display.add_keybinding("toggle-raven", settings, Meta.KeyBindingFlags.NONE, on_raven_main_toggle);
			display.add_keybinding("toggle-notifications", settings, Meta.KeyBindingFlags.NONE, on_raven_notification_toggle);
			display.add_keybinding("show-power-dialog", settings, Meta.KeyBindingFlags.NONE, on_show_power_dialog);
			display.overlay_key.connect(on_overlay_key);

			/* Hook up Raven handler.. */
			Bus.watch_name(BusType.SESSION, RAVEN_DBUS_NAME, BusNameWatcherFlags.NONE,
				has_raven, lost_raven);

			/* Panel manager */
			Bus.watch_name(BusType.SESSION, PANEL_DBUS_NAME, BusNameWatcherFlags.NONE,
				has_panel, lost_panel);

			/* Menu manager */
			Bus.watch_name(BusType.SESSION, MENU_DBUS_NAME, BusNameWatcherFlags.NONE,
				has_menu, lost_menu);

			/* TabSwitcher */
			Bus.watch_name(BusType.SESSION, SWITCHER_DBUS_NAME, BusNameWatcherFlags.NONE,
				has_switcher, lost_switcher);

			/* Power Dialog */
			Bus.watch_name(BusType.SESSION, POWER_DIALOG_DBUS_NAME, BusNameWatcherFlags.NONE,
				has_power_dialog, lost_power_dialog);

			/* ScreenshotControl */
			Bus.watch_name(BusType.SESSION, SCREENSHOTCONTROL_DBUS_NAME, BusNameWatcherFlags.NONE,
				has_screenshotcontrol, lost_screenshotcontrol);

			/* Keep an eye out for systemd stuffs */
			if (have_logind()) {
				get_logind();
			}

			Meta.KeyBinding.set_custom_handler("panel-main-menu", launch_menu);
			Meta.KeyBinding.set_custom_handler("panel-run-dialog", launch_rundialog);
			Meta.KeyBinding.set_custom_handler("switch-windows", switch_windows);
			Meta.KeyBinding.set_custom_handler("switch-windows-backward", switch_windows_backward);
			Meta.KeyBinding.set_custom_handler("switch-applications", switch_windows);
			Meta.KeyBinding.set_custom_handler("switch-applications-backward", switch_windows_backward);

			shim = new ShellShim(this);
			shim.serve();

			focus_interface = new BudgieWMDBUS(this);
			focus_interface.serve();

			background_group = new Meta.BackgroundGroup();
			background_group.set_reactive(true);
			display_group.insert_child_below(background_group, null);
			background_group.button_release_event.connect(on_background_click);

			Meta.Context ctx = display.get_context();

			var monitor_manager = ctx.get_backend().get_monitor_manager();
			monitor_manager.monitors_changed.connect(on_monitors_changed);
			on_monitors_changed();

			background_group.show();
			display_group.show();
			stage.show();

			keyboard = new KeyboardManager(this);
			keyboard.hook_extra();

			display.get_workspace_manager().override_workspace_layout(Meta.DisplayCorner.TOPLEFT, false, 1, -1);

			screenshot = ScreenshotManager.init(this);
			screenshot.setup_dbus();
		}

		/**
		* Launch menu manager with our wallpaper
		*/
		private bool on_background_click(Clutter.ButtonEvent? event) {
			if (event.button == 1) {
				this.dismiss_raven();
			} else if (event.button == 3) {
				if (menu_proxy == null) {
					return CLUTTER_EVENT_STOP;
				}

				menu_proxy.ShowDesktopMenu.begin(3, 0, (obj,res) => {
					try {
						menu_proxy.ShowDesktopMenu.end(res);
					} catch (Error e) {
						message("Error invoking MenuManager: %s", e.message);
					}
				});
			} else {
				return CLUTTER_EVENT_PROPAGATE;
			}

			return CLUTTER_EVENT_STOP;
		}

		private void on_wm_schema_changed(string key) {
			if (key == EXPERIMENTAL_DIALOG) { // Key changed was the experimental enable
				enabled_experimental_run_diag_as_menu = this.settings.get_boolean(key);
			} else if (key == WM_ENABLE_UNREDIRECT) {
				set_redirection_mode(this.settings.get_boolean(key));
			}
		}

		public void set_redirection_mode(bool enable) {
			var display = this.get_display();
			if (enable) {
				Meta.Compositor.enable_unredirect_for_display(display);
			} else {
				Meta.Compositor.disable_unredirect_for_display(display);
			}
			this.enable_unredirect = enable;
		}

		public override void show_window_menu(Meta.Window window, Meta.WindowMenuType type, int x, int y) {
			if (type != Meta.WindowMenuType.WM) return;
			if (menu_proxy == null) return;
			Timeout.add(100, () => {
				uint32 xid = (uint32)window.get_xwindow();
				menu_proxy.ShowWindowMenu.begin(xid, 3, 0, (obj, res) => {
					try {
						menu_proxy.ShowWindowMenu.end(res);
					} catch (Error e) {
						message("Error invoking MenuManager: %s", e.message);
					}
				});

				return false;
			});
		}

		/**
		* update_workspace_count will update our workspace count trigger workspace creation / removal
		*/
		public void update_workspace_count() {
			unowned Meta.WorkspaceManager wsm = get_display().get_workspace_manager();
			int current_workspace_count = wsm.get_n_workspaces();
			int new_workspace_count = gnome_desktop_prefs.get_int("num-workspaces"); // Get the new amount of workspaces

			if (new_workspace_count > 8) { // If the total amount of workspaces is excessive
				gnome_desktop_prefs.set_int("num-workspaces", 8); // Force to max of 8
			}

			if (new_workspace_count != current_workspace_count) { // If there is an actual difference
				if (new_workspace_count > current_workspace_count) { // If we should be adding workspaces
					while (wsm.get_n_workspaces() < new_workspace_count) {
						wsm.append_new_workspace(false, get_display().get_current_time());
					}
				} else { // Workspaces to remove
					while (wsm.get_n_workspaces() > new_workspace_count) {
						var last_workspace = wsm.get_workspace_by_index(wsm.get_n_workspaces() - 1);

						if (last_workspace != null) {
							wsm.remove_workspace(last_workspace, get_display().get_current_time());
						}
					}
				}
			}
		}

		/* Dismiss raven from view. Consider in future tracking the visible
		* state
		*/
		void dismiss_raven() {
			if (raven_proxy != null) {
				raven_proxy.Dismiss.begin();
			}
		}

		void on_monitors_changed() {
		var display = get_display();
			background_group.destroy_all_children();

			for (int i = 0; i < display.get_n_monitors(); i++) {
				var actor = new BudgieBackground(display, i, this);
				background_group.add_child(actor);
			}
		}

		const int MAP_TIMEOUT = 100;
		const int MENU_MAP_TIMEOUT = 120;
		const float MAP_SCALE = 0.94f;
		const float MENU_MAP_SCALE_X = 0.98f;
		const float MENU_MAP_SCALE_Y = 0.95f;
		const float NOTIFICATION_MAP_SCALE_X = 0.5f;
		const float NOTIFICATION_MAP_SCALE_Y = 0.8f;
		const int FADE_TIMEOUT = 145;

		void finalize_animations(Meta.WindowActor? actor) {
			if (!state_map.contains(actor)) {
				return;
			}

			actor.remove_all_transitions();

			unowned AnimationState? state = state_map.lookup(actor);
			switch (state) {
				case AnimationState.MAP:
					actor.set("pivot-point", PV_NORM, "opacity", 255U);
					map_completed(actor);
					break;
				case AnimationState.DESTROY:
					destroy_completed(actor);
					break;
				case AnimationState.MINIMIZE:
					actor.set("pivot-point", PV_NORM, "opacity", 255U, "scale-x", 1.0, "scale-y", 1.0);
					actor.hide();
					minimize_completed(actor);
					break;
				case AnimationState.UNMINIMIZE:
					actor.set("pivot-point", PV_NORM, "opacity", 255U, "scale-x", 1.0, "scale-y", 1.0);
					unminimize_completed(actor);
					break;
				default:
					break;
			}
			state_map.remove(actor);
		}

		void map_done(Clutter.Actor? actor) {
			SignalHandler.disconnect_by_func(actor, (void*)map_done, this);
			finalize_animations(actor as Meta.WindowActor);
		}

		private unowned Meta.Window? focused_window = null;

		/**
		* Store the focused window
		*/
		public void store_focused() {
			var workspace = get_display().get_workspace_manager().get_active_workspace();
			if (workspace == null) return;
			foreach (var window in workspace.list_windows()) {
				if (window.has_focus()) {
					focused_window = window;
					break;
				}
			}
		}

		/**
		* Restore the focused window
		*/
		public void restore_focused() {
			if (focused_window == null) return;
			focused_window.focus(get_display().get_current_time());
			focused_window = null;
		}

		public override void map(Meta.WindowActor actor) {
			Meta.Window? window = actor.get_meta_window();

			if (!use_animations) {
				this.map_completed(actor);
				return;
			}

			switch (window.get_window_type()) {
				case Meta.WindowType.POPUP_MENU:
				case Meta.WindowType.DROPDOWN_MENU:
				case Meta.WindowType.MENU:
					actor.set("opacity", 0U, "scale-x", MENU_MAP_SCALE_X, "scale-y", MENU_MAP_SCALE_Y,
						"pivot-point", PV_CENTER);
					actor.show();

					actor.save_easing_state();
					actor.set_easing_mode(Clutter.AnimationMode.EASE_OUT_CIRC);
					actor.set_easing_duration(MENU_MAP_TIMEOUT);

					actor.set("scale-x", 1.0, "scale-y", 1.0, "opacity", 255U);
					break;
				case Meta.WindowType.NOTIFICATION:
					if (window.get_wm_class() == "raven") {
						this.map_completed(actor);
						return;
					}
					actor.set("opacity", 0U, "scale-x", NOTIFICATION_MAP_SCALE_X, "scale-y", NOTIFICATION_MAP_SCALE_Y,
						"pivot-point", PV_CENTER);
					actor.show();

					actor.save_easing_state();
					actor.set_easing_mode(Clutter.AnimationMode.EASE_OUT_QUART);
					actor.set_easing_duration(MAP_TIMEOUT);

					actor.set("scale-x", 1.0, "scale-y", 1.0, "opacity", 255U);
					break;
				case Meta.WindowType.NORMAL:
				case Meta.WindowType.DIALOG:
				case Meta.WindowType.MODAL_DIALOG:
					actor.set("opacity", 0U, "scale-x", MAP_SCALE, "scale-y", MAP_SCALE,
						"pivot-point", PV_CENTER);
					actor.show();

					actor.save_easing_state();
					actor.set_easing_mode(Clutter.AnimationMode.EASE_OUT_QUAD);
					actor.set_easing_duration(MAP_TIMEOUT);

					actor.set("scale-x", 1.0, "scale-y", 1.0, "opacity", 255U);
					break;
				default:
					this.map_completed(actor);
					return;
			}

			actor.transitions_completed.connect(map_done);
			state_map.insert(actor, AnimationState.MAP);
			actor.restore_easing_state();
		}

		void minimize_done(Clutter.Actor? actor) {
			SignalHandler.disconnect_by_func(actor, (void*)minimize_done, this);
			finalize_animations(actor as Meta.WindowActor);
		}

		const int MINIMIZE_TIMEOUT = 225;

		public override void minimize(Meta.WindowActor actor) {
			if (!this.use_animations) {
				this.minimize_completed(actor);
				return;
			}

			Meta.Rectangle icon;
			Meta.Window? window = actor.get_meta_window();

			if (window.get_window_type() != Meta.WindowType.NORMAL) {
				this.minimize_completed(actor);
				return;
			}

			if (!window.get_icon_geometry(out icon)) {
				icon.x = 0;
				icon.y = 0;
			}

			finalize_animations(actor);

			state_map.insert(actor, AnimationState.MINIMIZE);
			actor.save_easing_state();
			actor.set_easing_mode(Clutter.AnimationMode.EASE_IN_QUAD);
			actor.set_easing_duration(MINIMIZE_TIMEOUT);
			actor.transitions_completed.connect(minimize_done);

			Meta.Display display = this.get_display();
			Meta.Context ctx = display.get_context();

			/* Save the minimize state for later restoration */
			var scale_factor = ctx.get_backend().get_settings().get_ui_scaling_factor();
			var scale_x = (float)((icon.width * scale_factor) / actor.width);
			var scale_y = (float)((icon.height * scale_factor) / actor.height);
			var place_x = (float)icon.x * scale_factor;
			var place_y = (float)icon.y * scale_factor;
			var old_x = (float)actor.x;
			var old_y = (float)actor.y;

			MinimizeData d = new MinimizeData(scale_x, scale_y, place_x, place_y, old_x, old_y);

			actor.set_data("_minimize_data", d);
			actor.set_scale(d.scale_x, d.scale_y);
			actor.set_x(d.place_x);
			actor.set_y(d.place_y);
			actor.opacity = 0U;
			actor.set_content_gravity(Clutter.ContentGravity.TOP_LEFT);
			actor.set_pivot_point(0f, 0f);
			actor.restore_easing_state();
		}

		/**
		* Unminimize now done
		*/
		void unminimize_done(Clutter.Actor? actor) {
			SignalHandler.disconnect_by_func(actor, (void*)unminimize_done, this);
			finalize_animations(actor as Meta.WindowActor);
		}

		const int UNMINIMIZE_TIMEOUT = 200;

		/**
		* Handle unminimize animation
		*/
		public override void unminimize(Meta.WindowActor actor) {
			if (!this.use_animations) {
				this.unminimize_completed(actor);
				return;
			}

			MinimizeData? d = actor.get_data("_minimize_data");
			if (d == null) {
				this.unminimize_completed(actor);
				return;
			}

			finalize_animations(actor);

			actor.set_pivot_point(0f, 0f);
			actor.set_scale(d.scale_x, d.scale_y);
			actor.set_x(d.place_x);
			actor.set_y(d.place_y);
			actor.opacity = 0U;

			actor.show();

			actor.save_easing_state();
			actor.set_easing_mode(Clutter.AnimationMode.EASE_OUT_QUAD);
			actor.set_easing_duration(UNMINIMIZE_TIMEOUT);

			actor.set_scale(1.0f, 1.0f);
			actor.opacity = 255U;
			actor.set_x(d.old_x);
			actor.set_y(d.old_y);

			actor.transitions_completed.connect(unminimize_done);
			state_map.insert(actor, AnimationState.UNMINIMIZE);
			actor.restore_easing_state();

			actor.set_data("_minimize_data", null);
		}

		void destroy_done(Clutter.Actor? actor) {
			SignalHandler.disconnect_by_func(actor, (void*)destroy_done, this);
			finalize_animations(actor as Meta.WindowActor);
		}

		const int DESTROY_TIMEOUT = 120;
		const double DESTROY_SCALE = 0.88;

		public override void destroy(Meta.WindowActor actor) {
			Meta.Window? window = actor.get_meta_window();

			if (focused_window == window) {
				focused_window = null;
			}

			if (!this.use_animations) {
				this.destroy_completed(actor);
				return;
			}

			finalize_animations(actor);

			switch (window.get_window_type()) {
				case Meta.WindowType.NOTIFICATION:
				case Meta.WindowType.NORMAL:
				case Meta.WindowType.DIALOG:
				case Meta.WindowType.MODAL_DIALOG:
					actor.set("pivot-point", PV_CENTER);
					actor.save_easing_state();
					actor.set_easing_mode(Clutter.AnimationMode.EASE_OUT_QUAD);
					actor.set_easing_duration(DESTROY_TIMEOUT);

					actor.set("scale-x", DESTROY_SCALE, "scale-y", DESTROY_SCALE, "opacity", 0U);
					break;
				case Meta.WindowType.MENU:
				case Meta.WindowType.POPUP_MENU:
				case Meta.WindowType.DROPDOWN_MENU:
					actor.set("pivot-point", PV_CENTER);
					actor.save_easing_state();
					actor.set_easing_mode(Clutter.AnimationMode.EASE_OUT_QUAD);
					actor.set_easing_duration(DESTROY_TIMEOUT);
					actor.set("opacity", 0U);
					break;
				default:
					this.destroy_completed(actor);
					return;
			}

			actor.transitions_completed.connect(destroy_done);
			state_map.insert(actor, AnimationState.DESTROY);
			actor.restore_easing_state();
		}

		private ScreenTilePreview? tile_preview = null;
		private uint8? default_tile_opacity = null;

		/* Ported from old budgie-wm, in turn ported from Mutter's default plugin */
		public override void show_tile_preview(Meta.Window window, Meta.Rectangle tile_rect, int tile_monitor_num) {
			var display = this.get_display();

			if (this.tile_preview == null) {
				this.tile_preview = new ScreenTilePreview();
				this.tile_preview.transitions_completed.connect(tile_preview_transition_complete);

				var display_group = Meta.Compositor.get_window_group_for_display(display);
				display_group.add_child(this.tile_preview);

				default_tile_opacity = this.tile_preview.get_opacity();
			}

			if (tile_preview.visible &&
				tile_preview.tile_rect.x == tile_rect.x &&
				tile_preview.tile_rect.y == tile_rect.y &&
				tile_preview.tile_rect.width == tile_rect.width &&
				tile_preview.tile_rect.height == tile_rect.height) {
				return;
			}

			var win_actor = window.get_compositor_private() as Clutter.Actor;

			tile_preview.remove_all_transitions();
			tile_preview.set_position(win_actor.x, win_actor.y);
			tile_preview.set_size(win_actor.width, win_actor.height);
			tile_preview.set_opacity(default_tile_opacity);
			tile_preview.set("scale-x", NOTIFICATION_MAP_SCALE_X, "scale-y", NOTIFICATION_MAP_SCALE_Y,
				"pivot-point", PV_CENTER);

			//tile_preview.lower(win_actor);
			tile_preview.tile_rect = tile_rect;

			tile_preview.show();

			tile_preview.save_easing_state();
			tile_preview.set_easing_mode(Clutter.AnimationMode.EASE_OUT_QUAD);
			tile_preview.set_easing_duration(MAP_TIMEOUT);

			tile_preview.set_position(tile_rect.x, tile_rect.y);
			tile_preview.set_size(tile_rect.width, tile_rect.height);

			tile_preview.set("scale-x", 1.0, "scale-y", 1.0);
			tile_preview.restore_easing_state();

		}

		public override void hide_tile_preview() {
			if (tile_preview != null) {
				tile_preview.remove_all_transitions();
				tile_preview.save_easing_state();
				tile_preview.set_easing_mode(Clutter.AnimationMode.EASE_OUT_QUAD);
				tile_preview.set_easing_duration(FADE_TIMEOUT);
				tile_preview.set_opacity(0);
				tile_preview.restore_easing_state();
			}
		}

		private void tile_preview_transition_complete() {
			if (tile_preview.get_opacity() == 0x00) {
				this.tile_preview.hide();
			}
		}

		public void switch_windows_backward(Meta.Display display,
						Meta.Window? window, Clutter.KeyEvent? event,
						Meta.KeyBinding binding) {
			switch_switcher(true);
		}

		public void switch_windows(Meta.Display display,
						Meta.Window? window, Clutter.KeyEvent? event,
						Meta.KeyBinding binding) {
			switch_switcher();
		}

		public void switch_switcher(bool backwards = false) {
			switcher_proxy.ShowSwitcher.begin(backwards);
		}

		public void stop_switch_windows() {
			switcher_proxy.StopSwitcher.begin();
		}


		/* EVEN MORE LEVELS OF DERP. */
		Clutter.Actor? out_group = null;
		Clutter.Actor? in_group = null;
		public override void kill_switch_workspace() {
			if (this.out_group != null) {
				out_group.transitions_completed();
			}
		}

		void switch_workspace_done() {
			var display = this.get_display();

			foreach (var actor in Meta.Compositor.get_window_actors(display)) {
				actor.show();

				Clutter.Actor? orig_parent = actor.get_data("orig-parent");
				if (orig_parent == null) {
					continue;
				}

				actor.ref();
				actor.get_parent().remove_child(actor);
				orig_parent.add_child(actor);
				actor.unref();

				actor.set_data("orig-parent", null);
			}

			SignalHandler.disconnect_by_func(out_group, (void*)switch_workspace_done, this);

			out_group.remove_all_transitions();
			in_group.remove_all_transitions();
			out_group.destroy();
			out_group = null;
			in_group.destroy();
			in_group = null;

			this.switch_workspace_completed();
		}


		public const int SWITCH_TIMEOUT = 250;
		public override void switch_workspace(int from, int to, Meta.MotionDirection direction) {
			if (raven_proxy != null) { // Raven proxy is defined
				raven_proxy.Dismiss.begin((obj,res) => {
					try {
						raven_proxy.Dismiss.end(res);
					} catch (Error e) {
						warning("Failed to dismiss Raven: %s", e.message);
					}
				}); // Dismiss

				Timeout.add(200, () => {return false;}); // Delay until animation is complete. Looks janky otherwise
			}

			bool use_animations = iface_settings.get_boolean("enable-animations");

			// Stop the Switcher if it was showing
			this.stop_switch_windows();

			int screen_width;
			int screen_height;

			if (from == to) {
				this.switch_workspace_completed();
				return;
			}

			var display = this.get_display();
			var stage = Meta.Compositor.get_stage_for_display(display);
			display.get_size(out screen_width, out screen_height);

			out_group = new Clutter.Actor();
			in_group = new Clutter.Actor();

			stage.add_child(in_group);
			stage.add_child(out_group);
			stage.set_child_above_sibling(in_group, null);

			/* TODO: Windows should slide "under" the panel/dock
			* Move "in-between" workspaces, e.g. 1->3 shows 2 */

			if (use_animations) { // If animations are enabled
				foreach (var actor in Meta.Compositor.get_window_actors(display)) {
					var window = ((Meta.WindowActor) actor).get_meta_window();

					if (!window.showing_on_its_workspace() || window.is_on_all_workspaces()) {
						continue;
					}

					var space = window.get_workspace();
					var win_space = space.index();

					if (win_space == to || win_space == from) {
						var orig_parent = actor.get_parent();
						unowned Clutter.Actor? new_parent = win_space == to ? in_group : out_group;
						actor.set_data("orig-parent", orig_parent);

						actor.ref();
						orig_parent.remove_child(actor);
						new_parent.add_child(actor);
						actor.unref();
					} else {
						actor.hide();
					}
				}
			}

			int y_dest = 0;
			int x_dest = 0;

			if (direction == Meta.MotionDirection.UP ||
				direction == Meta.MotionDirection.UP_LEFT ||
				direction == Meta.MotionDirection.UP_RIGHT) {
				y_dest = screen_height;
			} else if (direction == Meta.MotionDirection.DOWN ||
						direction == Meta.MotionDirection.DOWN_LEFT ||
						direction == Meta.MotionDirection.DOWN_RIGHT) {
				y_dest = -screen_height;
			}

			if (direction == Meta.MotionDirection.LEFT ||
				direction == Meta.MotionDirection.UP_LEFT ||
				direction == Meta.MotionDirection.DOWN_LEFT) {
				x_dest = screen_width;
			} else if (direction == Meta.MotionDirection.RIGHT ||
						direction == Meta.MotionDirection.UP_RIGHT ||
						direction == Meta.MotionDirection.DOWN_RIGHT) {
				x_dest = -screen_width;
			}

			in_group.set_position(-x_dest, -y_dest);
			in_group.save_easing_state();

			if (use_animations) { // If animations are enabled
				in_group.set_easing_mode(Clutter.AnimationMode.EASE_OUT_QUAD);
				in_group.set_easing_duration(SWITCH_TIMEOUT);
			}

			in_group.set_position(0, 0);
			in_group.restore_easing_state();

			out_group.transitions_completed.connect(switch_workspace_done);

			out_group.save_easing_state();

			if (use_animations) { // If animations are enabled
				out_group.set_easing_mode(Clutter.AnimationMode.EASE_OUT_QUAD);
				out_group.set_easing_duration(SWITCH_TIMEOUT);
			}

			out_group.set_position(x_dest, y_dest);
			out_group.restore_easing_state();
		}
	}

	/**
	* Store/restore focused window for use of the popover manager in budgie.
	* This part of the equation is inspired by wingpanel, which uses our
	* popover manager.
	*/
	[DBus (name="org.budgie_desktop.BudgieWM")]
	public class BudgieWMDBUS : GLib.Object {
		unowned Budgie.BudgieWM? wm;

		[DBus (visible=false)]
		public BudgieWMDBUS(Budgie.BudgieWM? wm) {
			this.wm = wm;
		}

		[DBus (visible=false)]
		void on_bus_acquired(DBusConnection conn) {
			try {
				conn.register_object("/org/budgie_desktop/BudgieWM", this);
			} catch (Error e) {
				message("Unable to register BudgieWMDBUS: %s", e.message);
			}
		}

		[DBus (visible=false)]
		public void serve() {
			Bus.own_name(BusType.SESSION, "org.budgie_desktop.BudgieWM",
				BusNameOwnerFlags.ALLOW_REPLACEMENT|BusNameOwnerFlags.REPLACE,
				on_bus_acquired, null, null);
		}

		public void store_focused() throws DBusError, IOError {
			this.wm.store_focused();
		}

		public void restore_focused() throws DBusError, IOError {
			this.wm.restore_focused();
		}

		public void RemoveWorkspaceByIndex(int index, uint32 time) throws DBusError, IOError {
			unowned Meta.WorkspaceManager wsm = this.wm.get_display().get_workspace_manager();
			unowned Meta.Workspace? workspace = wsm.get_workspace_by_index(index);
			if (workspace == null) {
				return;
			}
			wsm.remove_workspace(workspace, time);
		}

		public int AppendNewWorkspace(uint32 time) throws DBusError, IOError {
			unowned Meta.WorkspaceManager wsm = this.wm.get_display().get_workspace_manager();
			int current_count = wsm.get_n_workspaces(); // Get the current count

			if (current_count < 8) {
				unowned Meta.Workspace? space = wsm.append_new_workspace(false, time);
				return space.index();
			}

			return -1;
		}
	}
}
