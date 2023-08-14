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

public class SendtoApplication : Gtk.Application {
	private const OptionEntry[] OPTIONS = {
		{ "daemon", 'd', 0, OptionArg.NONE, out silent, "Run the application in the background", null },
		{ "send", 'f', 0, OptionArg.NONE, out send, "Send a file via Bluetooth", null },
		{ "", 0, 0, OptionArg.STRING_ARRAY, out arg_files, "Get files", null }, // TODO: Better description
		{ null },
	};

	private static bool silent = true;
	private static bool send = false;
	private static bool active_once;
	[CCode (array_length = false, array_null_terminated = true)]
	private static string[]? arg_files = {};

	private Bluetooth.ObjectManager manager;
	private Bluetooth.Obex.Agent agent;
	private Bluetooth.Obex.Transfer transfer;

	private FileSender file_sender;
	private List<FileSender> file_senders;
	private ScanDialog scan_dialog;

	construct {
		application_id = "org.buddiesofbudgie.Sendto";
		flags |= ApplicationFlags.HANDLES_COMMAND_LINE;
	}

	public override int command_line(ApplicationCommandLine command) {
		var args = command.get_arguments();
		var context = new OptionContext(null);
		context.add_main_entries(OPTIONS, null);

		// Try to parse the command args
		try {
			context.parse_strv(ref args);
		} catch (Error e) {
			warning("Unable to parse command args: %s", e.message);
			return 1;
		}

		activate();

		// Exit early if no files to send
		if (!send) return 0;

		File[] files = {};
		foreach (unowned var arg_file in arg_files) {
			var file = command.create_file_for_arg(arg_file);

			if (file.query_exists()) {
				files += file;
			} else {
				warning("File not found: %s", file.get_path());
			}
		}

		// If we weren't given any files, open a file picker dialog
		if (files.length == 0) {
			var picker = new Gtk.FileChooserDialog(
				_("Files to send"),
				null,
				Gtk.FileChooserAction.OPEN,
				_("_Cancel"), Gtk.ResponseType.CANCEL,
				_("_Open"), Gtk.ResponseType.ACCEPT
			) {
				select_multiple = true,
			};

			if (picker.run() == Gtk.ResponseType.ACCEPT) {
				var picked_files = picker.get_files();
				picked_files.foreach((file) => {
					files += file;
				});
			}

			picker.destroy();
		}

		// Still no files, exit
		if (files.length == 0) return 0;

		// Create the Bluetooth scanner dialog if it doesn't yet exist
		if (scan_dialog == null) {
			scan_dialog = new ScanDialog(this, manager);

			// Wait for asyncronous initialization before showing the dialog
			Idle.add(() => {
				scan_dialog.show_all();
				return Source.REMOVE;
			});
		} else {
			// Dialog already exists, present it
			scan_dialog.present();
		}

		// Clear our pointer when the scan dialog is destroyed
		scan_dialog.destroy.connect(() => {
			scan_dialog = null;
		});

		// Send the files when a device has been selected
		scan_dialog.send_file.connect((device) => {
			if (!insert_sender(files, device)) {
				file_sender = new FileSender(this);
				file_sender.add_files(files, device);
				file_senders.append(file_sender);
				file_sender.show_all();
				file_sender.destroy.connect(() => {
					file_senders.foreach((sender) => {
						if (sender.device == file_sender.device) {
							file_senders.remove_link(file_senders.find(sender));
						}
					});
				});
			}
		});

		arg_files = {};
		send = false;

		return 0;
	}

	protected override void activate() {
		if (silent) {
			if (active_once) {
				release();
			}
			hold();
			silent = false;
		}

		if (manager == null) {
			file_senders = new List<FileSender>();

			manager = new Bluetooth.ObjectManager();
			manager.notify["has-object"].connect(() => {
				var build_path = Path.build_filename(Environment.get_home_dir(), ".local", "share", "contractor");
				var file = File.new_for_path(
					Path.build_filename(
						build_path,
						Environment.get_application_name() + ".contract"
					)
				);
				var file_exists = file.query_exists();

				// Create the parent directory for the contract file if it doesn't exist
				if (!File.new_for_path(build_path).query_exists()) {
					DirUtils.create(build_path, 0700);
				}

				// If we have Bluetooth devices, create our Obex Agent and contract file
				if (manager.has_object) {
					// Create our Obex Agent if we haven't been activated yet
					if (!active_once) {
						agent = new Bluetooth.Obex.Agent();
						agent.transfer_view.connect(dialog_active);
						// TODO: Connect agent signals
						active_once = true;
					}

					// Create and write to our Obex contract file if it doesn't exist
					if (!file_exists) {
						var keyfile = new KeyFile();
						keyfile.set_string ("Contractor Entry", "Name", _("Send Files via Bluetooth"));
						keyfile.set_string ("Contractor Entry", "Icon", "bluetooth-active");
						keyfile.set_string ("Contractor Entry", "Description", _("Send files to device…"));
						keyfile.set_string ("Contractor Entry", "Exec", "org.buddiesofbudgie.sendto -f %F");
						keyfile.set_string ("Contractor Entry", "MimeType", "!inode;");

						try {
							keyfile.save_to_file(file.get_path());
						} catch (Error e) {
							critical("Error saving contract file: %s", e.message);
						}
					}
				} else {
					// Delete the contract file if it exists
					if (file_exists) {
						try {
							file.delete();
						} catch (Error e) {
							critical("Error deleting old contract file: %s", e.message);
						}
					}
				}
			});
		}
	}

	private void dialog_active(string session_path) {
		// TODO: Receivers

		// Show any file sender dialogs if there is a transfer session for the
		// given path
		file_senders.foreach((sender) => {
			if (sender.transfer.session == session_path) {
				sender.show_all();
			}
		});
	}

	private bool insert_sender(File[] files, Bluetooth.Device device) {
		bool exists = false;

		// Pass the files to send to the correct sender
		file_senders.foreach((sender) => {
			if (sender.device == device) {
				sender.add_files(files, device);
				sender.present();
				exists = true;
			}
		});

		return exists;
	}
}

public static int main(string[] args) {
	Intl.setlocale(LocaleCategory.ALL, "");
	Intl.bindtextdomain(Budgie.GETTEXT_PACKAGE, Budgie.LOCALEDIR);
	Intl.bind_textdomain_codeset(Budgie.GETTEXT_PACKAGE, "UTF-8");
	Intl.textdomain(Budgie.GETTEXT_PACKAGE);

	var app = new SendtoApplication();
	return app.run(args);
}
