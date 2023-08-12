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

public class FileSender : Gtk.Dialog {
	public Bluetooth.Obex.Transfer transfer;
	public Bluetooth.Device device;

	private int current_file = 0;
	private int total_files = 0;
	private uint64 total_size = 0;
	private int start_time = 0;

	private DBusConnection connection;
	private DBusProxy client_proxy;
	private DBusProxy session;
	private File file_path;
	private ObjectPath session_path;

	private Gtk.ListStore file_store;

	private Gtk.Label path_label;
	private Gtk.Label device_label;
	private Gtk.Label filename_label;
	private Gtk.Label rate_label;
	private Gtk.Label progress_label;
	private Gtk.ProgressBar progress_bar;
	private Gtk.Image icon_label;

	public FileSender(Gtk.Application application) {
		Object(application: application, resizable: false);
	}

	construct {
		file_store = new Gtk.ListStore(1, typeof(GLib.File));

		var icon_image = new Gtk.Image.from_icon_name ("bluetooth-active", Gtk.IconSize.DIALOG) {
			valign = Gtk.Align.END,
			halign = Gtk.Align.END,
		};

		icon_label = new Gtk.Image() {
			valign = Gtk.Align.END,
			halign = Gtk.Align.END,
		};

		var overlay = new Gtk.Overlay();
		overlay.add(icon_image);
		overlay.add_overlay(icon_label);

		path_label = new Gtk.Label(Markup.printf_escaped("<b>%s</b>:", _("From"))) {
			max_width_chars = 45,
			wrap = true,
			xalign = 0,
			use_markup = true,
		};
		path_label.get_style_context().add_class("primary");

		device_label = new Gtk.Label(Markup.printf_escaped("<b>%s</b>:", _("To"))) {
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
		};

		progress_label = new Gtk.Label(null) {
			max_width_chars = 45,
			hexpand = false,
			wrap = true,
			xalign = 0,
		};

		var message_grid = new Gtk.Grid() {
			column_spacing = 0,
			width_request = 450,
			margin_start = 10,
			margin_end = 15
		};

		message_grid.attach(overlay, 0, 0, 1, 3);
		message_grid.attach(path_label, 1, 0, 1, 1);
		message_grid.attach(device_label, 1, 1, 1, 1);
		message_grid.attach(filename_label, 1, 2, 1, 1);
		message_grid.attach(rate_label, 1, 3, 1, 1);
		message_grid.attach(progress_bar, 1, 4, 1, 1);
		message_grid.attach(progress_label, 1, 5, 1, 1);

		get_content_area().add(message_grid);

		// Now add the dialog buttons
		add_button(_("Close"), Gtk.ResponseType.CLOSE);
		var reject_transfer = add_button(_("Cancel"), Gtk.ResponseType.CANCEL);
		reject_transfer.get_style_context().add_class(Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);

		// Hook up the responses
		response.connect((response_id) => {
			if (response_id == Gtk.ResponseType.CANCEL) {
				// Cancel the current transfer if it is active
				if (transfer != null && transfer.status == "active") {
					try {
						transfer.cancel();
					} catch (Error e) {
						warning("Error cancelling Bluetooth transfer: %s", e.message);
					}

					// TODO: remove_session.begin();
				}

				destroy();
			} else {
				// Close button clicked, hide or close
				if (transfer.status == "active") {
					hide_on_delete();
				} else {
					destroy();
				}
			}
		});

		delete_event.connect(() => {
			if (transfer.status == "active") {
				return hide_on_delete();
			} else {
				destroy();
			}
		});
	}

	public void add_files(File[] files, Bluetooth.Device device) {
		// Add each file to our list of files
		foreach (var file in files) {
			Gtk.TreeIter iter;
			file_store.append(out iter);
			file_store.set(iter, 0, file);
		}

		this.device = device;

		Gtk.TreeIter iter;
		file_store.get_iter_first(out iter);
		file_store.get(iter, 0, out file_path);

		total_n_current();
		create_session.begin();
	}

