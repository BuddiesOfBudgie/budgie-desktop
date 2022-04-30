using Gtk;
using Gdk;
using Cairo;
using Gst;

/*
Budgie Screenshot
Author: Jacob Vlijm
Copyright © 2022 Ubuntu Budgie Developers
Website=https://ubuntubudgie.org
This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or any later version. This
program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
A PARTICULAR PURPOSE. See the GNU General Public License for more details. You
should have received a copy of the GNU General Public License along with this
program.  If not, see <https://www.gnu.org/licenses/>.
*/

// valac --pkg cairo --pkg gtk+-3.0 --pkg gdk-3.0 --pkg gstreamer-1.0 --pkg gio-2.0

/*
* if daemon is running, use below to call its methods:
* dbus-send --session --type=method_call --dest=org.buddiesofbudgie.ScreenshotControl /org/buddiesofbudgie/ScreenshotControl org.buddiesofbudgie.ScreenshotControl.StartMainWindow
* dbus-send --session --type=method_call --dest=org.buddiesofbudgie.ScreenshotControl /org/buddiesofbudgie/ScreenshotControl org.buddiesofbudgie.ScreenshotControl.StartAreaSelect
* dbus-send --session --type=method_call --dest=org.buddiesofbudgie.ScreenshotControl /org/buddiesofbudgie/ScreenshotControl org.buddiesofbudgie.ScreenshotControl.StartFullScreenshot
* dbus-send --session --type=method_call --dest=org.buddiesofbudgie.ScreenshotControl /org/buddiesofbudgie/ScreenshotControl org.buddiesofbudgie.ScreenshotControl.StartWindowScreenshot
*/


namespace Budgie {

	ScreenshotClient client;

	enum WindowState {
		NONE,
		MAINWINDOW,
		SELECTINGAREA,
		AFTERSHOT,
		WAITINGFORSHOT,
	}

	enum ButtonPlacement {
		LEFT,
		RIGHT,
	}

	[SingleInstance]
	public class CurrentState : GLib.Object {

		GLib.Settings? buttonplacement;

		public GLib.Settings screenshot_settings {get; private set;}
		public int newstate {get; private set; default = WindowState.NONE;}
		public bool showtooltips {get; set; default = true;}
		public int buttonpos {get; private set;}
		public string tempfile_path {get; private set;}
		public bool startedfromgui {get; private set; default = false;}

		public signal void buttonpos_changed ();

		public CurrentState () {
			screenshot_settings = new GLib.Settings("org.buddiesofbudgie.screenshot");

			buttonplacement = new GLib.Settings("com.solus-project.budgie-wm");

			buttonplacement.changed["button-style"].connect(()=> {
				fill_buttonpos();
				buttonpos_changed();
			});
			fill_buttonpos();

			showtooltips = screenshot_settings.get_boolean("showtooltips");
			screenshot_settings.changed["showtooltips"].connect(()=>{
				showtooltips = screenshot_settings.get_boolean("showtooltips");
			});

			// we need to use the same temporary file across instances
			// so use the logged in user to differentiate in multiuser
			// scenarious
			string username = Environment.get_user_name();
			string tmpdir = GLib.Environment.get_tmp_dir();
			tempfile_path = tmpdir.concat("/", username, "_budgiescreenshot_tempfile");
		}

		private void fill_buttonpos() {
			if (buttonplacement.get_string("button-style")=="left") {
				buttonpos=ButtonPlacement.LEFT;
			}
			else {
				buttonpos=ButtonPlacement.RIGHT;
			}
		}

		public void statechanged(int n) {
			newstate = n;

			(newstate == 0)?  startedfromgui = false : startedfromgui;
			(newstate == 1)?  startedfromgui = true : startedfromgui;
		}
	}

	[DBus (name = "org.buddiesofbudgie.ScreenshotControl")]
	public class ScreenshotServer : GLib.Object {
		CurrentState windowstate;

		private int getcurrentstate() throws Error {
			return windowstate.newstate;
		}

		private void set_target(string target) {
			windowstate.screenshot_settings.set_string("screenshot-mode", target);
			windowstate.screenshot_settings.set_int("delay", 0);
		}

		public async void StartMainWindow() throws Error {
			if (getcurrentstate() == 0) {
				new ScreenshotHomeWindow();
			}
		}

		public async void StartAreaSelect() throws Error {
			if (getcurrentstate() == 0) {
				set_target("Selection"); // don't translate!
				new SelectLayer();
			}
		}

		public async void StartWindowScreenshot() throws Error {
			if (getcurrentstate() == 0) {
				set_target("Window"); // don't translate!
				new MakeScreenshot(null);
			}
		}

		public async void StartFullScreenshot() throws Error {
			if (getcurrentstate() == 0) {
				set_target("Screen"); // don't translate!
				new MakeScreenshot(null);
			}
		}
		public ScreenshotServer() {
			windowstate = new CurrentState();
		}

		// setup dbus
		void on_bus_acquired(DBusConnection conn) {
			// register the bus
			try {
				conn.register_object("/org/buddiesofbudgie/ScreenshotControl",	new ScreenshotServer());
			}
			catch (IOError e) {
				stderr.printf ("Could not register service\n");
			}
		}

