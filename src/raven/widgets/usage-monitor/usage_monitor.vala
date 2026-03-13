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

using GTop;

public class UsageMonitorRavenPlugin : Budgie.RavenPlugin, Peas.ExtensionBase {
	public Budgie.RavenWidget new_widget_instance(string uuid, GLib.Settings? settings) {
		return new UsageMonitorRavenWidget(uuid, settings);
	}

	public bool supports_settings() {
		return true;
	}
}

public class UsageMonitorRavenWidget : Budgie.RavenWidget {
	private Gtk.Revealer? content_revealer = null;
	private Gtk.Button? header_reveal_button = null;
	private UsageMonitorRow? cpu = null;
	private UsageMonitorRow? ram = null;
	private UsageMonitorRow? swap = null;

	private GTop.Cpu? prev_cpu = null;

	private uint timeout_id = 0;

	public UsageMonitorRavenWidget(string uuid, GLib.Settings? settings) {
		initialize(uuid, settings);

		GTop.init();

		var main_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
		add(main_box);

		var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
		header.get_style_context().add_class("raven-header");
		main_box.add(header);

		var icon = new Gtk.Image.from_icon_name("utilities-system-monitor-symbolic", Gtk.IconSize.MENU);
		icon.margin = 4;
		icon.margin_start = 12;
		icon.margin_end = 10;
		header.add(icon);

		var header_label = new Gtk.Label(_("Usage Monitor"));
		header.add(header_label);

		var content = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
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
		header_reveal_button.clicked.connect(on_header_reveal_clicked);
		header.pack_end(header_reveal_button, false, false, 0);

		var rows = new Gtk.Grid();
		rows.hexpand = true;
		rows.margin_start = 12;
		rows.margin_end = 12;
		rows.margin_top = 8;
		rows.margin_bottom = 8;
		rows.set_column_spacing(8);
		content.add(rows);

		cpu = new UsageMonitorRow(_("CPU"), 0);
		rows.attach(cpu.label, 0, cpu.index, 1, 1);
		rows.attach(cpu.bar, 1, cpu.index, 1, 1);
		rows.attach(cpu.percentage, 2, cpu.index, 1, 1);

		ram = new UsageMonitorRow(_("RAM"), 1);
		rows.attach(ram.label, 0, ram.index, 1, 1);
		rows.attach(ram.bar, 1, ram.index, 1, 1);
		rows.attach(ram.percentage, 2, ram.index, 1, 1);

		swap = new UsageMonitorRow(_("Swap"), 2);
		rows.attach(swap.label, 0, swap.index, 1, 1);
		rows.attach(swap.bar, 1, swap.index, 1, 1);
		rows.attach(swap.percentage, 2, swap.index, 1, 1);

		show_all();

		settings.changed.connect(settings_updated);
		settings_updated("show-swap-usage");

		update_cpu();
		update_ram_and_swap();

		raven_expanded.connect(on_raven_expanded);
	}

	private void on_header_reveal_clicked() {
		content_revealer.reveal_child = !content_revealer.child_revealed;
		var image = (Gtk.Image?) header_reveal_button.get_image();
		if (content_revealer.reveal_child) {
			image.set_from_icon_name("pan-down-symbolic", Gtk.IconSize.MENU);
		} else {
			image.set_from_icon_name("pan-end-symbolic", Gtk.IconSize.MENU);
		}
	}

	private void on_raven_expanded(bool expanded) {
		if (!expanded && timeout_id != 0) {
			Source.remove(timeout_id);
			timeout_id = 0;
		} else if (expanded && timeout_id == 0) {
			timeout_id = Timeout.add(1000, on_update_timeout);
		}
	}

	private bool on_update_timeout() {
		update_cpu();
		update_ram_and_swap();
		return GLib.Source.CONTINUE;
	}

	private void settings_updated(string key) {
		if (key == "show-swap-usage") {
			var should_show = get_instance_settings().get_boolean(key);
			swap.stay_hidden = !should_show;

			if (should_show) swap.show(); else swap.hide();
		}
	}

