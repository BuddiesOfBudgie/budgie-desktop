/*
 * This file is part of budgie-desktop
 *
 * Copyright © 2014-2022 Budgie Desktop Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

public class ClockPlugin : Budgie.Plugin, Peas.ExtensionBase {
	public Budgie.Applet get_panel_widget(string uuid) {
		return new ClockApplet(uuid);
	}
}

private const string CLOCK_SETTINGS_SCHEMA = "com.solus-project.clock";
private const string GNOME_SETTINGS_SCHEMA = "org.gnome.desktop.interface";

public class ClockApplet : Budgie.Applet {
	protected Gtk.EventBox widget;
	protected Gtk.Box layout;
	protected Gtk.Label clock_label;
	protected Gtk.Label date_label;
	protected Gtk.Label seconds_label;

	private DateTime time;

	protected Settings settings;
	protected Settings gnome_settings;

	Budgie.Popover? popover = null;

	Gtk.Orientation orient = Gtk.Orientation.HORIZONTAL;

	private unowned Budgie.PopoverManager? manager = null;

	private bool clock_show_date;
	private bool clock_show_seconds;
	private bool clock_use_24_hour_time;
	private bool clock_use_custom_format;
	private bool clock_use_custom_timezone;
	private string clock_custom_format;
	private TimeZone clock_timezone;

	public string uuid { public set; public get; }

	Gtk.Button new_plain_button(string label_str) {
		Gtk.Button ret = new Gtk.Button.with_label(label_str);
		ret.get_child().halign = Gtk.Align.START;
		ret.get_style_context().add_class(Gtk.STYLE_CLASS_FLAT);
		return ret;
	}


	public override void panel_position_changed(Budgie.PanelPosition position) {
		if (position == Budgie.PanelPosition.LEFT || position == Budgie.PanelPosition.RIGHT) {
			this.orient = Gtk.Orientation.VERTICAL;
			clock_label.set_line_wrap(true);
			clock_label.set_max_width_chars(1);
		} else {
			this.orient = Gtk.Orientation.HORIZONTAL;
			clock_label.set_line_wrap(false);
			clock_label.set_max_width_chars(-1);
		}
		this.seconds_label.set_text("");
		this.layout.set_orientation(this.orient);
		this.update_clock();
	}

	public ClockApplet(string uuid) {
		Object(uuid: uuid);

		settings_schema = CLOCK_SETTINGS_SCHEMA;
		settings_prefix = "/com/solus-project/clock/instance/clock";

		this.settings = this.get_applet_settings(uuid);
		this.gnome_settings = new Settings(GNOME_SETTINGS_SCHEMA);

		widget = new Gtk.EventBox();
		layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 2);
		widget.add(layout);

		clock_label = new Gtk.Label("");
		clock_label.set_line_wrap(true);
		clock_label.justify = Gtk.Justification.CENTER;
		layout.pack_start(clock_label, false, false, 0);
		layout.margin = 0;
		layout.border_width = 0;

		seconds_label = new Gtk.Label("");
		seconds_label.get_style_context().add_class("dim-label");
		layout.pack_start(seconds_label, false, false, 0);
		seconds_label.no_show_all = true;
		seconds_label.hide();

		date_label = new Gtk.Label("");
		layout.pack_start(date_label, false, false, 0);
		date_label.no_show_all = true;
		date_label.hide();

		clock_label.valign = Gtk.Align.CENTER;
		seconds_label.valign = Gtk.Align.CENTER;
		date_label.valign = Gtk.Align.CENTER;

		get_style_context().add_class("budgie-clock-applet");

		// Create a submenu system
		popover = new Budgie.Popover(widget);

		var container = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
		container.get_style_context().add_class("clock-applet-stack");
		container.set_homogeneous(true);

		var menu = new Gtk.Box(Gtk.Orientation.VERTICAL, 1);
		menu.get_style_context().add_class("clock-applet-stack");
		menu.border_width = 6;

		popover.add(menu);

		var time_button = this.new_plain_button(_("System time and date settings"));
		time_button.clicked.connect(on_date_activate);

		menu.pack_start(time_button, false, false, 0);

		widget.button_press_event.connect((e) => {
			if (e.button != 1) {
				return Gdk.EVENT_PROPAGATE;
			}
			if (popover.get_visible()) {
				popover.hide();
			} else {
				this.manager.show_popover(widget);
			}
			return Gdk.EVENT_STOP;
		});

		// make sure every setting is ready
		this.update_setting(CLOCK_SETTINGS_SCHEMA, "show-date");
		this.update_setting(CLOCK_SETTINGS_SCHEMA, "show-seconds");
		this.update_setting(GNOME_SETTINGS_SCHEMA, "clock-format"); // clock format comes from gnome desktop settings (24 or 12 hour format)
		this.update_setting(CLOCK_SETTINGS_SCHEMA, "use-custom-format");
		this.update_setting(CLOCK_SETTINGS_SCHEMA, "custom-format");
		this.update_setting(CLOCK_SETTINGS_SCHEMA, "use-custom-timezone");
		this.update_setting(CLOCK_SETTINGS_SCHEMA, "custom-timezone");

		this.date_label.set_visible(this.clock_show_date);
		this.seconds_label.set_visible(this.clock_show_seconds);

		Timeout.add_seconds_full(Priority.LOW, 1, update_clock);

		settings.changed.connect((key) => {
			update_setting(CLOCK_SETTINGS_SCHEMA, key);
			update_clock();
		});
		gnome_settings.changed.connect((key) => {
			update_setting(GNOME_SETTINGS_SCHEMA, key);
			update_clock();
		});

		add(widget);

		popover.get_child().show_all();

		show_all();
	}

	void on_date_activate() {
		this.popover.hide();
		var app_info = new DesktopAppInfo("budgie-datetime-panel.desktop");

		if (app_info == null) {
			return;
		}
		try {
			app_info.launch(null, null);
		} catch (Error e) {
			message("Unable to launch budgie-datetime-panel.desktop: %s", e.message);
		}
	}

	public override void update_popovers(Budgie.PopoverManager? manager) {
		this.manager = manager;
		manager.register_popover(widget, popover);
	}

	private void update_setting(string schema, string key) {
		if (schema == CLOCK_SETTINGS_SCHEMA) {
			switch (key) {
				case "show-date":
					this.clock_show_date = settings.get_boolean(key);
					this.date_label.set_visible(this.clock_show_date);
					break;
				case "show-seconds":
					this.clock_show_seconds = settings.get_boolean(key);
					this.seconds_label.set_visible(this.clock_show_seconds);
					break;
				case "use-custom-format":
					this.clock_use_custom_format = settings.get_boolean(key);
					if (this.clock_use_custom_format) {
						this.date_label.set_visible(false);
						this.seconds_label.set_visible(false);
					} else {
						this.date_label.set_visible(this.clock_show_date);
						this.seconds_label.set_visible(this.clock_show_seconds);
					}
					break;
				case "custom-format":
					this.clock_custom_format = settings.get_string(key);
					break;
				case "use-custom-timezone":
				case "custom-timezone":
					this.clock_use_custom_timezone = settings.get_boolean("use-custom-timezone");
					if (this.clock_use_custom_timezone) {
						string custom_tz = settings.get_string("custom-timezone");
						try {
							this.clock_timezone = new TimeZone.identifier(custom_tz);
						} catch (Error e) {
							warning("Clock applet: Failed to set time zone from identifier %s. Using UTC instead.", custom_tz);
							this.clock_timezone = new TimeZone.utc();
						}
					} else {
						this.clock_timezone = new TimeZone.local();
					}
					break;
			}
			return;
		}
		if (schema == GNOME_SETTINGS_SCHEMA) {
			switch (key) {
				case "clock-format": // gnome-settings
					this.clock_use_24_hour_time = (gnome_settings.get_string("clock-format") == "24h");
					break;
			}
			return;
		}
	}


	/**
	 * Update the date if necessary
	 */
	protected void update_date() {
		if (!this.clock_show_date || this.clock_use_custom_format) {
			return;
		}
		string ftime;
		if (this.orient == Gtk.Orientation.HORIZONTAL) {
			ftime = "%x";
		} else {
			ftime = "<small>%b %d</small>";
		}

		// Prevent unnecessary redraws
		var old = this.date_label.get_label();
		var ctime = this.time.format(ftime);
		if (old == ctime) {
			return;
		}
		this.date_label.set_markup(ctime);
	}

	/**
	 * Update the seconds if necessary
	 */
	protected void update_seconds() {
		if (!this.clock_show_seconds || this.clock_use_custom_format) {
			return;
		}
		string ftime;
		if (this.orient == Gtk.Orientation.HORIZONTAL) {
			ftime = "";
		} else {
			ftime = "<big>%S</big>";
		}

		// Prevent unnecessary redraws
		var old = this.seconds_label.get_label();
		var ctime = this.time.format(ftime);
		if (old == ctime) {
			return;
		}

		this.seconds_label.set_markup(ctime);
	}

	/**
	 * This is called once every second, updating the time
	 */
	protected bool update_clock() {
		if (!this.clock_use_custom_timezone) {
			this.clock_timezone = new TimeZone.local();
		}
		this.time = new DateTime.now(this.clock_timezone);

		string format;
		if (!this.clock_use_custom_format) {
			format = (this.clock_use_24_hour_time) ? "%H:%M" : "%l:%M";

			if (orient == Gtk.Orientation.HORIZONTAL && this.clock_show_seconds) {
				format += ":%S";
			}

			if (!this.clock_use_24_hour_time) {
				format += " %p";
			}
		} else {
			format = this.clock_custom_format;
		}

		this.update_date();
		this.update_seconds();

		// Prevent unnecessary redraws
		var old = this.clock_label.get_label();
		var ctime = this.time.format(format).strip();

		string ftime;
		if (this.orient == Gtk.Orientation.HORIZONTAL) {
			ftime = "%s";
		} else {
			ftime = "<small>%s</small>";
		}

		var formatted = ftime.printf(ctime).replace("\u2007", "");
		if (old == formatted) {
			return true;
		}

		this.clock_label.set_markup(formatted);
		this.queue_draw();

		return true;
	}

	public override bool supports_settings() {
		return true;
	}

	public override Gtk.Widget? get_settings_ui() {
		return new ClockSettings(this.get_applet_settings(uuid), new Settings(GNOME_SETTINGS_SCHEMA));
	}
}