		public void setup_dbus() throws Error {
			GLib.Bus.own_name (
				BusType.SESSION, "org.buddiesofbudgie.ScreenshotControl",
				BusNameOwnerFlags.NONE, on_bus_acquired,
				() => {}, () => stderr.printf ("Could not acquire name\n"));
		}

	}

	[DBus (name = "org.buddiesofbudgie.Screenshot")]
	public interface ScreenshotClient : GLib.Object {
		public abstract async void ScreenshotArea(int x, int y, int width, int height, bool include_cursor,	bool flash, string filename,
			out bool success, out string filename_used) throws Error;
		public abstract async void Screenshot(bool include_cursor, bool flash, string filename, out bool success, out string filename_used) throws Error;
		public abstract async void ScreenshotWindow (bool include_frame, bool include_cursor, bool flash, string filename,
			out bool success, out string filename_used) throws Error;
	}

	class MakeScreenshot {

		int delay;
		int scale;
		int[]? area;
		string screenshot_mode;
		bool include_cursor;
		bool include_frame;
		CurrentState windowstate;

		public MakeScreenshot(int[]? area) {
			windowstate = new CurrentState();
			this.area = area;
			scale = get_scaling();
			delay = windowstate.screenshot_settings.get_int("delay");
			screenshot_mode = windowstate.screenshot_settings.get_string("screenshot-mode");
			include_cursor = windowstate.screenshot_settings.get_boolean("include-cursor");
			include_frame = windowstate.screenshot_settings.get_boolean("include-frame");

			switch (screenshot_mode) {
				case "Selection":
				GLib.Timeout.add(200 + (delay*1000), ()=> {
					shoot_area.begin();

					return false;
				});
				break;
				case "Screen":
				GLib.Timeout.add(200 + (delay*1000), ()=> {
					shoot_screen.begin();

					return false;
				});
				break;
				case "Window":
				GLib.Timeout.add(200 + (delay*1000), ()=> {
					shoot_window.begin();

					return false;
				});
				break;
			}
		}

		async void shoot_window() {
			bool success = false;
			string filename_used = "";
			play_shuttersound(200);

			try {
				yield client.ScreenshotWindow(include_frame, include_cursor, true, windowstate.tempfile_path, out success, out filename_used);
			}
			catch (Error e) {
				stderr.printf ("%s, failed to make screenshot\n", e.message);
				windowstate.statechanged(WindowState.NONE);
			}

			if (success) {
				new AfterShotWindow();
			}
		}

		private async void shoot_screen() {
			bool success = false;
			string filename_used = "";

			play_shuttersound(200);

			try {
				yield client.Screenshot(include_cursor, true, windowstate.tempfile_path, out success, out filename_used);
			}
			catch (Error e) {
				stderr.printf ("%s, failed to make screenhot\n", e.message);
				windowstate.statechanged(WindowState.NONE);
			}
			if (success) {
				new AfterShotWindow();
			}
		}

		async void shoot_area() {
			bool success = false;
			string filename_used = "";
			int topleftx = this.area[0];
			int toplefty = this.area[1];
			int width = this.area[2];
			int height = this.area[3];
			// if we just click, forget to drag, set w/h to 1px
			(height == 0)? height = 1 : height;
			(width == 0)? width = 1 : width;

			play_shuttersound(0);

			try {
				yield client.ScreenshotArea (
					topleftx*scale, toplefty*scale, width*scale, height*scale,
					include_cursor, true, windowstate.tempfile_path, out success, out filename_used
				);
			}
			catch (Error e) {
				stderr.printf ("%s, failed to make screenhot\n", e.message);
				windowstate.statechanged(WindowState.NONE);
			}
			if (success) {
				new AfterShotWindow();
			}
		}

		private void play_shuttersound(int timeout, string[]? args=null) {
			// todo: we should probably not hardcode the soundfile?
			try {
				var check = Gst.init_check(ref args);
				if (!check) {
					warning("Could not initialise gstreamer");
					return;
				}
			}
			catch (Error e) {
				error ("Error: %s", e.message);
			}
			Gst.Element pipeline;

			try {
				pipeline = Gst.parse_launch(
					"playbin uri=file:///usr/share/sounds/freedesktop/stereo/screen-capture.oga"
				);
			}
			catch (Error e) {
				error ("Error: %s", e.message);
			}

			GLib.Timeout.add(timeout, ()=> {
				// fake thread to make sure flash and shutter are in sync
				pipeline.set_state(State.PLAYING);
				Gst.Bus bus = pipeline.get_bus();
				bus.timed_pop_filtered(
					Gst.CLOCK_TIME_NONE, Gst.MessageType.ERROR | Gst.MessageType.EOS
				);
				pipeline.set_state (Gst.State.NULL);

				return false;
			});
		}
	}

	[GtkTemplate (ui="/org/buddiesofbudgie/Screenshot/screenshothome.ui")]
	class ScreenshotHomeWindow : Gtk.Window {

		Gtk.HeaderBar topbar;
		CurrentState windowstate;
		int selectmode = 0;
		bool ignore = false;
		Label[] shortcutlabels;
		ulong? button_id=null;

		[GtkChild]
		private unowned Gtk.Grid? maingrid;

		[GtkChild]
		private unowned Gtk.SpinButton? delayspin;

		[GtkChild]
		private unowned Gtk.Switch? showpointerswitch;