	private void update_cpu() {
		GTop.Cpu current_cpu;
		GTop.get_cpu(out current_cpu);

		if (prev_cpu != null) {
			uint64 total_delta = current_cpu.total - prev_cpu.total;
			if (total_delta > 0) {
				// idle + iowait = time the CPU was not doing useful work
				uint64 idle_delta = (current_cpu.idle + current_cpu.iowait) -
				(prev_cpu.idle + prev_cpu.iowait);
				float usage = (float)(total_delta - idle_delta) / (float)total_delta;
				cpu.update(usage.clamp(0.0f, 1.0f));
			}
		}

		prev_cpu = current_cpu;
	}

	private void update_ram_and_swap() {
		GTop.Mem mem;
		GTop.get_mem(out mem);

		if (mem.total > 0) {
			float mem_fraction = (float) mem.used / (float) mem.total;
			ram.update(mem_fraction.clamp(0.0f, 1.0f));
		} else {
			ram.hide();
		}

		GTop.Swap swap_info;
		GTop.get_swap(out swap_info);

		if (swap_info.total > 0 && !swap.stay_hidden) {
			float swap_fraction = (float) swap_info.used / (float) swap_info.total;
			swap.update(swap_fraction.clamp(0.0f, 1.0f));
		} else {
			swap.hide();
		}
	}

	public override Gtk.Widget build_settings_ui() {
		return new UsageMonitorRavenWidgetSettings(get_instance_settings());
	}
}

[GtkTemplate (ui="/org/buddiesofbudgie/budgie-desktop/raven/widget/UsageMonitor/settings.ui")]
public class UsageMonitorRavenWidgetSettings : Gtk.Grid {
	[GtkChild]
	private unowned Gtk.Switch? switch_show_swap_usage;

	public UsageMonitorRavenWidgetSettings(Settings? settings) {
		settings.bind("show-swap-usage", switch_show_swap_usage, "active", SettingsBindFlags.DEFAULT);
	}
}

private class UsageMonitorRow {
	public Gtk.Label label;
	public Gtk.LevelBar bar;
	public Gtk.Label percentage;
	public int index;
	public bool stay_hidden = false;

	public UsageMonitorRow(string name, int index) {
		this.index = index;

		label = new Gtk.Label(null);
		label.xalign = 0.0f;
		label.width_chars = 5;
		label.set_markup(name);

		bar = new Gtk.LevelBar();
		bar.name="usagemonitorlevel";
		bar.add_offset_value("full", 0.8);
		bar.add_offset_value("high", 0.9);
		bar.add_offset_value("low", 1.0);
		bar.valign = Gtk.Align.CENTER;
		bar.halign = Gtk.Align.FILL;
		bar.margin_top = 6;
		bar.margin_bottom = 6;
		bar.hexpand = true;
		bar.set_size_request(-1, 10);

		try {
			// alot of themes set the min-width for a level-bar - which isn't great since it
			// limits the granularity - rather than asking each individual theme to change lets
			// override a themes wishes in this very specific use-case
			var css = new Gtk.CssProvider ();
			css.load_from_data ("""
				levelbar#usagemonitorlevel trough block {min-width: 0px; }
			""");
			Gtk.StyleContext.add_provider_for_screen (
				Gdk.Screen.get_default (),
				css,
				Gtk.STYLE_PROVIDER_PRIORITY_USER
			);
		} catch (Error e) {
			warning("Could not load levelbar CSS %s", e.message);
		}

		percentage = new Gtk.Label(null);
		percentage.xalign = 1.0f;
		percentage.width_chars = 4;
		percentage.set_markup("<span size='small'>0%</span>");
	}

	public void update(float new_value) {
		bar.value = new_value;
		bar.queue_draw();
		percentage.set_markup("<span size='small'>%.0f%%</span>".printf(new_value * 100));
		show();
	}

	public void show() {
		if (stay_hidden) return;

		label.show();
		bar.show();
		percentage.show();
	}

	public void hide() {
		label.hide();
		bar.hide();
		percentage.hide();
	}
}

[ModuleInit]
public void peas_register_types(TypeModule module) {
	// boilerplate - all modules need this
	var objmodule = module as Peas.ObjectModule;
	objmodule.register_extension_type(typeof(Budgie.RavenPlugin), typeof(UsageMonitorRavenPlugin));
}
