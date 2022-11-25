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

public class UsageMonitorRavenPlugin : Budgie.RavenPlugin, Peas.ExtensionBase {
	public Budgie.RavenWidget new_widget_instance(string uuid, GLib.Settings? settings) {
		return new UsageMonitorRavenWidget(uuid, settings);
	}

	public bool supports_settings() {
		return false;
	}
}

public class UsageMonitorRavenWidget : Budgie.RavenWidget {
	private Gtk.Revealer? content_revealer = null;
	private UsageMonitorRow? cpu = null;
	private UsageMonitorRow? ram = null;
	private UsageMonitorRow? swap = null;
	private ProcStatContents? prev = null;

	public UsageMonitorRavenWidget(string uuid, GLib.Settings? settings) {
		initialize(uuid, settings);

		var main_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
		add(main_box);

		var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
		header.get_style_context().add_class("raven-header");
		main_box.add(header);

		var icon = new Gtk.Image.from_icon_name("utilities-system-monitor", Gtk.IconSize.MENU);
		icon.margin = 8;
		icon.margin_start = 12;
		icon.margin_end = 12;
		header.add(icon);

		var header_label = new Gtk.Label("Usage Monitor");
		header.add(header_label);

		var content = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
		content.get_style_context().add_class("raven-background");

		content_revealer = new Gtk.Revealer();
		content_revealer.add(content);
		content_revealer.reveal_child = true;
		main_box.add(content_revealer);

		var header_reveal_button = new Gtk.Button.from_icon_name("pan-down-symbolic", Gtk.IconSize.MENU);
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

		var rows = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
		rows.margin_start = 12;
		rows.margin_end = 12;
		rows.margin_top = 8;
		rows.margin_bottom = 8;
		content.add(rows);

		cpu = new UsageMonitorRow("CPU");
		rows.add(cpu);

		ram = new UsageMonitorRow("RAM");
		rows.add(ram);

		swap = new UsageMonitorRow("Swap");
		rows.add(swap);

		update_cpu();
		update_ram_and_swap();

		Timeout.add(1000, () => {
			update_cpu();
			update_ram_and_swap();
			return GLib.Source.CONTINUE;
		});

		show_all();
	}

	private void update_cpu() {
		ProcStatContents? stat = read_proc_stat();

		if (prev != null && stat != null) {
			float total_cpu_usage = (float) (stat.busy - prev.busy) / (float) (stat.total - prev.total);
			cpu.update(total_cpu_usage);
		}

		prev = stat;
	}

	private void update_ram_and_swap() {
		ProcMeminfoContents? meminfo = read_proc_meminfo();

		if (meminfo == null) {
			ram.hide();
			swap.hide();
			return;
		}

		if (meminfo.swap_total > 0) {
			var swap_used = meminfo.swap_total - meminfo.swap_free - meminfo.swap_cached;
			swap.update((float) swap_used / (float) meminfo.swap_total);
		} else {
			swap.hide();
		}

		if (meminfo.mem_total > 0) {
			var mem_used = meminfo.mem_total - meminfo.mem_available;
			ram.update((float) mem_used / (float) meminfo.mem_total);
		} else {
			ram.hide();
		}
	}

	private ProcStatContents? read_proc_stat() {
		var stat_file = File.new_for_path("/proc/stat");
		if (!stat_file.query_exists()) {
			return null;
		}

		try {
			var input_stream = new DataInputStream(stat_file.read());

			string line;
			while ((line = input_stream.read_line()) != null) {
				if (!line.has_prefix("cpu ")) {
					continue;
				}

				ulong user = 0;
				ulong nice = 0;
				ulong system = 0;
				ulong idle = 0;
				ulong iowait = 0;
				ulong irq = 0;
				ulong softirq = 0;

				int read = line.scanf(
					"%*s %lu %lu %lu %lu %lu %lu %lu",
					&user, &nice, &system, &idle, &iowait, &irq, &softirq
				);

				if (read == 7) {
					ProcStatContents? contents = ProcStatContents();
					contents.total = user + nice + system + idle + iowait + irq + softirq;
					contents.busy = contents.total - idle - iowait;
					return contents;
				}
			}
		} catch (Error e) {}

		return null;
	}

	private ProcMeminfoContents? read_proc_meminfo() {
		var meminfo_file = File.new_for_path("/proc/meminfo");
		if (!meminfo_file.query_exists()) {
			return null;
		}

		try {
			var input_stream = new DataInputStream(meminfo_file.read());

			var contents = ProcMeminfoContents();
			string line;
			while ((line = input_stream.read_line()) != null) {
				string label = "";
				ulong value = -1;

				line.scanf("%s %lu", label, &value);

				if (label == "MemTotal:") {
					contents.mem_total = value;
				} else if (label == "MemAvailable:") {
					contents.mem_available = value;
				} else if (label == "SwapTotal:") {
					contents.swap_total = value;
				} else if (label == "SwapFree:") {
					contents.swap_free = value;
				} else if (label == "SwapCached:") {
					contents.swap_cached = value;
				}
			}

			return contents;
		} catch (Error e) {
			return null;
		}
	}
}

private struct ProcMeminfoContents {
	ulong mem_total;
	ulong mem_available;
	ulong swap_total;
	ulong swap_free;
	ulong swap_cached;
}

private struct ProcStatContents {
	ulong total;
	ulong busy;
}

private class UsageMonitorRow : Gtk.Box {
	private Gtk.LevelBar bar;
	private Gtk.Label percentage;

	public UsageMonitorRow(string name) {
		Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 8);

		var label = new Gtk.Label(null);
		label.set_markup(name);
		pack_start(label, false, false, 0);

		bar = new Gtk.LevelBar();
		bar.add_offset_value("low", 0.8);
		bar.add_offset_value("high", 0.9);
		bar.add_offset_value("full", 1.0);
		bar.valign = Gtk.Align.CENTER;
		bar.halign = Gtk.Align.END;
		bar.set_size_request(150, 10);
		set_center_widget(bar);

		percentage = new Gtk.Label(null);
		percentage.set_text("0%");
		pack_end(percentage, false, false, 0);
	}

	public void update(float new_value) {
		bar.value = new_value;
		bar.queue_draw();
		percentage.set_text("%.0f%%".printf(new_value * 100));
		show();
	}
}

[ModuleInit]
public void peas_register_types(TypeModule module) {
	// boilerplate - all modules need this
	var objmodule = module as Peas.ObjectModule;
	objmodule.register_extension_type(typeof(Budgie.RavenPlugin), typeof(UsageMonitorRavenPlugin));
}