		public ScreenshotHomeWindow() {
			windowstate=new CurrentState();
			this.set_keep_above(true);
			windowstate.statechanged(WindowState.MAINWINDOW);

			var theme = Gtk.IconTheme.get_default();
			theme.add_resource_path ("/org/buddiesofbudgie/Screenshot/icons/scalable/apps/");

			string home_css = """
			.buttonlabel {
				margin-top: -12px;
			}
			.centerbutton {
				border-radius: 0px 0px 0px 0px;
				border-width: 0px;
			}
			.optionslabel {
				margin-left: 12px;
				margin-bottom: 2px;
			}
			.popoverheader {
				margin-bottom: 5px;
				font-weight: bold;
			}
			""";

			topbar = new Gtk.HeaderBar();
			topbar.show_close_button = true;
			this.set_titlebar(topbar);

			/*
			/ left or right windowbuttons, that's the question when
			/ (re-?) arranging headerbar buttons
			*/
			button_id=windowstate.buttonpos_changed.connect(()=> {rearrange_headerbar();});
			rearrange_headerbar();

			// css stuff
			Gdk.Screen screen = this.get_screen();
			Gtk.CssProvider css_provider = new Gtk.CssProvider();

			try {
				css_provider.load_from_data(home_css);
				Gtk.StyleContext.add_provider_for_screen(screen, css_provider, Gtk.STYLE_PROVIDER_PRIORITY_USER);
			}
			catch (Error e) {
				// not much to be done
				warning("Error loading css data\n");
			}

			// so, let's add some content - areabuttons
			Gtk.Box areabuttonbox = setup_areabuttons();
			maingrid.attach(areabuttonbox, 0, 0, 1, 1);;

			// - show pointer
			windowstate.screenshot_settings.bind("include-cursor", showpointerswitch, "active",	SettingsBindFlags.GET|SettingsBindFlags.SET);

			// - delay
			windowstate.screenshot_settings.bind("delay", delayspin, "value", SettingsBindFlags.GET|SettingsBindFlags.SET);

			this.destroy.connect(()=> {
				// prevent WindowState.NONE if follow up button is pressed
				GLib.Timeout.add(100, ()=> {
					if (windowstate.newstate == WindowState.MAINWINDOW) {
						windowstate.statechanged(WindowState.NONE);
					}

					return false;
				});
			});
			this.show_all();
		}

		private void update_current_shortcuts() {
			GLib.Settings scrshot_shortcuts = new GLib.Settings("com.solus-project.budgie-wm");
			string[] keyvals = {
				"take-full-screenshot",
				"take-window-screenshot",
				"take-region-screenshot"
			};
			int currshot = 0;
			foreach (string s in keyvals) {
				Variant shc = scrshot_shortcuts.get_strv(s);
				string shc_action = (string)shc.get_child_value(0);
				string newaction = shc_action.replace("<", "").replace(">", " + ");

				// let's do capital
				string[] newaction_steps = newaction.split(" + ");
				int action_len = newaction_steps.length;
				if (action_len == 2 && newaction_steps[1].length == 1) {
					newaction = newaction.replace(newaction_steps[1], newaction_steps[1].up());
				}
				shortcutlabels[currshot].set_text(newaction);
				currshot += 1;
			}
		}

		private Gtk.Popover make_info_popover(Button b) {
			Gtk.Popover newpopover = new Gtk.Popover(b);
			Grid popovergrid = new Gtk.Grid();
			set_margins(popovergrid, 15, 15, 15, 15);
			Label[] shortcutnames = {
				// Translators: be as brief as possible; popovers ar cut off if broader than the window
				new Label(_("Screenshot entire screen") + ":\t"),
				new Label(_("Screenshot selected area") + ":\t"),
				new Label(_("Screenshot active window") + ":\t"),
			};

			shortcutlabels = {};
			// Shortcuts is about -keyboard- shortcuts
			Label header = new Label("Shortcuts:");
			header.get_style_context().add_class("popoverheader");
			header.xalign = 0;
			int ypos = 1;
			popovergrid.attach(header, 0, 0, 1, 1);

			foreach(Label l in shortcutnames) {
				l.xalign = 0;
				popovergrid.attach(l, 0, ypos, 1, 1);
				Label newshortcutlabel = new Label("");
				newshortcutlabel.xalign = 0;
				shortcutlabels += newshortcutlabel;
				popovergrid.attach(newshortcutlabel, 1, ypos, 1, 1);
				ypos += 1;
			}

			newpopover.add(popovergrid);
			popovergrid.show_all();

			return newpopover;
		}

