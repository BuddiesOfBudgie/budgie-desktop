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

public class SendtoApp : Gtk.Application {
	public const OptionEntry[] BLUETOOTH_OPTIONS = {
		{ "silent", 's', 0, OptionArg.NONE, out silent, "Run application in the background", null },
		{ "send", 'f', 0, OptionArg.NONE, out send, "Send file to Bluetooth device", null },
		{ "", 0, 0, OptionArg.STRING_ARRAY, out arg_files, "Get files", null },
		null
	};

	public static bool silent = false;
	public static bool active_once = false;
	public static bool send = false;
	[CCode (array_length = false, array_null_terminated = true)]
	public static string[]? arg_files = {};

	construct {
		application_id = "org.buddiesofbudgie.bluetooth-sendto-dialog";
		flags |= ApplicationFlags.HANDLES_COMMAND_LINE;
		Intl.setlocale(LocaleCategory.ALL, );
	}

	public override int command_line(ApplicationCommandLine command) {
		string[] args_cmd = command.get_arguments();
		unowned string[] args = args_cmd;
		var context = new OptionContext();
		context.add_main_entries(BLUETOOTH_OPTIONS, null);

		try {
			context.parse(ref args);
		} catch (Error e) {
			warning("Error parsing command args: %s", e.message);
		}

		activate();

		return 0;
	}

	public override void activate() {
		if (silent) {
			if (active_once) {
				release();
			}
			hold();
			silent = false;
		}

		// TODO: ObjectManager
	}
}

public static int main(string[] args) {
	var app = new SendtoApp();
	return app.run(args);
}
