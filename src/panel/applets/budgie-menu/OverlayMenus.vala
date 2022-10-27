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

using Gdk;
using GLib;
using Gtk;

/**
 * Class to contain our overlay menu items
 */
public class OverlayMenus : Revealer {
	const string LOGIND_LOGIN = "org.freedesktop.login1";
	const string G_SESSION = "org.gnome.SessionManager";

	private Stack? stack = null;
	private ListBox? folder_items = null;
	private Box? power_menu_items = null;

	private MenuItem? lock_menu = null;
	private MenuItem? suspend_menu = null;
	private MenuItem? hibernate_menu = null;
	private MenuItem? reboot_menu = null;
	private MenuItem? shutdown_menu = null;
	private MenuItem? logout_menu = null;

	private ScreenSaverRemote? saver = null;
	private XDGDirTrackerRemote? xdgtracker = null;
	private LogindRemote? logind_interface = null;
	private SessionManagerRemote? session = null;

	private List<UserDirectory> items_to_show = null;
	private HashTable<UserDirectory, MenuItem>? user_directory_buttons = null;

	/**
	 * Emitted when an item in the menu has been clicked.
	 */
	public signal void item_clicked();

	public OverlayMenus() {
		Object(
			valign: Align.END,
			halign: Align.START,
			transition_duration: 250,
			transition_type: RevealerTransitionType.SLIDE_LEFT
		);
	}

	construct {
		this.stack = new Stack();
		this.stack.get_style_context().add_class("budgie-menu-overlay");
		this.stack.set_homogeneous(false); // Make sure pages are same size
		this.stack.set_transition_type(StackTransitionType.NONE); // Don't waste any time on transitions

		this.folder_items = new ListBox();
		this.folder_items.get_style_context().add_class("left-overlay-menu");
		this.folder_items.activate_on_single_click = false;
		this.folder_items.selection_mode = SelectionMode.NONE; 
		this.folder_items.set_filter_func(this.filter_list_box_item);
		this.folder_items.set_sort_func(this.sort_xdg_menu_items); // Ensure our menu items use our locale sorting

		this.user_directory_buttons = new HashTable<UserDirectory, MenuItem>(direct_hash, direct_equal);
		this.user_directory_buttons.set(UserDirectory.DESKTOP, new MenuItem("Desktop", "user-desktop-symbolic"));
		this.user_directory_buttons.set(UserDirectory.DOCUMENTS, new MenuItem("Documents", "folder-documents-symbolic"));
		this.user_directory_buttons.set(UserDirectory.DOWNLOAD, new MenuItem("Downloads", "folder-downloads-symbolic"));
		this.user_directory_buttons.set(UserDirectory.MUSIC, new MenuItem("Music", "folder-music-symbolic"));
		this.user_directory_buttons.set(UserDirectory.PICTURES, new MenuItem("Pictures", "folder-pictures-symbolic"));
		this.user_directory_buttons.set(UserDirectory.VIDEOS, new MenuItem("Videos", "folder-videos-symbolic"));

		this.items_to_show = this.user_directory_buttons.get_keys();

		this.user_directory_buttons.foreach((key, val) => {
			unowned string dir = Environment.get_user_special_dir(key);

			if (dir != null) {
				string dir_base = Path.get_basename(dir); // Get the name of the folder
				val.label_text = dir_base;
			}

			val.set_data<UserDirectory>("user-directory", key); // Add the UserDirectory as the data for this button
			this.folder_items.insert(val, -1); // Add each of the menu items
			val.clicked.connect((val) => { this.handle_xdg_dir_clicked(val);});
		});

		this.setup_dbus.begin();

		this.lock_menu = new MenuItem(_("Lock"), "system-lock-screen-symbolic");
		this.logout_menu = new MenuItem(_("Logout"), "system-log-out-symbolic");
		this.suspend_menu = new MenuItem(_("Suspend"), "system-suspend-symbolic");
		this.hibernate_menu = new MenuItem(_("Hibernate"), "system-hibernate-symbolic");
		this.reboot_menu = new MenuItem(_("Restart"), "system-restart-symbolic");
		this.shutdown_menu = new MenuItem(_("Shutdown"), "system-shutdown-symbolic");

		this.power_menu_items = new Box(Orientation.VERTICAL, 0);
		this.power_menu_items.get_style_context().add_class("right-overlay-menu");

		this.power_menu_items.add(lock_menu);
		this.power_menu_items.add(logout_menu);
		this.power_menu_items.add(suspend_menu);
		this.power_menu_items.add(hibernate_menu);
		this.power_menu_items.add(reboot_menu);
		this.power_menu_items.add(shutdown_menu);

		this.stack.add_named(this.folder_items, "xdg");
		this.stack.add_named(this.power_menu_items, "power");
		this.add(this.stack);

		this.setup_menu_events();
	}