		private void rearrange_headerbar() {
			/*
			/ we want screenshot button and help button arranged
			/ outside > inside, so order depends on button positions
			*/
			foreach (Widget w in topbar.get_children()) {
				w.destroy();
			}

			/*
			/ all the things you need to do to work around Gtk peculiarities:
			/ if you set an image on a button, button gets crazy roundings,
			/ if you set border radius, you get possible theming issues,
			/ so.. add icon to grid, grid to button, button behaves. pfff.
			*/
			Gtk.Button shootbutton = new Gtk.Button();
			if (windowstate.showtooltips) {
				shootbutton.set_tooltip_text("Take a screenshot");
			}

			var iconfile =  new ThemedIcon(name="shootscreen-symbolic");
			Gtk.Image shootimage = new Gtk.Image.from_gicon(iconfile,Gtk.IconSize.DND);
			shootimage.pixel_size = 24;
			Gtk.Grid shootgrid = new Gtk.Grid();
			shootgrid.attach(shootimage, 0, 0, 1, 1);
			shootbutton.add(shootgrid);
			set_margins(shootgrid, 10, 10, 0, 0);
			shootbutton.get_style_context().add_class(Gtk.STYLE_CLASS_SUGGESTED_ACTION);
			shootbutton.clicked.connect(()=> {
				windowstate.disconnect(button_id);
				this.close();
				string shootmode = windowstate.screenshot_settings.get_string(
					"screenshot-mode"
				);
				// allow the window to gracefully disappear
				GLib.Timeout.add(100, ()=> {
					switch (shootmode) {
						case "Selection": // don't translate!
							new SelectLayer();
							break;
						case "Screen": // don't translate!
							windowstate.statechanged(WindowState.WAITINGFORSHOT);
							new MakeScreenshot(null);
							break;
						case "Window": // don't translate!
							windowstate.statechanged(WindowState.WAITINGFORSHOT);
							new MakeScreenshot(null);
							break;
					}

					return false;
				});
			});

			Gtk.Button helpbutton = new Gtk.Button();
			Gtk.Popover helppopover = make_info_popover(helpbutton);
			helpbutton.clicked.connect(() => {
				update_current_shortcuts();
				helppopover.set_visible(true);
			});
			helpbutton.label = "･･･";
			helpbutton.get_style_context().add_class(Gtk.STYLE_CLASS_RAISED);
			if (windowstate.buttonpos == ButtonPlacement.LEFT) {
				topbar.pack_end(shootbutton);
				topbar.pack_end(helpbutton);
			}
			else {
				topbar.pack_start(shootbutton);
				topbar.pack_start(helpbutton);
			}
			this.show_all();
		}

		private Gtk.Box setup_areabuttons() {
			Gtk.Box areabuttonbox = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
			string mode = windowstate.screenshot_settings.get_string("screenshot-mode");

			// we cannot use areabuttons_labels, since these will be translated
			string[] mode_options =  {"Screen", "Window", "Selection"}; // don't translate, internal use
			int active = find_stringindex(mode, mode_options);

			// translate! These are the interface names
			string[] areabuttons_labels = {
				_("Screen"), _("Window"), _("Selection")
			};

			string[] icon_names = {
				"selectscreen-symbolic",
				"selectwindow-symbolic",
				"selectselection-symbolic"
			};

			int i = 0;
			ToggleButton[] selectbuttons = {};
			foreach (string s in areabuttons_labels) {
				var iconfile = new ThemedIcon(name=icon_names[i]);
				Gtk.Image selecticon = new Gtk.Image.from_gicon(iconfile,Gtk.IconSize.DIALOG);
				selecticon.pixel_size = 60;
				Grid buttongrid = new Gtk.Grid();
				buttongrid.attach(selecticon, 0, 0, 1, 1);

				// label
				Label selectionlabel = new Label(s);
				selectionlabel.set_size_request(90, 10);
				selectionlabel.xalign = (float)0.5;
				selectionlabel.get_style_context().add_class("buttonlabel");
				buttongrid.attach(selectionlabel, 0, 1, 1, 1);

				// grid in button
				ToggleButton b = new Gtk.ToggleButton();
				b.get_style_context().add_class("centerbutton");
				b.add(buttongrid);
				if (i == active) {
					b.set_active(true);
				}
				areabuttonbox.pack_start(b);
				selectbuttons += b;
				b.clicked.connect(()=> {
					if (!ignore) {
						ignore = true;
						select_action(b, selectbuttons);
						b.set_active(true);
						GLib.Timeout.add(200, ()=> {
							ignore = false;

							return false;
						});
					}
				});
				i += 1;
			}

			return areabuttonbox;
		}

		private void select_action(ToggleButton b, ToggleButton[] btns) {
			string[] selectmodes = {"Screen", "Window", "Selection"}; // don't translate!
			int i = 0;

			foreach (ToggleButton bt in btns) {
				if (bt != b) {
					bt.set_active(false);
				}
				else {
					selectmode = i;
					windowstate.screenshot_settings.set_string("screenshot-mode", selectmodes[i]);
				}
				i += 1;
			}
		}

		private void set_margins(Gtk.Grid grid, int left, int right, int top, int bottom) {
			grid.set_margin_start(left);
			grid.set_margin_end(right);
			grid.set_margin_top(top);
			grid.set_margin_bottom(bottom);
		}
	}


	class SelectLayer : Gtk.Window {
		int startx;
		int starty;
		int topleftx;
		int toplefty;
		int width;
		int height;
		double red = 0; // fallback
		double green = 0; // fallback
		double blue = 1; // fallback
		GLib.Settings? theme_settings;
		CurrentState windowstate;

