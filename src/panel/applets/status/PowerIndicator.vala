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

public class BatteryIcon : Gtk.Box {
	/** The battery associated with this icon */
	public unowned Up.Device battery { protected set; public get; }
	bool changing = false;
	bool emitted_warning = false;

	private Gtk.Image image;

	private Gtk.Label percent_label;

	/**
	 * Expose a simple property so the UI can update whether we show
	 * labels or not
	 */
	public bool label_visible {
		public set {
			this.percent_label.visible = value;
		}
		public get {
			return this.percent_label.visible;
		}
	}

	public BatteryIcon(Up.Device battery) {
		Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);

		this.get_style_context().add_class("battery-icon");

		/* We'll optionally show percent labels */
		this.percent_label = new Gtk.Label("");
		this.percent_label.get_style_context().add_class("percent-label");

		this.image = new Gtk.Image();
		this.image.valign = Gtk.Align.CENTER;
		this.image.pixel_size = 0;
		pack_start(this.image, false, false, 0);

		this.percent_label.valign = Gtk.Align.CENTER;
		this.percent_label.margin_start = 4;
		pack_start(this.percent_label, false, false, 0);
		this.percent_label.no_show_all = true;

		this.update_ui(battery);

		battery.notify.connect(this.on_battery_change);
	}

	private void on_battery_change(Object o, ParamSpec sp) {
		if (this.changing) return;
		this.changing = true;
		try {
			this.battery.refresh_sync(null);
		} catch (Error e) {
			if (!emitted_warning) {
				warning("Failed to refresh battery: %s", e.message);
				emitted_warning = true;
			}
		}

		this.update_ui(this.battery);
		this.changing = false;
	}

	public void update_ui(Up.Device battery) {
		string tip;

		this.battery = battery;

		// Determine the icon to use for this battery
		string image_name;

		// round to nearest 10
		int rounded = (int) Math.round(battery.percentage / 10) * 10;

		// in case the stepped icon doesn't exist
		string image_fallback;
		if (battery.percentage <= 10) {
			image_fallback = "battery-empty";
		} else if (battery.percentage <= 35) {
			image_fallback = "battery-low";
		} else if (battery.percentage <= 75) {
			image_fallback = "battery-good";
		} else {
			image_fallback = "battery-full";
		}

		image_name = "battery-level-%d".printf(rounded);

		// Fully charged OR charging
		if (battery.state == 4) {
			image_name = "battery-full-charged-symbolic";
			tip = _("Battery fully charged."); // Imply the battery is charged
		} else if (battery.state == 1) {
			image_name += "-charging-symbolic";
			image_fallback += "-charging-symbolic";
			string time_to_full_str = _("Unknown"); // Default time_to_full_str to Unknown
			int time_to_full = (int)battery.time_to_full; // Seconds for battery time_to_full

			if (time_to_full > 0) { // If TimeToFull is known
				int hours = time_to_full / (60 * 60);
				int minutes = time_to_full / 60 - hours * 60;
				time_to_full_str = "%d:%02d".printf(hours, minutes); // Set inner charging duration to hours:minutes
			}

			tip = _("Battery charging") + ": %d%% (%s)".printf((int)battery.percentage, time_to_full_str); // Set to charging: % (Unknown/Time)
		} else {
			image_name += "-symbolic";
			int hours = (int)battery.time_to_empty / (60 * 60);
			int minutes = (int)battery.time_to_empty / 60 - hours * 60;
			tip = _("Battery remaining") + ": %d%% (%d:%02d)".printf((int)battery.percentage, hours, minutes);
		}

		// Set the percentage label text if it's changed
		string labe = "%d%%".printf((int)battery.percentage);
		string old = this.percent_label.get_label();
		if (old != labe) {
			this.percent_label.set_text(labe);
		}

		// Set a handy tooltip until we gain a menu in StatusApplet
		set_tooltip_text(tip);

		Gtk.IconTheme theme = Gtk.IconTheme.get_default();
		Gtk.IconInfo? result = theme.lookup_icon(image_name, Gtk.IconSize.MENU, 0);

		this.image.set_from_icon_name((result != null) ? image_name : image_fallback, Gtk.IconSize.MENU);
		this.queue_draw();
	}
}