[GtkTemplate (ui="/com/solus-project/clock/settings.ui")]
public class ClockSettings : Gtk.Grid {

	[GtkChild]
	private unowned Gtk.Switch? show_date;

	[GtkChild]
	private unowned Gtk.Switch? show_seconds;

	[GtkChild]
	private unowned Gtk.Switch? use_24_hour_time;

	[GtkChild]
	private unowned Gtk.Switch? use_custom_format;

	[GtkChild]
	private unowned Gtk.Entry? custom_format;

	[GtkChild]
	private unowned Gtk.Switch? use_custom_timezone;

	[GtkChild]
	private unowned Gtk.Entry? custom_timezone;

	public ClockSettings(Settings? settings, Settings? gnome_settings) {
		settings.bind("show-date", this.show_date, "active", SettingsBindFlags.DEFAULT);
		settings.bind("show-seconds", this.show_seconds, "active", SettingsBindFlags.DEFAULT);
		gnome_settings.bind_with_mapping("clock-format", this.use_24_hour_time, "active", SettingsBindFlags.DEFAULT, (value, variant, user_data) => {
			value.set_boolean((variant.get_string() == "24h"));
			return true;
		}, (value, expected_type, user_data) => {
			if (value.get_boolean()) {
				return new Variant("s", "24h");
			}
			return new Variant("s", "12h");
		}, null, null);
		settings.bind("use-custom-format", this.use_custom_format, "active", SettingsBindFlags.DEFAULT);
		settings.bind("custom-format", this.custom_format, "text", SettingsBindFlags.DEFAULT);
		settings.bind("use-custom-timezone", this.use_custom_timezone, "active", SettingsBindFlags.DEFAULT);
		settings.bind("custom-timezone", this.custom_timezone, "text", SettingsBindFlags.DEFAULT);

		this.use_custom_format.notify["active"].connect(this.updateSensitve);
		this.use_custom_timezone.notify["active"].connect(this.updateSensitve);

		this.updateSensitve();
	}

	private void updateSensitve() {
		var useCustomFormat = this.use_custom_format.get_active();
		this.show_date.set_sensitive(!useCustomFormat);
		this.show_seconds.set_sensitive(!useCustomFormat);
		this.use_24_hour_time.set_sensitive(!useCustomFormat);
		this.custom_format.set_sensitive(useCustomFormat);

		this.custom_timezone.set_sensitive(this.use_custom_timezone.get_active());
	}

}

[ModuleInit]
public void peas_register_types(TypeModule module) {
	// boilerplate - all modules need this
	var objmodule = module as Peas.ObjectModule;
	objmodule.register_extension_type(typeof(Budgie.Plugin), typeof(ClockPlugin));
}