		public SelectLayer(int? overrule_delay=null) {
			windowstate=new CurrentState();
			windowstate.statechanged(WindowState.SELECTINGAREA);
			theme_settings = new GLib.Settings("org.gnome.desktop.interface");
			this.set_type_hint(Gdk.WindowTypeHint.UTILITY);
			this.fullscreen();
			this.set_keep_above(true);
			get_theme_fillcolor();

			// connect draw
			Gtk.DrawingArea darea = new Gtk.DrawingArea();
			darea.draw.connect((w, ctx)=> {
				// draw: x, y, width, height
				draw_rectangle(
					w, ctx, topleftx, toplefty,
					width, height
				);

				return true;
			});

			this.add(darea);
			// connect button & move
			this.button_press_event.connect(determine_startpoint);
			this.button_release_event.connect(()=> {
				take_shot.begin();

				return true;
			});

			this.motion_notify_event.connect(update_preview);
			set_win_transparent();
			this.show_all();
			change_cursor();
		}

		private void get_theme_fillcolor(){
			Gtk.StyleContext style_ctx = new Gtk.StyleContext();
			Gtk.WidgetPath widget_path =  new Gtk.WidgetPath();
			widget_path.append_type(typeof(Gtk.Button));
			style_ctx.set_path(widget_path);
			Gdk.RGBA fcolor = style_ctx.get_color(Gtk.StateFlags.LINK);
			red = fcolor.red;
			green = fcolor.green;
			blue = fcolor.blue;
		}

		private bool determine_startpoint(Gtk.Widget w, EventButton e) {
			/*
			/ determine first point of the selected rectangle, which is not
			/ necessarily topleft(!)
			*/
			startx = (int)e.x;
			starty = (int)e.y;

			return true;
		}

		private bool update_preview(Gdk.EventMotion e) {
			/*
			/ determine end of selected area, which is not necessarily
			/ bottom_right(!)
			*/
			int endx = (int)e.x;
			int endy = (int)e.y;
			// now make sure we define top-left -> bottom-right
			int[] areageo = calculate_rectangle(
				startx, starty, endx, endy
			);
			topleftx = areageo[0];
			toplefty = areageo[1];
			width = areageo[2];
			height = areageo[3];
			// update
			Gdk.Window window = this.get_window();
			var region = window.get_clip_region();
			window.invalidate_region(region, true);

			return true;
		}

		private int[] calculate_rectangle(int startx, int starty, int endx, int endy) {
			/*
			/ user might not move in the expected direction (top-left ->
			/ bottom-right), so we need to convert & calculate into the
			/ right format for drawing the rectangle or taking scrshot
			*/
			(endx < startx)? topleftx = endx : topleftx = startx;
			(endy < starty)? toplefty = endy : toplefty = starty;

			return {topleftx, toplefty, (startx-endx).abs(), (starty-endy).abs()};
		}

		private void draw_rectangle(Widget da, Cairo.Context ctx, int x1, int y1, int x2, int y2) {
			ctx.set_source_rgba(red, green, blue, 0.3);
			ctx.rectangle(x1, y1, x2, y2);
			ctx.fill_preserve();
			ctx.set_source_rgba(red, green, blue, 1.0);
			ctx.set_line_width(0.5);
			ctx.stroke();
			ctx.fill();
		}

		private void set_win_transparent() {
			this.set_app_paintable(true);
			var visual = screen.get_rgba_visual();
			this.set_visual(visual);

			//  this.draw.connect(on_draw);
			this.draw.connect((da, ctx)=> {
				ctx.set_source_rgba(0, 0, 0, 0);
				ctx.set_operator(Cairo.Operator.SOURCE);
				ctx.paint();
				ctx.set_operator(Cairo.Operator.OVER);

				return false;
			});
		}

		private void change_cursor() {
			Gdk.Cursor selectcursor = new Gdk.Cursor.from_name(Gdk.Display.get_default(), "crosshair");
			this.get_window().set_cursor(selectcursor);
		}

		async void take_shot() {
			this.destroy();
			windowstate.statechanged(WindowState.WAITINGFORSHOT);
			int[] area = {topleftx, toplefty, width, height};
			new MakeScreenshot(area);
		}
	}

	[GtkTemplate (ui="/org/buddiesofbudgie/Screenshot/aftershot.ui")]
	class AfterShotWindow : Gtk.Window {
		/*
		* after the screenshot was taken, we need to present user a window
		* with a preview. from there we can decide what to do with it
		*/

		[GtkChild]
		private unowned Gtk.Entry? filenameentry;

		[GtkChild]
		private unowned Gtk.ComboBox? pickdir_combo;

		[GtkChild]
		private unowned Gtk.ListStore? dir_liststore;

		[GtkChild]
		private unowned Gtk.Image? img;

		VolumeMonitor monitor;
		bool act_ondropdown = true;
		string[]? custompath_row = null;
		string[] alldirs = {};
		Button[] decisionbuttons = {};
		string? extension;
		int counted_dirs;
		CurrentState windowstate;
		ulong? button_id=null;

		enum Column {
			DIRPATH,
			DISPLAYEDNAME,
			ICON,
			ISSEPARATOR
		}

		private void delete_file(File file) {
			try {
				file.delete();
			}
			catch (Error e) {
				// nothing to do, file does not exist
			}
		}

		private Gdk.Pixbuf? get_pxb() {
			// wait max 2 sec for file to appear in /tmp
			File pixfile = GLib.File.new_for_path(windowstate.tempfile_path);
			int n = 0;
			while (n < 20) {
				Thread.usleep(100000);
				if (pixfile.query_exists()) {
					try {
						Pixbuf pxb = new Gdk.Pixbuf.from_file(windowstate.tempfile_path);
						delete_file(pixfile);

						return pxb;
					}
					catch (Error e) {
						print("unable to load image from /tmp\n");
					}
				}
				n += 1;
			}

			return null;
		}