const string POWER_PROFILES_DBUS_NAME = "net.hadess.PowerProfiles";
const string POWER_PROFILES_DBUS_OBJECT_NAME = "/net/hadess/PowerProfiles";

[DBus (name = "net.hadess.PowerProfiles")]
public interface PowerProfilesDBus : Object {
	public abstract HashTable<string, Variant>[] profiles { owned get; }
	public abstract string active_profile { owned get; set; }
}

public class PowerProfilesOption : Gtk.RadioButton {
	public PowerProfilesOption(PowerProfilesDBus profiles_proxy, string profile_name, string display_name) {
		label = display_name;

		this.toggled.connect(() => {
			if (this.get_active()) {
				profiles_proxy.active_profile = profile_name;
			}
		});
	}

}

public class PowerProfilesSelector : Gtk.Box {
	// Power profile toggles
	private PowerProfilesOption radio_power_save;
	private PowerProfilesOption radio_power_balanced;
	private PowerProfilesOption radio_power_performance;

	public PowerProfilesSelector(PowerProfilesDBus profiles_proxy) {
		orientation = Gtk.Orientation.VERTICAL;
		spacing = 6;

		var profiles = new GenericSet<string>(str_hash, str_equal);

		foreach (HashTable<string, Variant> profile in profiles_proxy.profiles) {
			var profile_value = profile.get("Profile");

			if (!profile_value.is_of_type(VariantType.STRING)) continue;

			profiles.add(profile_value.get_string());
		}

		// need at least two options for it to be meaningful
		if (profiles.length < 2) return;

		var sep = new Gtk.Separator(Gtk.Orientation.HORIZONTAL);
		pack_start(sep, false, false, 1);

		var header = new Gtk.Label("");
		header.set_markup("<b>%s</b>".printf(_("Performance Mode")));
		header.set_halign(Gtk.Align.START);
		pack_start(header);

		var power_profiles_radio_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);

		Gtk.RadioButton radio_group = null;

		if (profiles.contains("power-saver")) {
			radio_power_save = new PowerProfilesOption(profiles_proxy, "power-saver", _("Power Saver"));
			radio_power_save.join_group(radio_group);
			radio_group = radio_power_save;
			power_profiles_radio_box.pack_start(radio_power_save, false, false, 1);
		}

		if (profiles.contains("balanced")) {
			radio_power_balanced = new PowerProfilesOption(profiles_proxy, "balanced", _("Balanced"));
			radio_power_balanced.join_group(radio_group);
			radio_group = radio_power_balanced;
			power_profiles_radio_box.pack_start(radio_power_balanced, false, false, 1);
		}

		if (profiles.contains("performance")) {
			radio_power_performance = new PowerProfilesOption(profiles_proxy, "performance", _("Performance"));
			radio_power_performance.join_group(radio_group);
			radio_group = radio_power_performance;
			power_profiles_radio_box.pack_start(radio_power_performance, false, false, 1);
		}

		pack_start(power_profiles_radio_box);

		// initialize state
		on_active_profile_changed(profiles_proxy.active_profile);

		((DBusProxy) profiles_proxy).g_properties_changed.connect(() => {
			on_active_profile_changed(profiles_proxy.active_profile);
		});

	}

	void on_active_profile_changed(string active_profile) {
		switch(active_profile) {
			case "power-saver":
				radio_power_save.set_active(true);
				break;
			case "balanced":
				radio_power_balanced.set_active(true);
				break;
			case "performance":
				radio_power_performance.set_active(true);
				break;
		}
	}
}

public class PowerIndicator : Gtk.Bin {
	/** Widget containing battery icons to display */
	public Gtk.EventBox? ebox = null;
	public Budgie.Popover? popover = null;
	private Gtk.Box widget = null;
	private Gtk.Box box = null;

	private PowerProfilesDBus profiles_proxy;
	private PowerProfilesSelector power_profiles_selector;

	/** Our upower client */
	public Up.Client client { protected set; public get; }

	private HashTable<string,BatteryIcon?> devices;

	public bool label_visible { set ; get ; default = false; }

	public PowerIndicator() {
		devices = new HashTable<string,BatteryIcon?>(str_hash, str_equal);
		ebox = new Gtk.EventBox();
		add(ebox);

		widget = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 2);
		ebox.add(widget);

