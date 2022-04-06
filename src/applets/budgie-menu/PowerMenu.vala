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

/**
 * Class to contain menu items to do things like lock the screen, restart
 * or shutdown the system, and more.
 */
public class PowerMenu : Gtk.Revealer {
	const string LOGIND_LOGIN = "org.freedesktop.login1";
	const string G_SESSION = "org.gnome.SessionManager";

	private Gtk.Box? menu_items = null;

	private MenuItem? lock_menu = null;
	private MenuItem? suspend_menu = null;
	private MenuItem? hibernate_menu = null;
	private MenuItem? reboot_menu = null;
	private MenuItem? shutdown_menu = null;
	private MenuItem? logout_menu = null;

	private ScreenSaverRemote? saver = null;
	private SessionManagerRemote? session = null;
	private LogindRemote? logind_interface = null;

	/**
	 * Emitted when an item in the menu has been clicked.
	 */
	public signal void item_clicked();

	public PowerMenu() {
		Object(
			valign: Gtk.Align.END,
			halign: Gtk.Align.END,
			transition_duration: 250,
			transition_type: Gtk.RevealerTransitionType.SLIDE_LEFT
		);
	}

	construct {
		this.setup_dbus.begin();

		this.lock_menu = new MenuItem(_("Lock"), "system-lock-screen-symbolic");
		this.logout_menu = new MenuItem(_("Logout"), "system-log-out-symbolic");
		this.suspend_menu = new MenuItem(_("Suspend"), "system-suspend-symbolic");
		this.hibernate_menu = new MenuItem(_("Hibernate"), "system-hibernate-symbolic");
		this.reboot_menu = new MenuItem(_("Restart"), "system-restart-symbolic");
		this.shutdown_menu = new MenuItem(_("Shutdown"), "system-shutdown-symbolic");

		this.menu_items = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
		this.menu_items.get_style_context().add_class("budgie-menu-overlay");

		this.menu_items.add(lock_menu);
		this.menu_items.add(logout_menu);
		this.menu_items.add(suspend_menu);
		this.menu_items.add(hibernate_menu);
		this.menu_items.add(reboot_menu);
		this.menu_items.add(shutdown_menu);

		this.add(this.menu_items);

		this.setup_menu_events();
	}

	/**
	 * Set up all of the DBus bits to make all the items work.
	 */
	private async void setup_dbus() {
		try {
			this.logind_interface = yield Bus.get_proxy(BusType.SYSTEM, LOGIND_LOGIN, "/org/freedesktop/login1");
		} catch (Error e) {
			warning("Unable to connect to logind: %s", e.message);
		}

		try {
			this.saver = yield Bus.get_proxy(BusType.SESSION, "org.gnome.ScreenSaver", "/org/gnome/ScreenSaver");
		} catch (Error e) {
#if HAVE_GNOME_SCREENSAVER
			warning("Unable to connect to gnome-screensaver: %s", e.message);
#else
			warning("Unable to connect to budgie-screensaver: %s", e.message);
#endif
			return;
		}

		try {
			this.session = yield Bus.get_proxy(BusType.SESSION, G_SESSION, "/org/gnome/SessionManager");
		} catch (Error e) {
			warning("Unable to connect to GNOME Session: %s", e.message);
		}
	}

	/**
	 * Sets up all of the event handling needed to make everything work.
	 */
	private void setup_menu_events() {
		logout_menu.button_release_event.connect((e) => {
			if (e.button != 1) {
				return Gdk.EVENT_PROPAGATE;
			}
			logout();
			return Gdk.EVENT_STOP;
		});

		lock_menu.button_release_event.connect((e) => {
			if (e.button != 1) {
				return Gdk.EVENT_PROPAGATE;
			}
			lock_screen();
			return Gdk.EVENT_STOP;
		});

		suspend_menu.button_release_event.connect((e) => {
			if (e.button != 1) {
				return Gdk.EVENT_PROPAGATE;
			}
			suspend();
			return Gdk.EVENT_STOP;
		});

		reboot_menu.button_release_event.connect((e) => {
			if (e.button != 1) {
				return Gdk.EVENT_PROPAGATE;
			}
			reboot();
			return Gdk.EVENT_STOP;
		});

		hibernate_menu.button_release_event.connect((e) => {
			if (e.button != 1) {
				return Gdk.EVENT_PROPAGATE;
			}
			hibernate();
			return Gdk.EVENT_STOP;
		});

		shutdown_menu.button_release_event.connect((e) => {
			if (e.button != 1) {
				return Gdk.EVENT_PROPAGATE;
			}
			shutdown();
			return Gdk.EVENT_STOP;
		});
	}

	private void logout() {
		this.item_clicked();
		if (session == null) {
			return;
		}

		Idle.add(() => {
			try {
				session.Logout(0);
			} catch (Error e) {
				warning("Failed to logout: %s", e.message);
			}
			return false;
		});
	}

	private void hibernate() {
		this.item_clicked();
		if (logind_interface == null) {
			return;
		}

		Idle.add(() => {
			try {
				lock_screen();
				logind_interface.hibernate(false);
			} catch (Error e) {
				warning("Cannot hibernate: %s", e.message);
			}
			return false;
		});
	}

	private void reboot() {
		this.item_clicked();
		if (session == null) {
			return;
		}

		Idle.add(() => {
			session.Reboot.begin();
			return false;
		});
	}

	private void shutdown() {
		this.item_clicked();
		if (session == null) {
			return;
		}

		Idle.add(() => {
			session.Shutdown.begin();
			return false;
		});
	}

	private void suspend() {
		this.item_clicked();
		if (logind_interface == null) {
			return;
		}

		Idle.add(() => {
			try {
				lock_screen();
				logind_interface.suspend(false);
			} catch (Error e) {
				warning("Cannot suspend: %s", e.message);
			}
			return false;
		});
	}

	private void lock_screen() {
		this.item_clicked();
		Idle.add(() => {
			try {
#if HAVE_GNOME_SCREENSAVER
				if (saver == null) { // attempt to connect to dbus if not started previously
					saver = Bus.get_proxy_sync(BusType.SESSION, "org.gnome.ScreenSaver", "/org/gnome/ScreenSaver");
				}
#endif
				saver.lock();
			} catch (Error e) {
				warning("Cannot lock screen: %s", e.message);
#if HAVE_GNOME_SCREENSAVER
				saver = null; // allow another retry to lock the screen on a failure
#endif
			}
			return false;
		});
	}
}