		public AfterShotWindow() {
			windowstate=new CurrentState();
			Gdk.Pixbuf pxb = get_pxb();
			if (pxb == null) {
				print("Error loading pixbuf!\n");
				windowstate.statechanged(WindowState.NONE);
			}
			else {
				makeaftershotwindow(pxb);
			}
		}

		private void makeaftershotwindow(Pixbuf pxb) {
			this.set_keep_above(true);
			int scale = get_scaling();
			Clipboard clp = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
			windowstate.statechanged(WindowState.AFTERSHOT);

			// create resized image for preview
			var pixbuf = resize_pixbuf(pxb, scale);
			img.set_from_pixbuf(pixbuf);
			filenameentry.set_text(get_scrshotname());

			// volume monitor
			monitor = VolumeMonitor.get();
			monitor.mount_added.connect(update_dropdown);
			monitor.mount_removed.connect(update_dropdown);
			update_dropdown();
			pickdir_combo.changed.connect(()=> {
				if (act_ondropdown) {item_changed(pickdir_combo);}
			});

			// headerbar
			HeaderBar decisionbar = new Gtk.HeaderBar();
			decisionbar.show_close_button = false;
			button_id=windowstate.buttonpos_changed.connect(()=> {
				decisionbuttons = {};
				setup_headerbar(decisionbar, filenameentry, clp, pxb);
			});

			setup_headerbar(decisionbar, filenameentry, clp, pxb);
		}

		private void close_window() {
			windowstate.disconnect(button_id);
			this.close();
		}

		private void setup_headerbar(HeaderBar bar, Entry filenameentry, Clipboard clp, Pixbuf pxb) {
			foreach (Widget w in bar.get_children()) {
				w.destroy();
			}

			// translate
			string[] tooltips = {
				_("Cancel screenshot"),
				_("Save screenshot to the selected directory"),
				_("Copy screenshot to the clipboard"),
				_("Open screenshot in default application")
			};
			string[] header_imagenames = {
				"trash-shot-symbolic",
				"save-shot-symbolic",
				"clipboard-shot-symbolic",
				"edit-shot-symbolic"
			};

			int currbutton = 0;
			foreach (string s in header_imagenames) {
				Button decisionbutton = new Gtk.Button();
				if (windowstate.showtooltips) {
					decisionbutton.set_tooltip_text(tooltips[currbutton]);
				}

				decisionbutton.set_can_focus(false);
				set_buttoncontent(decisionbutton, s);
				decisionbuttons += decisionbutton;
				currbutton += 1;
			}

			// set suggested on save button
			decisionbuttons[1].get_style_context().add_class(Gtk.STYLE_CLASS_SUGGESTED_ACTION);

			// aligned headerbar buttons
			string[] align = {"left", "right", "right", "right"}; // don't translate!
			(windowstate.buttonpos == ButtonPlacement.LEFT)? align = {"right", "left", "left", "left"} : align; // don't translate!

			int b_index = 0;
			foreach (Button b in decisionbuttons) {
				if (align[b_index] == "left") {
					bar.pack_end(b);
				}
				else {
					bar.pack_start(b);
				}
				b_index += 1;
			}

			// set headerbar button actions
			// - trash button: cancel
			decisionbuttons[0].clicked.connect(()=> {
				if (!windowstate.startedfromgui) {
					windowstate.statechanged(WindowState.NONE);
					close_window();
				}
				else {
					windowstate.statechanged(WindowState.MAINWINDOW);
					close_window();
					new ScreenshotHomeWindow();
				}
			});

			// - save to file
			decisionbuttons[1].clicked.connect(()=> {
				if (save_tofile(filenameentry, pickdir_combo, pxb) != "fail") {
					windowstate.statechanged(WindowState.NONE);
					close_window();
				}
			});

			// - copy to clipboard
			decisionbuttons[2].clicked.connect(()=> {
				clp.set_image(pxb);
				windowstate.statechanged(WindowState.NONE);
				close_window();
			});

			// - save to file. open in default
			decisionbuttons[3].clicked.connect(()=> {
				string usedpath = save_tofile(filenameentry, pickdir_combo, pxb);
				if (usedpath != "fail") {
					open_indefaultapp(usedpath);
					windowstate.statechanged(WindowState.NONE);
					close_window();
				}
			});

			this.set_titlebar(bar);
			this.show_all();
		}

		private void open_indefaultapp(string path) {
			File file = File.new_for_path(path);
			if (file.query_exists()) {
				try {
					AppInfo.launch_default_for_uri (file.get_uri (), null);
				} catch (Error e) {
					warning ("Unable to launch %s", path);
				}
			}
		}

		private string? get_path_fromcombo(Gtk.ComboBox combo) {
			// get the info from liststore from selected item
			Gtk.TreeIter iter;
			GLib.Value val;
			combo.get_active_iter(out iter);
			dir_liststore.get_value(iter, 0, out val);

			return (string)val;
		}

		private string get_scrshotname() {
			// create timestamped name
			extension = windowstate.screenshot_settings.get_string("file-type");
			GLib.DateTime now = new GLib.DateTime.now_local();

			return now.format(@"Snapshot_%F_%H-%M-%S.$extension");
		}

