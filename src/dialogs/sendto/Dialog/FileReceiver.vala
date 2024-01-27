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

public class FileReceiver : BaseDialog {
	public string session_path { get; set; }

	private Notification notification;

	private string file_name = "";

	public FileReceiver(Gtk.Application application) {
		Object(application: application, resizable: false);
	}

	construct {
		title = _("Bluetooth File Transfer");
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
			filename_label.set_markup(Markup.printf_escaped(_("<b>File name</b>: %s"), transfer.name));
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
}
