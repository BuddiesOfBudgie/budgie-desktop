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

[DBus (name = "org.budgie_desktop.Panel")]
interface PanelRemote : Object {
	public abstract async void ShowDesktop(bool show) throws Error;
	public abstract async void ToggleShowDesktop() throws Error;
	public signal void DesktopShown(bool showing);
}

public class ShowDesktopPlugin : Budgie.Plugin, Peas.ExtensionBase {
	public Budgie.Applet get_panel_widget(string uuid) {
		return new ShowDesktopApplet();
	}
}

public class ShowDesktopApplet : Budgie.Applet {
	protected Gtk.ToggleButton widget;
	protected Gtk.Image img;
	private PanelRemote? panel_proxy = null;
	private bool in_toggle = false;

	public ShowDesktopApplet() {
		widget = new Gtk.ToggleButton();
		widget.relief = Gtk.ReliefStyle.NONE;
		widget.set_active(false);
		img = new Gtk.Image.from_icon_name("user-desktop-symbolic", Gtk.IconSize.BUTTON);
		widget.add(img);
		widget.set_tooltip_text(_("Toggle the desktop"));

		// Connect to panel DBus service
		setup_dbus.begin();

		widget.toggled.connect(() => {
			if (in_toggle) return;
			toggle_desktop.begin();
		});

		add(widget);
		show_all();
	}

	private async void setup_dbus() {
		try {
			panel_proxy = yield Bus.get_proxy(BusType.SESSION,
				"org.budgie_desktop.Panel",
				"/org/budgie_desktop/Panel");

			// Track desktop state changes
			panel_proxy.DesktopShown.connect((showing) => {
				in_toggle = true;
				widget.set_active(showing);
				in_toggle = false;
			});
		} catch (Error e) {
			warning("Failed to connect to panel DBus: %s", e.message);
		}
	}

	private async void toggle_desktop() {
		if (panel_proxy == null) return;

		try {
			yield panel_proxy.ToggleShowDesktop();

			// If toggle completed successfully but button is still pressed
			// and we're not in a toggle state update, it means there were
			// no windows to minimize. Reset the button state.
			if (!in_toggle && widget.get_active()) {
				// Small delay to allow signal to propagate
				Timeout.add(50, () => {
					if (!in_toggle && widget.get_active()) {
						in_toggle = true;
						widget.set_active(false);
						in_toggle = false;
					}
					return false;
				});
			}
		} catch (Error e) {
			warning("Failed to toggle desktop: %s", e.message);
			// Revert button state on error
			in_toggle = true;
			widget.set_active(!widget.get_active());
			in_toggle = false;
		}
	}
}

[ModuleInit]
public void peas_register_types(TypeModule module) {
	// boilerplate - all modules need this
	var objmodule = module as Peas.ObjectModule;
	objmodule.register_extension_type(typeof(Budgie.Plugin), typeof(ShowDesktopPlugin));
}