		private string save_tofile(Gtk.Entry entry, ComboBox combo, Pixbuf pxb) {
			string? found_dir = get_path_fromcombo(combo);
			string fname = entry.get_text();
			(fname.has_suffix(@".$extension"))? fname : fname = @"$fname.$extension";
			string usedpath = @"$found_dir/$fname";

			try {
				pxb.save(usedpath, extension);
			}
			catch (Error e) {
				stderr.printf ("%s\n", e.message);
				Button savebutton = decisionbuttons[1];
				set_buttoncontent(
					savebutton, "saveshot-noaccess-symbolic"
				);
				savebutton.set_tooltip_text(
					"A permission error on the directory occurred"
				);

				return "fail";
			}

			return usedpath;
		}

		private void set_buttoncontent(Button b, string icon) {
			foreach (Widget w in b.get_children()) {
				w.destroy();
			}

			Grid buttongrid = new Gtk.Grid();
			var theme = Gtk.IconTheme.get_default();
			theme.add_resource_path("/org/buddiesofbudgie/Screenshot/icons/scalable/apps/");
			var iconfile =  new ThemedIcon(name=icon);
			Gtk.Image buttonimage = new Gtk.Image.from_gicon(iconfile,Gtk.IconSize.BUTTON);
			buttonimage.pixel_size = 24;
			buttongrid.attach(buttonimage, 0, 0, 1, 1);
			set_margins(buttongrid, 8, 8, 0, 0);
			b.add(buttongrid);
			buttongrid.show_all();
		}

		private Gdk.Pixbuf resize_pixbuf(Pixbuf pxb, int scale) {
			/*
			* before showing the image, resize it to fit the max available
			* available space in the decision window (345 x 345)
			*/
			int maxw_h = 345;
			float resize = 1;
			int scaled_width = (int)(pxb.get_width()/scale);
			int scaled_height = (int)(pxb.get_height()/scale);

			if (scaled_width > maxw_h || scaled_height > maxw_h) {
				(scaled_width >= scaled_height)? resize = (float)maxw_h/scaled_width : resize;
				(scaled_height >= scaled_width)? resize = (float)maxw_h/scaled_height : resize;
			}

			int dest_width = (int)(scaled_width * resize);
			int dest_height = (int)(scaled_height * resize);
			Gdk.Pixbuf resized = pxb.scale_simple(dest_width, dest_height, InterpType.BILINEAR);

			return resized;
		}

		// the labor work to add a row
		private void create_row(string? path, string? mention, string? iconname, bool separator = false) {
			// create a liststore-row
			Gtk.TreeIter iter;
			dir_liststore.append(out iter);
			dir_liststore.set(iter, Column.DIRPATH, path);
			dir_liststore.set(iter, Column.DISPLAYEDNAME, mention);
			dir_liststore.set(iter, Column.ICON, iconname);
			dir_liststore.set(iter, Column.ISSEPARATOR, separator);
			alldirs += path;
		}

		private bool is_separator(Gtk.TreeModel dir_liststore, Gtk.TreeIter iter) {
			// separator function to check if ISSEPARATOR is true
			GLib.Value is_sep;
			dir_liststore.get_value(iter, 3, out is_sep);

			return (bool)is_sep;
		}

		private string get_dir_basename(string path) {
			string[] dirmention = path.split("/");

			return dirmention[dirmention.length-1];
		}

		private void update_dropdown() {
			alldirs = {};

			// temporarily surpass dropdown-connect
			act_ondropdown = false;

			// - and clean up stuff
			pickdir_combo.clear();
			dir_liststore.clear();

			// look up user dirs & add
			string[] userdir_iconnames = {
				"user-desktop", "folder-documents", "folder-download",
				"folder-music", "folder-pictures", "folder-publicshare",
				"folder-templates", "folder-videos"
			}; // do we need fallbacks?

			// first section: user-dirs
			int n_dirs = UserDirectory.N_DIRECTORIES;
			counted_dirs = 0;
			for(int i=0; i<n_dirs; i++) {
				string path = Environment.get_user_special_dir(i);
				string mention = get_dir_basename(path);
				string iconname = userdir_iconnames[i];

				// check if dir exists
				if (GLib.File.new_for_path(path).query_exists()) {
					create_row(path, mention, iconname, false);
					counted_dirs += 1;
				}
			}

			create_row(null, null, null, true);
			// (home)
			create_row(
				GLib.Environment.get_home_dir(),
				get_dir_basename(GLib.Environment.get_home_dir()),
				"user-home",
				false
			);

			create_row(null, null, null, true);
			// second section: look up mounted volumes
			bool add_separator = false;
			List<Mount> mounts = monitor.get_mounts ();
			foreach (Mount mount in mounts) {
				add_separator = true;
				GLib.Icon icon = mount.get_icon();
				string ic_name = get_icon_fromgicon(icon);
				string displayedname = mount.get_name();
				string dirpath = mount.get_default_location().get_path ();
				create_row(dirpath, displayedname, ic_name, false);
			}

			if (add_separator) {
				create_row(null, null, null, true);
			}
			// second section: (possible) custom path
			int r_index = -1;
			if (custompath_row != null) {
				string c_path = custompath_row[0];

				// check if the picked dir is already listed
				r_index = find_stringindex(c_path, alldirs);

				if (r_index == -1) {
					create_row(
						c_path, custompath_row[1], custompath_row[2], false
					);

					// now update the index to set new dir active
					r_index = find_stringindex(c_path, alldirs);
					create_row(null, null, null, true);
				}
			}

			// Other -> call Filebrowser (path = null)
			// 'Other' is about setting a custom directory on a dropdown list
			create_row(null, _("Other..."), null, false);

			// set separator
			pickdir_combo.set_row_separator_func(is_separator);

			// populate dropdown
			Gtk.CellRendererText cell = new Gtk.CellRendererText();
			cell.set_padding(10, 1);
			cell.set_property("ellipsize", Pango.EllipsizeMode.END);
			cell.set_fixed_size(15, -1);
			Gtk.CellRendererPixbuf cell_pb = new Gtk.CellRendererPixbuf();
			pickdir_combo.pack_end(cell, false);
			pickdir_combo.pack_end(cell_pb, false);
			pickdir_combo.set_attributes(cell, "text", Column.DISPLAYEDNAME);
			pickdir_combo.set_attributes(cell_pb, "icon_name", Column.ICON);

			// if we picked a custom dir, set it active
			int active_row;
			active_row = windowstate.screenshot_settings.get_int("last-save-directory");

			// prevent segfault error on incorrect gsettings value
			// if set row > found number of user dirs -> land on home row
			(active_row > counted_dirs - 1)? active_row = counted_dirs + 1 : active_row;

			// a bit overdone, since we already checked on row creation but:
			(r_index != -1)? active_row = r_index : active_row;
			pickdir_combo.set_active(active_row);
			pickdir_combo.show();
			act_ondropdown = true;
		}

