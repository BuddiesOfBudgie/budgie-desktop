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

public class FileSender : BaseDialog {
	private int current_file = 0;
	private int total_files = 0;

	private DBusConnection connection;
	private DBusProxy client_proxy;
	private DBusProxy session;
	private File file_path;
	private ObjectPath session_path;

	private Gtk.ListStore file_store;

	public FileSender(Gtk.Application application) {
		Object(application: application, resizable: false);
	}

	construct {
		title = _("Bluetooth File Transfer");

		file_store = new Gtk.ListStore(1, typeof(GLib.File));

		directory_label.set_markup(Markup.printf_escaped("<b>%s</b>:", _("From")));
		device_label.set_markup(Markup.printf_escaped("<b>%s</b>:", _("To")));

		// Hook up the responses
		response.connect((response_id) => {
			if (response_id == Gtk.ResponseType.CANCEL) {
				// Cancel the current session if it is active
				if (transfer != null && transfer.status == "active") {
					remove_session.begin();
				}
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
			directory_label.set_markup(GLib.Markup.printf_escaped(_("<b>From</b>: %s"), file_path.get_parent().get_path()));
			device_label.set_markup(GLib.Markup.printf_escaped(_("<b>To</b>: %s"), device.alias));
			device_image.set_from_gicon(new ThemedIcon(device.icon == null ? "bluetooth-active" : device.icon), Gtk.IconSize.LARGE_TOOLBAR);
			progress_label.label = _("Trying to connect to %s…").printf(device.alias);

			// Prepare to send the file
			VariantBuilder builder = new VariantBuilder(VariantType.DICTIONARY);
			builder.add("{sv}", "Target", new Variant.string("opp"));
			Variant parameters = new Variant("(sa{sv})", device.address, builder);
			Variant variant_client = yield client_proxy.call("CreateSession", parameters, GLib.DBusCallFlags.NONE, -1);
			variant_client.get("(o)", out session_path);

			// Create our Obex session
			session = yield new GLib.DBusProxy(
				connection,
				DBusProxyFlags.NONE,
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
			var suggested_button = retry_dialog.add_button(_("Retry"), Gtk.ResponseType.ACCEPT);
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
		directory_label.set_markup(GLib.Markup.printf_escaped(_("<b>From</b>: %s"), file_path.get_parent().get_path()));
		device_label.set_markup(GLib.Markup.printf_escaped(_("<b>To</b>: %s"), device.alias));
		device_image.set_from_gicon(new ThemedIcon(device.icon ?? "bluetooth-active"), Gtk.IconSize.LARGE_TOOLBAR);
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
				var suggested_button = retry_dialog.add_button(_("Retry"), Gtk.ResponseType.ACCEPT);
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
		notification.set_icon(new ThemedIcon(device.icon ?? "bluetooth-active"));
		notification.set_title(_("File transferred successfully"));
		notification.set_body(Markup.printf_escaped("<b>From:</b> %s <b>Sent to:</b> %s", file_path.get_path(), device.alias));
		notification.set_priority(NotificationPriority.NORMAL);
		((Gtk.Window) get_toplevel()).application.send_notification("org.buddiesofbudgie.bluetooth", notification);
	}
}
