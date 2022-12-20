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

using GLib;

namespace Budgie {
	public static int main(string[] args) {
		Intl.setlocale(LocaleCategory.ALL, "");
		Intl.bindtextdomain(Budgie.GETTEXT_PACKAGE, Budgie.LOCALEDIR);
		Intl.bind_textdomain_codeset(Budgie.GETTEXT_PACKAGE, "UTF-8");
		Intl.textdomain(Budgie.GETTEXT_PACKAGE);

		var power_app = new PowerApplication();
		return power_app.run();
	}
}