	private void total_n_current(bool total = false) {
		total_files = 0;
		int current = 0;

		file_store.foreach((model, path, iter) => {
			File file;
			model.get(iter, 0, out file);

			if (file == file_path) {
				current = total_files;
			}

			total_files++;
			return false;
		});

		if (!total) {
			current_file = current + 1;
		}
	}

	private async void create_session() {
		try {
			// Create our Obex client
			connection = yield Bus.get(BusType.SESSION);
			client_proxy = yield new DBusProxy(
				connection,
				DBusProxyFlags.DO_NOT_LOAD_PROPERTIES | DBusProxyFlags.DO_NOT_CONNECT_SIGNALS,
				null,
				"org.bluez.obex",
				"/org/bluez/obex",
				"org.bluez.obex.Client1"
			);

			// Update the labels
			path_label.set_markup(GLib.Markup.printf_escaped(_("<b>From</b>: %s"), file_path.get_parent().get_path()));
			device_label.set_markup(GLib.Markup.printf_escaped(_("<b>To</b>: %s"), device.alias));
			icon_label.set_from_gicon(new ThemedIcon(device.icon == null ? "bluetooth-active" : device.icon), Gtk.IconSize.LARGE_TOOLBAR);
			progress_label.label = _("Trying to connect to %s…").printf(device.alias);

			// Prepare to send the file
			VariantBuilder builder = new VariantBuilder(VariantType.DICTIONARY);
			builder.add("{sv}", "Target", new Variant.string("opp"));
			Variant parameters = new Variant("(sa{sv})", device.address, builder);
			Variant variant_client = yield client_proxy.call("CreateSession", parameters, GLib.DBusCallFlags.NONE, -1);
			variant_client.get("(o)", out session_path);

			// Create our Obex session
			session = yield new GLib.DBusProxy (
				connection,
				GLib.DBusProxyFlags.NONE,
				null,
				"org.bluez.obex",
				session_path,
				"org.bluez.obex.ObjectPush1"
			);

			// Start the transfer
			send_file.begin();
		} catch (Error e) {
			// Hide ourselves
			hide_on_delete();

			// Create a dialog asking the user to retry the transfer
			var retry_dialog = new Gtk.MessageDialog(
				this,
				Gtk.DialogFlags.MODAL,
				Gtk.MessageType.ERROR,
				Gtk.ButtonsType.NONE,
				null
			) {
				text = _("Connecting to '%s' failed").printf(device.alias),
				secondary_text = "%s\n%s".printf(
					"Transferring file '%s' failed.".printf(file_path.get_basename()),
					_("The file has not been transferred.")
				),
			};

			retry_dialog.add_button(_("Cancel"), Gtk.ResponseType.CANCEL);
			var suggested_button = retry_dialog.add_button(_("Accept"), Gtk.ResponseType.ACCEPT);
			suggested_button.get_style_context().add_class(Gtk.STYLE_CLASS_SUGGESTED_ACTION);

			retry_dialog.response.connect((response_id) => {
				if (response_id == Gtk.ResponseType.ACCEPT) {
					create_session.begin();
					present();
				} else {
					destroy();
				}

				retry_dialog.destroy();
			});

			retry_dialog.show_all();
			progress_label.label = e.message.split("org.bluez.obex.Error.Failed:")[1];
			warning("Error transferring '%s' to '%s': %s", file_path.get_basename(), device.alias, e.message);
		}
	}

	private async void remove_session() {
		try {
			yield client_proxy.call("RemoveSession", new Variant("(o)", session_path), DBusCallFlags.NONE, -1);
		} catch (Error e) {
			warning("Error removing Obex transfer session: %s", e.message);
		}
	}

