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

public class ShowDesktopPlugin : Budgie.Plugin, Peas.ExtensionBase {
	public Budgie.Applet get_panel_widget(string uuid) {
		return new ShowDesktopApplet();
	}
}

public class ShowDesktopApplet : Budgie.Applet {
	protected Gtk.ToggleButton widget;
	protected Gtk.Image img;
	private Xfw.Screen xfce_screen;

	public ShowDesktopApplet() {
		widget = new Gtk.ToggleButton();
		widget.relief = Gtk.ReliefStyle.NONE;
		widget.set_active(false);
		img = new Gtk.Image.from_icon_name("user-desktop-symbolic", Gtk.IconSize.BUTTON);
		widget.add(img);
		widget.set_tooltip_text(_("Toggle the desktop"));

		xfce_screen = Xfw.Screen.get_default();

		xfce_screen.window_opened.connect((window) => {
			if (window.is_skip_pager() || window.is_skip_tasklist()) return;

			widget.set_active(false);

			window.state_changed.connect(() => {
				if (!window.is_minimized()) widget.set_active(false);
			});
		});

		widget.toggled.connect(() => {
			bool showing_desktop = !widget.get_active();
  			xfce_screen.get_windows_stacked().foreach((window) => {
				if (window.is_skip_pager() || window.is_skip_tasklist()) return;

				try {
					window.set_minimized(!showing_desktop);
				} catch (Error e) {
					// Note: This is intentionally set to debug instead of warning because Xfw will create noise otherwise
					// Unminimize operations can end up being noisy when they fail due to the window not yet reporting the capability to support CAN_MINIMIZE
					// https://gitlab.xfce.org/xfce/libxfce4windowing/-/blob/main/libxfce4windowing/xfw-window-x11.c#L363
					debug("Failed to change state of window \"%s\": %s", window.get_name(), e.message);
				}
			});
		});

		add(widget);
		show_all();
	}
}

[ModuleInit]
public void peas_register_types(TypeModule module) {
	// boilerplate - all modules need this
	var objmodule = module as Peas.ObjectModule;
	objmodule.register_extension_type(typeof(Budgie.Plugin), typeof(ShowDesktopPlugin));
}
