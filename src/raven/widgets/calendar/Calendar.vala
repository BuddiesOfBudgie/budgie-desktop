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
		return true;
	}
}

public class CalendarRavenWidget : Budgie.RavenWidget {
	private Gtk.Box? header = null;
	private Gtk.Button? header_reveal_button = null;
	private Gtk.Revealer? content_revealer = null;
	private Gtk.Box? content = null;
	private Gtk.Label? header_label = null;
	private Gtk.Box? main_box = null;
	private Gtk.Calendar? cal = null;

	private const string date_format = "%e %b %Y";

	public CalendarRavenWidget(string uuid, GLib.Settings? settings) {
		initialize(uuid, settings);

		main_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
		add(main_box);

		header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
		header.get_style_context().add_class("raven-header");
		main_box.add(header);

		var icon = new Gtk.Image.from_icon_name("calendar", Gtk.IconSize.MENU);
		icon.margin = 8;
		icon.margin_start = 12;
		icon.margin_end = 12;
		header.add(icon);

		var time = new DateTime.now_local();
		header_label = new Gtk.Label(time.format(date_format));
		header.add(header_label);

		content = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
		content.get_style_context().add_class("raven-background");

		content_revealer = new Gtk.Revealer();
		content_revealer.add(content);
		content_revealer.reveal_child = true;
		main_box.add(content_revealer);

		header_reveal_button = new Gtk.Button.from_icon_name("pan-down-symbolic", Gtk.IconSize.MENU);
		header_reveal_button.get_style_context().add_class("flat");
		header_reveal_button.get_style_context().add_class("expander-button");
		header_reveal_button.margin = 4;
		header_reveal_button.valign = Gtk.Align.CENTER;
		header_reveal_button.clicked.connect(() => {
			content_revealer.reveal_child = !content_revealer.child_revealed;
			var image = (Gtk.Image?) header_reveal_button.get_image();
			if (content_revealer.reveal_child) {
				image.set_from_icon_name("pan-down-symbolic", Gtk.IconSize.MENU);
			} else {
				image.set_from_icon_name("pan-end-symbolic", Gtk.IconSize.MENU);
			}
		});
		header.pack_end(header_reveal_button, false, false, 0);

		cal = new Gtk.Calendar();
		cal.get_style_context().add_class("raven-calendar");
		content.add(cal);

		Timeout.add_seconds_full(Priority.LOW, 30, this.update_date);

		cal.month_changed.connect(() => {
			update_date();
		});

		settings.changed.connect(settings_updated);
		settings_updated("show-week-numbers");
		settings_updated("show-day-names");

		show_all();
	}

	/**
	 * set_week_number will set the display of the week number
	 */
	private void settings_updated(string key) {
		if (key == "show-week-numbers") {
			cal.show_week_numbers = get_instance_settings().get_boolean("show-week-numbers");
		} else if (key == "show-day-names") {
			cal.show_day_names = get_instance_settings().get_boolean("show-day-names");
		}
	}

	private bool update_date() {
		var time = new DateTime.now_local();
		var strf = time.format(date_format);
		header_label.label = strf;
		cal.day = (cal.month + 1) == time.get_month() && cal.year == time.get_year() ? time.get_day_of_month() : 0;
		return true;
	}

	public override Gtk.Widget build_settings_ui() {
		return new CalendarRavenWidgetSettings(get_instance_settings());
	}
}

[GtkTemplate (ui="/org/buddiesofbudgie/budgie-desktop/raven/widget/Calendar/settings.ui")]
public class CalendarRavenWidgetSettings : Gtk.Grid {
	[GtkChild]
	private unowned Gtk.Switch? switch_show_day_names;
	[GtkChild]
	private unowned Gtk.Switch? switch_show_week_numbers;

	public CalendarRavenWidgetSettings(Settings? settings) {
		settings.bind("show-day-names", switch_show_day_names, "active", SettingsBindFlags.DEFAULT);
		settings.bind("show-week-numbers", switch_show_week_numbers, "active", SettingsBindFlags.DEFAULT);
	}
}

[ModuleInit]
public void peas_register_types(TypeModule module) {
	// boilerplate - all modules need this
	var objmodule = module as Peas.ObjectModule;
	objmodule.register_extension_type(typeof(Budgie.RavenPlugin), typeof(CalendarRavenPlugin));
}