		private string lookup_icon_name(File customdir) {
			try {
				FileInfo info = customdir.query_info("standard::icon", 0);
				Icon icon = info.get_icon();

				return get_icon_fromgicon(icon);
			}
			catch (Error e) {
				stderr.printf ("%s\n", e.message);

				return "";
			}
		}

		void save_customdir(Gtk.Dialog dialog, int response_id) {
			// setting user response on dialog as custom path (the labor work)
			var save_dialog = dialog as Gtk.FileChooserDialog;
			if (response_id == Gtk.ResponseType.ACCEPT) {
				File file = save_dialog.get_file();
				string ic_name = lookup_icon_name(file);

				// so, the actual path
				string custompath = file.get_path();

				// ...and its mention in the dropdown
				string[] custompath_data = custompath.split("/");
				string mention = custompath_data[custompath_data.length - 1];

				// delivering info to set new row
				custompath_row = {custompath, mention, ic_name};
				update_dropdown();
			}
			else {
				pickdir_combo.set_active(windowstate.screenshot_settings.get_int("last-save-directory"));
			}
			dialog.destroy ();
		}

		private string get_icon_fromgicon(GLib.Icon ic) {
			/*
			* kind of dirty, we should find a cleaner one
			* if gicon holds ThemedIcon info, it starts with "". ThemedIcon",
			* so we pick first icon after that from the list
			* in other cases, single icon name is the only data in gicon.
			*/
			string found_icon = "";
			string[] iconinfo = ic.to_string().split(" ");
			(iconinfo.length >=3)? found_icon = iconinfo[2] : found_icon = iconinfo[0];

			return found_icon;
		}

		private void get_customdir() {
			// set custom dir to found dir
			Gtk.FileChooserDialog dialog = new Gtk.FileChooserDialog(
				_("Open Folder"), this, Gtk.FileChooserAction.SELECT_FOLDER,
				_("Cancel"), Gtk.ResponseType.CANCEL, _("Open"),Gtk.ResponseType.ACCEPT, null
			);

			dialog.response.connect(save_customdir);
			dialog.show();
		}

		private void set_margins(Gtk.Grid grid, int left, int right, int top, int bottom) {
			// setting margins for a grid
			grid.set_margin_start(left);
			grid.set_margin_end(right);
			grid.set_margin_top(top);
			grid.set_margin_bottom(bottom);
		}

		private void item_changed(Gtk.ComboBox combo) {
			/*
			* on combo selection change, check if we need to add custom
			* path. selected item then has null for field path.
			* remember picked enum. no need for vice versa, since this is
			* set after window is called, and selection is set.
			*/
			int new_selection = combo.get_active();
			if (new_selection <= counted_dirs) {
				windowstate.screenshot_settings.set_int("last-save-directory", new_selection);
			}

			// if we change directory, reset save button's icon
			Button savebutton = decisionbuttons[1];
			set_buttoncontent(savebutton, "save-shot-symbolic");
			savebutton.set_has_tooltip(false);

			if (get_path_fromcombo(combo) == null) {
				get_customdir();
			}
			else {
				custompath_row = null;
			}
		}
	}

	private int get_scaling() {
		// not very sophisticated, but for now, we'll assume one scale
		Gdk.Monitor gdkmon = Gdk.Display.get_default().get_monitor(0);
		int curr_scale = gdkmon.get_scale_factor();

		return curr_scale;
	}

	private int find_stringindex(string str, string[] arr) {
		for(int i=0; i<arr.length; i++) {
			if (str == arr[i]) {
				return i;
			}
		}

		return -1;
	}
}
