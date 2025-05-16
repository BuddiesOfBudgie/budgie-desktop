/*
 * This file is part of budgie-desktop.
 *
 * Copyright Budgie Desktop Developers
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 */

namespace Budgie {
	public enum Struts {
		LEFT,
		RIGHT,
		TOP,
		BOTTOM,
		LEFT_START,
		LEFT_END,
		RIGHT_START,
		RIGHT_END,
		TOP_START,
		TOP_END,
		BOTTOM_START,
		BOTTOM_END
	}

	public abstract class Toplevel : Gtk.Window {
		/**
		* Depth of our shadow component, to enable Raven blending
		*/
		public int shadow_depth { public set ; public get; default = 5; }

		/**
		* Our required size (height or width dependening on orientation
		*/
		public int intended_size { public set ; public get; }

		/**
		* Our configured applet spacing
		*/
		public int intended_spacing { public set; public get; }

		public bool shadow_visible { public set ; public get; }
		public bool theme_regions { public set; public get; }
		public bool dock_mode { public set; public get; default = false; }
		public bool intersected { public set; public get; default = false; }

		/**
		* Unique identifier for this panel
		*/
		public string uuid { public set ; public get; }

		public Budgie.PanelPosition position { public set; public get; default = Budgie.PanelPosition.BOTTOM; }
		public Budgie.PanelTransparency transparency { public set; public get; default = Budgie.PanelTransparency.NONE; }
		public Budgie.AutohidePolicy autohide { public set; public get; default = Budgie.AutohidePolicy.NONE; }


		public abstract List<Budgie.AppletInfo?> get_applets();
		public signal void applet_added(Budgie.AppletInfo? info);
		public signal void applet_removed(string uuid);

		public signal void applets_changed();

		public abstract bool can_move_applet_left(Budgie.AppletInfo? info);
		public abstract bool can_move_applet_right(Budgie.AppletInfo? info);

		public abstract void move_applet_left(Budgie.AppletInfo? info);
		public abstract void move_applet_right(Budgie.AppletInfo? info);

		public abstract void add_new_applet(string id);
		public abstract void remove_applet(Budgie.AppletInfo? info);
	}

	[Flags]
	public enum PanelTransparency {
		NONE = 1 << 0,
		DYNAMIC = 1 << 1,
		ALWAYS = 1 << 2
	}

	[Flags]
	public enum AutohidePolicy {
		NONE = 1 << 0,
		AUTOMATIC = 1 << 1,
		INTELLIGENT = 1 << 2
	}

	public static string position_class_name(PanelPosition position) {
		switch (position) {
			case PanelPosition.TOP:
				return "top";
			case PanelPosition.BOTTOM:
				return "bottom";
			case PanelPosition.LEFT:
				return "left";
			case PanelPosition.RIGHT:
				return "right";
			default:
				return "";
		}
	}
}