	private bool filter_list_box_item(ListBoxRow row) {
		MenuItem menu_item = (MenuItem) row.get_child();
		UserDirectory xdg_dir = menu_item.get_data("user-directory");
		return (this.items_to_show.index(xdg_dir) != -1);
	}

	private void handle_xdg_dir_clicked(Button item) {
		UserDirectory xdg_dir = item.get_data("user-directory");
		unowned string? path = Environment.get_user_special_dir(xdg_dir);

		if (path == null) {
			return;
		}

		Gdk.AppLaunchContext launch_context = (Display.get_default()).get_app_launch_context(); // Get the app launch context for the default display
		launch_context.set_screen(Screen.get_default()); // Set the screen
		launch_context.set_timestamp(CURRENT_TIME);

		DesktopAppInfo? appinfo = (DesktopAppInfo) AppInfo.get_default_for_type("inode/directory", true); // Ensure we using something which can handle inode/directory
		List<string> files = new List<string>();
		files.append("file://"+path);

		try {
			appinfo.launch_uris(files, launch_context);
		} catch (Error e) {
			warning("Failed to open %s: %s", path, e.message);
		}
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

		try {
			this.xdgtracker = yield Bus.get_proxy(BusType.SESSION, "org.buddiesofbudgie.XDGDirTracker", "/org/buddiesofbudgie/XDGDirTracker");
			this.xdgtracker.xdg_dirs_exist.connect(this.handle_xdg_dirs_changed);
			this.handle_xdg_dirs_changed(this.xdgtracker.get_dirs());
		} catch (Error e) {
			warning("Unable to connect to Budgie XDGDirTracker: %s", e.message);
		}
	}

	private void handle_xdg_dirs_changed(UserDirectory[] dirs) {
		this.items_to_show = new List<UserDirectory>(); // Remove all items

		for (var i = 0; i < dirs.length; i++) { // For each directory
			this.items_to_show.append(dirs[i]);
		}

		this.folder_items.invalidate_filter();
	}

	/**
	 * Sets up all of the event handling needed to make everything work.
	 */
	private void setup_menu_events() {
		logout_menu.clicked.connect(this.logout);
		lock_menu.clicked.connect(this.lock_screen);
		suspend_menu.clicked.connect(this.suspend);
		reboot_menu.clicked.connect(this.reboot);
		hibernate_menu.clicked.connect(this.hibernate);
		shutdown_menu.clicked.connect(this.shutdown);
	}

	private int sort_xdg_menu_items (ListBoxRow row1, ListBoxRow row2) {
		MenuItem row1_menu = (MenuItem) row1.get_child();
		MenuItem row2_menu = (MenuItem) row2.get_child();

		if ((row1_menu == null) || (row2 == null)) {
			return 0;
		}

		return row1_menu.label_text.collate(row2_menu.label_text);
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

	public void set_visible_menu(string vis) {
		this.halign = vis == "xdg" ? Align.START : Align.END;
		this.set_transition_type(vis == "xdg" ? RevealerTransitionType.SLIDE_LEFT : RevealerTransitionType.SLIDE_RIGHT);
		this.stack.set_visible_child_name(vis);
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