		popover = new Budgie.Popover(ebox);
		box = new Gtk.Box(Gtk.Orientation.VERTICAL, 1);
		box.border_width = 6;
		popover.add(box);

		var button = new Gtk.Button.with_label(_("Power settings"));
		button.get_style_context().add_class(Gtk.STYLE_CLASS_FLAT);
		button.clicked.connect(open_power_settings);
		button.get_child().set_halign(Gtk.Align.START);
		box.pack_start(button, false, false, 0);
		box.show_all();

		client = new Up.Client();

		Bus.watch_name(BusType.SYSTEM, POWER_PROFILES_DBUS_NAME, BusNameWatcherFlags.NONE, has_power_profiles, lost_power_profiles);

		this.sync_devices();
		client.device_added.connect(this.on_device_added);
		client.device_removed.connect(this.on_device_removed);
		toggle_show();
	}

	void has_power_profiles() {
		if (profiles_proxy != null) {
			create_power_profiles_options();
			return;
		}

		Bus.get_proxy.begin<PowerProfilesDBus>(BusType.SYSTEM, POWER_PROFILES_DBUS_NAME, POWER_PROFILES_DBUS_OBJECT_NAME, 0, null, on_proxy_get);
	}

	void lost_power_profiles() {
		power_profiles_selector.destroy();
	}

	void on_proxy_get(Object? o, AsyncResult? res) {
		try {
			profiles_proxy = Bus.get_proxy.end(res);

			if (profiles_proxy.active_profile != null)
				create_power_profiles_options();

		} catch (Error e) {
			warning("unable to connect to net.hadess.PowerProfiles: %s", e.message);
		}
	}

	void create_power_profiles_options() {
		power_profiles_selector = new PowerProfilesSelector(profiles_proxy);
		box.pack_start(power_profiles_selector);
		box.show_all();
	}

	public void change_orientation(Gtk.Orientation orient) {
		int spacing = (orient == Gtk.Orientation.VERTICAL) ? 5 : 0;
		unowned BatteryIcon? icon = null;
		var iter = HashTableIter<string,BatteryIcon?>(this.devices);
		while (iter.next(null, out icon)) {
			icon.set_spacing(spacing);
			icon.set_orientation(orient);
		}
		widget.set_orientation(orient);
	}

	public void update_labels(bool visible) {
		this.label_visible = visible;

		unowned BatteryIcon? icon = null;
		var iter = HashTableIter<string,BatteryIcon?>(this.devices);
		while (iter.next(null, out icon)) {
			icon.label_visible = this.label_visible;
		}
		/* Fix glitching with Arc theming + "theme-regions" */
		this.get_toplevel().queue_draw();
	}

	private bool is_interesting(Up.Device device) {
		return  device.kind == Up.DeviceKind.BATTERY;
	}

	void open_power_settings() {
		popover.hide();

		var app_info = new DesktopAppInfo("budgie-power-panel.desktop");

		if (app_info == null) return;

		try {
			app_info.launch(null, null);
		} catch (Error e) {
			message("Unable to launch gnome-power-panel.desktop: %s", e.message);
		}
	}

	/**
	 * Add a new device to the tree
	 */
	void on_device_added(Up.Device device) {
		string object_path = device.get_object_path();
		if (devices.contains(object_path)) {
			/* Treated as a change event */
			devices.lookup(object_path).update_ui(device);
			return;
		}
		if (!this.is_interesting(device)) return;
		var icon = new BatteryIcon(device);
		icon.label_visible = this.label_visible;
		devices.insert(object_path, icon);
		widget.pack_start(icon);
		change_orientation(widget.get_orientation());
		toggle_show();
	}


	void toggle_show() {
		if (devices.size() < 1) {
			hide();
		} else {
			show_all();
		}
	}

	/**
	 * Remove a device from our display
	 */
	void on_device_removed(string object_path) {
		if (!devices.contains(object_path)) return;
		unowned BatteryIcon? icon = devices.lookup(object_path);
		widget.remove(icon);
		devices.remove(object_path);
		toggle_show();
	}

	private void sync_devices() {
		// try to discover batteries
		var devices = client.get_devices();

		devices.foreach((device) => {
			this.on_device_added(device);
		});
		toggle_show();
	}
}