	private async void send_file() {
		// Update the labels
		path_label.set_markup(GLib.Markup.printf_escaped(_("<b>From</b>: %s"), file_path.get_parent().get_path()));
		device_label.set_markup(GLib.Markup.printf_escaped(_("<b>To</b>: %s"), device.alias));
		icon_label.set_from_gicon(new ThemedIcon(device.icon == null ? "bluetooth-active" : device.icon), Gtk.IconSize.LARGE_TOOLBAR);
		progress_label.label = _("Waiting for acceptance on %s…").printf(device.alias);

		try {
			var variant = yield session.call("SendFile", new Variant("(s)", file_path.get_path()), DBusCallFlags.NONE, -1);
			start_time = (int) get_real_time();

			ObjectPath object_path;
			variant.get("(oa{sv})", out object_path, null);

			transfer = Bus.get_proxy_sync<Bluetooth.Obex.Transfer>(
				BusType.SESSION,
				"org.bluez.obex",
				object_path,
				DBusProxyFlags.NONE
			);

			filename_label.set_markup(Markup.printf_escaped("<b>File name</b>: %s", transfer.name));
			total_size = transfer.size;

			((DBusProxy) transfer).g_properties_changed.connect((changed, invalid) => {
				update_progress();
			});
		} catch (Error e) {
			warning("Error transferring file '%s' to '%s': %s", transfer.name, device.alias, e.message);
		}
	}

	private void update_progress() {
		switch (transfer.status) {
			case "error":
				hide_on_delete();

				// Create a dialog asking the user to retry the transfer
				var retry_dialog = new Gtk.MessageDialog(
					this,
					Gtk.DialogFlags.MODAL,
					Gtk.MessageType.ERROR,
					Gtk.ButtonsType.NONE,
					null
				) {
					text = _("Transferring '%s' failed").printf(file_path.get_basename()),
					secondary_text = "%s\n%s".printf(
						_("The transfer was interrupted or declined by %s.").printf(device.alias),
						_("The file has not been transferred.")
					),
				};

				retry_dialog.add_button(_("Cancel"), Gtk.ResponseType.CANCEL);
				var suggested_button = retry_dialog.add_button(_("Accept"), Gtk.ResponseType.ACCEPT);
				suggested_button.get_style_context().add_class(Gtk.STYLE_CLASS_SUGGESTED_ACTION);

				retry_dialog.response.connect((response_id) => {
					if (response_id == Gtk.ResponseType.ACCEPT) {
						create_session.begin();
						present();
					} else {
						destroy();
					}

					retry_dialog.destroy();
				});

				retry_dialog.show_all();
				progress_bar.fraction = 0.0;
				remove_session.begin();
				break;
			case "active":
				on_transfer_progress(transfer.transferred);
				break;
			case "complete":
				send_notify();

				if (!try_next_file()) {
					remove_session.begin();
					destroy();
				}
				break;
			default:
				break;
		}
	}

	private void on_transfer_progress(uint64 transferred) {
		progress_bar.fraction = (double) transferred / (double) total_size;
		int current_time = (int) get_real_time();
		int elapsed_time = (current_time - start_time) / 1000000;
		if (current_time < start_time + 1000000) return;
		if (elapsed_time == 0) return;

		uint64 transfer_rate = transferred / elapsed_time;
		if (transfer_rate == 0) return;

		rate_label.label = Markup.printf_escaped (_("<b>Transfer rate:</b> %s"), format_size(transfer_rate));
		uint64 remaining_time = (total_size - transferred) / transfer_rate;
		progress_label.label = _("(%i/%i) %s of %s sent. Time remaining: %s").printf (current_file, total_files, format_size(transferred), format_size(total_size), format_time((int) remaining_time));
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

	private bool try_next_file() {
		Gtk.TreeIter iter;
		if (file_store.get_iter_from_string(out iter, current_file.to_string())) {
			file_store.get(iter, 0, out file_path);
			send_file.begin();
			total_n_current();
			return true;
		}

		return false;
	}

	private void send_notify() {
		var notification = new Notification("Bluetooth");
		notification.set_icon(new ThemedIcon(device.icon));
		notification.set_title(_("File transferred successfully"));
		notification.set_body(Markup.printf_escaped("<b>From:</b> %s <b>Sent to:</b> %s", file_path.get_path(), device.alias));
		notification.set_priority(NotificationPriority.NORMAL);
		((Gtk.Window) get_toplevel()).application.send_notification("org.buddiesofbudgie.bluetooth", notification);
	}
}
