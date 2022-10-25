/*
 * This file is part of budgie-desktop
 *
 * Copyright © 2015-2022 Budgie Desktop Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

public class CalendarRavenPlugin : Budgie.RavenPlugin, Peas.ExtensionBase {
	public Budgie.RavenWidget new_widget_instance(string uuid, GLib.Settings? settings) {
		return new CalendarRavenWidget(uuid, settings);
	}

	public bool supports_settings() {
		return false;
	}
}

public class CalendarRavenWidget : Budgie.RavenWidget {
	private Gtk.Box? main_box = null;
	private Gtk.Calendar? cal = null;

	private const string date_format = "%e %b %Y";

	public CalendarRavenWidget(string uuid, GLib.Settings? settings) {
		initialize(uuid, settings);

		main_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
		add(main_box);

		cal = new Gtk.Calendar();
		cal.get_style_context().add_class("raven-calendar");
		var ebox = new Gtk.EventBox();
		ebox.get_style_context().add_class("raven-background");
		ebox.add(cal);
		main_box.add(ebox);

		Timeout.add_seconds_full(Priority.LOW, 30, this.update_date);

		cal.month_changed.connect(() => {
			update_date();
		});

		set_week_number();

		show_all();
	}

	/**
	 * set_week_number will set the display of the week number
	 */
	 private void set_week_number() {
		bool show = false;

		this.cal.show_week_numbers = show;
	}

	private bool update_date() {
		var time = new DateTime.now_local();
		cal.day = (cal.month + 1) == time.get_month() && cal.year == time.get_year() ? time.get_day_of_month() : 0;
		return true;
	}
}

[ModuleInit]
public void peas_register_types(TypeModule module) {
	// boilerplate - all modules need this
	var objmodule = module as Peas.ObjectModule;
	objmodule.register_extension_type(typeof(Budgie.RavenPlugin), typeof(CalendarRavenPlugin));
}
