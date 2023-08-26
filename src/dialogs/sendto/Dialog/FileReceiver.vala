/*
 * This file is part of budgie-desktop
 *
 * Copyright Budgie Desktop Developers, elementary LLC
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

public class FileReceiver : Gtk.Dialog {
	public Bluetooth.Device device { get; set; }
	public string session_path { get; set; }

	public Bluetooth.Obex.Transfer transfer;

	private Gtk.ProgressBar progress_bar;
	private Gtk.Label device_label;
	private Gtk.Label directory_label;
	private Gtk.Label progress_label;
	private Gtk.Label filename_label;
	private Gtk.Label rate_label;
	private Gtk.Image device_image;

	private Notification notification;

	private string file_name = "";
	private int start_time = 0;
	private uint64 total_size = 0;

	public FileReceiver(Gtk.Application application) {
		Object(application: application, resizable: false);
	}

	construct {
		title = _("Bluetooth File Transfer");

		notification = new Notification("Bluetooth");
		notification.set_priority(NotificationPriority.NORMAL);

		var icon_image = new Gtk.Image.from_icon_name ("bluetooth-active", Gtk.IconSize.DIALOG) {
			valign = Gtk.Align.END,
			halign = Gtk.Align.END,
		};

		device_image = new Gtk.Image() {
			valign = Gtk.Align.END,
			halign = Gtk.Align.END,
		};

		var overlay = new Gtk.Overlay() {
			margin_right = 12,
		};
		overlay.add(icon_image);
		overlay.add_overlay(device_image);

		device_label = new Gtk.Label(null) {
			max_width_chars = 45,
			wrap = true,
			xalign = 0,
			use_markup = true,
		};
		device_label.get_style_context().add_class("primary");

		directory_label = new Gtk.Label(null) {
			max_width_chars = 45,
			wrap = true,
			xalign = 0,
			use_markup = true,
		};

		filename_label = new Gtk.Label(Markup.printf_escaped("<b>%s</b>:", _("File name"))) {
			max_width_chars = 45,
			wrap = true,
			xalign = 0,
			use_markup = true,
		};

		rate_label = new Gtk.Label(Markup.printf_escaped("<b>%s</b>:", _("Transfer rate"))) {
			max_width_chars = 45,
			wrap = true,
			xalign = 0,
			use_markup = true,
		};

		progress_bar = new Gtk.ProgressBar() {
			hexpand = true,
			margin_top = 4,
			margin_bottom = 4,
		};

		progress_label = new Gtk.Label(null) {
			max_width_chars = 45,
			hexpand = false,
			wrap = true,
			xalign = 0,
			margin_bottom = 4,
		};

		var message_grid = new Gtk.Grid() {
			column_spacing = 0,
			row_spacing = 4,
			width_request = 450,
			margin = 10,
		};

		message_grid.attach(overlay, 0, 0, 1, 3);
		message_grid.attach(device_label, 1, 0, 1, 1);
		message_grid.attach(directory_label, 1, 1, 1, 1);
		message_grid.attach(filename_label, 1, 2, 1, 1);
		message_grid.attach(rate_label, 1, 3, 1, 1);
		message_grid.attach(progress_bar, 1, 4, 1, 1);
		message_grid.attach(progress_label, 1, 5, 1, 1);

		get_content_area().add(message_grid);

		// Now add the dialog buttons
		add_button(_("Close"), Gtk.ResponseType.CLOSE);
		var reject_button = add_button(_("Reject"), Gtk.ResponseType.REJECT);
		reject_button.get_style_context().add_class(Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);

		// Hook up the responses
		response.connect((response_id) => {
			if (response_id == Gtk.ResponseType.REJECT) {
				// Cancel the current transfer if it is active
				try {
					transfer.cancel();
				} catch (Error e) {
					warning("Error rejecting Bluetooth transfer: %s", e.message);
				}

				destroy();
			} else {
				// Close button clicked, hide
				hide_on_delete();
			}
		});

		delete_event.connect(() => {
			if (transfer.status == "active") {
				return hide_on_delete();
			} else {
				return false;
			}
		});
	}

	public void set_transfer(Bluetooth.Device device, string path) {
		this.device = device;

		device_label.set_markup(GLib.Markup.printf_escaped(_("<b>From</b>: %s"), device.alias));
		directory_label.set_markup(Markup.printf_escaped(_("<b>To</b>: %s"), Environment.get_user_special_dir (UserDirectory.DOWNLOAD)));
		device_image.set_from_gicon(new ThemedIcon(device.icon ?? "bluetooth-active"), Gtk.IconSize.LARGE_TOOLBAR);
		start_time = (int) get_real_time();

		try {
			transfer = Bus.get_proxy_sync<Bluetooth.Obex.Transfer>(BusType.SESSION, "org.bluez.obex", path);
			((DBusProxy) transfer).g_properties_changed.connect((changed, invalid) => {
				transfer_progress();
			});

			total_size = transfer.size;
			session_path = transfer.session;
			filename_label.set_markup(Markup.printf_escaped (_("<b>File name</b>: %s"), transfer.name));
		} catch (Error e) {
			warning("Error accepting Bluetooth file transfer: %s", e.message);
		}
	}

	private void transfer_progress() {
		switch (transfer.status) {
			case "error":
				notification.set_icon(device_image.gicon);
				notification.set_title(_("File transfer failed"));
				notification.set_body(_("File '%s' not received from %s").printf(transfer.name, device.alias));
				((Gtk.Window) get_toplevel()).application.send_notification("org.buddiesofbudgie.bluetooth", notification);
				destroy();
				break;
			case "queued":
				break;
			case "active":
				// Save the file name here because it won't be available later
				var name = transfer.filename;
				if (name != null) {
					file_name = name;
				}
				// Update the transfer progress UI
				on_transfer_progress(transfer.transferred);
				break;
			case "complete":
				try {
					move_to_downloads(file_name);
				} catch (Error e) {
					notification.set_icon(device_image.gicon);
					notification.set_title(_("File transfer failed"));
					notification.set_body(_("File '%s' from %s not received: %s".printf(transfer.name, device.alias, e.message)));
					((Gtk.Window) get_toplevel()).application.send_notification("org.buddiesofbudgie.bluetooth", notification);
					warning("Error saving transferred file: %s", e.message);
				}
				destroy();
				break;
		}
	}

	private void move_to_downloads(string path) throws Error {
		var source = File.new_for_path(path);
		var file_name = Path.build_filename(Environment.get_user_special_dir(UserDirectory.DOWNLOAD), source.get_basename());
		var dest = get_save_name(file_name);

		source.move(dest, FileCopyFlags.ALL_METADATA);

		notification.set_icon(device_image.gicon);
		notification.set_title(_("File transferred successfully"));
		notification.set_body(_("Saved file from %s to '%s'").printf(device.alias, dest.get_path()));
		((Gtk.Window) get_toplevel()).application.send_notification("org.buddiesofbudgie.bluetooth", notification);
	}

	private File? get_save_name(string uri) {
		var file = File.new_for_path(uri);

		if (!file.query_exists()) return file;

		var base_name = file.get_basename();
		var ext_index = base_name.last_index_of(".");
		var name = ext_index == -1 ? base_name : base_name.substring(0, ext_index);
		var ext = ext_index == -1 ? "" : base_name.substring(ext_index + 1);
		var time = new DateTime.now_local().format_iso8601();

		return File.new_for_path(name + " " + time + ext);
	}

	private void on_transfer_progress(uint64 transferred) {
		progress_bar.fraction = (double) transferred / (double) total_size;
		int current_time = (int) get_real_time();
		int elapsed_time = (current_time - start_time) / 1000000;
		if (current_time < start_time + 1000000) return;
		if (elapsed_time == 0) return;

		uint64 transfer_rate = transferred / elapsed_time;
		if (transfer_rate == 0) return;

		rate_label.label = Markup.printf_escaped(_("<b>Transfer rate:</b> %s / s"), format_size(transfer_rate));
		uint64 remaining_time = (total_size - transferred) / transfer_rate;
		progress_label.label = _("%s of %s received. Time remaining: %s").printf(format_size(transferred), format_size(total_size), format_time((int) remaining_time));
	}

	private string format_time(int seconds) {
		if (seconds < 0) seconds = 0;
		if (seconds < 60) return ngettext("%d second", "%d seconds", seconds).printf(seconds);

		int minutes;
		if (seconds < 60 * 60) {
			minutes = (seconds + 30) / 60;
			return ngettext("%d minute", "%d minutes", minutes).printf(minutes);
		}

		int hours = seconds / (60 * 60);
		if (seconds < 60 * 60 * 4) {
			minutes = (seconds - hours * 60 * 60 + 30) / 60;
			string h = ngettext("%u hour", "%u hours", hours).printf(hours);
			string m = ngettext("%u minute", "%u minutes", minutes).printf(minutes);
			///TRANSLATORS: For example "1 hour, 8 minutes".
			return _("%s, %s").printf(h, m);
		}

		return ngettext("about %d hour", "about %d hours", hours).printf(hours);
	}
}
