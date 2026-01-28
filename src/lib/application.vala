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

namespace Budgie {
	/**
	* Represents an application that can be ran.
	*/
	public class Application : Object {
		public string name { get; construct set; }
		public string description { get; private set; default = ""; }
		public string desktop_id { get; construct set; }
		public string exec { get; private set; }
		public string[] keywords { get; private set;}
		public Icon icon { get; private set; default = new ThemedIcon.with_default_fallbacks("application-default-icon"); }
		public string desktop_path { get; private set; }
		public string categories { get; private set; }
		public string[] content_types { get; private set; }
		public string generic_name { get; private set; default = ""; }
		public bool prefers_default_gpu { get; private set; default = false; }
		public bool should_show { get; private set; default = true; }
		public bool dbus_activatable { get; private set; default = false; }
		public unowned string[] actions { get; private set; }

		/**
		* Emitted when the application is launched.
		*
		* See https://valadoc.org/gio-2.0/GLib.AppLaunchContext.launched.html
		*/
		public signal void launched(AppInfo info, Variant platform_data);

		/**
		* Emitted when the application fails to launch.
		*
		* See https://valadoc.org/gio-2.0/GLib.AppLaunchContext.launch_failed.html
		*/
		public signal void launch_failed(string startup_notify_id);

		private Switcheroo switcheroo;

		/**
		* Create a new application from a `DesktopAppInfo`.
		*/
		public Application(DesktopAppInfo app_info) {
			this.name = app_info.get_display_name();
			this.description = app_info.get_description() ?? name;
			this.exec = app_info.get_commandline();
			this.desktop_id = app_info.get_id();
			this.desktop_path = app_info.get_filename();
			this.keywords = app_info.get_keywords();
			this.categories = app_info.get_categories();
			this.content_types = app_info.get_supported_types();
			this.generic_name = app_info.get_generic_name();
			this.prefers_default_gpu = !app_info.get_boolean("PrefersNonDefaultGPU");
			this.should_show = app_info.should_show();
			this.dbus_activatable = app_info.get_boolean("DBusActivatable");
			this.actions = app_info.list_actions();

			// Try to get an icon from the desktop file
			var desktop_icon = app_info.get_icon();
			if (desktop_icon != null) {
				// Make sure we have a usable icon
				unowned var theme = Gtk.IconTheme.get_default();
				if (theme.lookup_by_gicon(desktop_icon, 64, Gtk.IconLookupFlags.USE_BUILTIN) != null) {
					this.icon = desktop_icon;
				}
			}
		}

		construct {
			this.switcheroo = new Switcheroo();
		}

		public AppLaunchContext create_launch_context() {
			// Create a launch context and try to apply a GPU profile
			var context = new AppLaunchContext();

			// Hook up our signals for rebroadcast
			context.launched.connect((info, data) => {
				this.launched(info, data);
			});
			context.launch_failed.connect((startup_id) => {
				this.launch_failed(startup_id);
			});

			// Try to apply a GPU profile if necessary for multiple GPU setups
			switcheroo.apply_gpu_profile(context, this.prefers_default_gpu);

			return context;
		}

		public bool launch() {
			var context = create_launch_context();
			return launch_with_context(context);
		}

		/**
		* Launch this application.
		*
		* Returns `true` if the application launched successfully,
		* otherwise `false`.
		*/
		public bool launch_with_context(AppLaunchContext context) {
			try {
				var info = new DesktopAppInfo(this.desktop_id);

				var cmd = info.get_commandline();
				string[] parsed_args;
				bool fallback = false;

				try {
					GLib.Shell.parse_argv(cmd, out parsed_args);
				} catch (Error e) {
					warning("Failed to parse command line for '%s': %s", this.desktop_id, e.message);
					// Fallback: try the default launcher
					fallback = true;
				}

				// If not pkexec, use the DesktopAppInfo to launch the app normally
				if (parsed_args.length == 0 || parsed_args[0] != "pkexec" || fallback == true) {
					new DesktopAppInfo(this.desktop_id).launch(null, context);
					return true;
				}

				// Collect any pkexec options (those starting with '-') right after 'pkexec'
				var pkexec_opts = new GLib.List<string>();
				int i = 1;
				while (i < parsed_args.length && parsed_args[i].has_prefix("-")) {
					pkexec_opts.append(parsed_args[i]);
					i++;
				}

				// The remainder after options is the original executable and its arguments
				var original_prog_and_args = new GLib.List<string>();
				for (int j = i; j < parsed_args.length; j++) {
					original_prog_and_args.append(parsed_args[j]);
				}

				// Gather Wayland info from the *user* environment
				var wayland_display = GLib.Environment.get_variable("WAYLAND_DISPLAY"); // e.g. "wayland-0"
				var xdg_runtime_dir = GLib.Environment.get_variable("XDG_RUNTIME_DIR"); // e.g. "/run/user/1000"

				// Build a new argv - format will now be
				// pkexec [opts] env variable1=... variable2=... <executable> <arguments>
				var final_args = new GLib.List<string>();
				final_args.append("pkexec");
				foreach (var opt in pkexec_opts) {
					final_args.append(opt);
				}

				// Always use env so we can add variables for Wayland
				final_args.append("env");

				bool injected_any = false;
				if (wayland_display != null && wayland_display.length > 0) {
					// IMPORTANT: keep WAYLAND_DISPLAY as the socket name (e.g., "wayland-0")
					final_args.append("WAYLAND_DISPLAY=%s".printf(wayland_display));
					injected_any = true;
				}
				if (xdg_runtime_dir != null && xdg_runtime_dir.length > 0) {
					// This must be the user's runtime dir, e.g., "/run/user/1000"
					final_args.append("XDG_RUNTIME_DIR=%s".printf(xdg_runtime_dir));
					injected_any = true;
				}

				// Append the original program and args
				foreach (var a in original_prog_and_args) {
					final_args.append(a);
				}

				// Convert the list to a string array
				string[] argv = {};
				foreach (var a in final_args) {
					argv += a;
				}

				// Use the existing environment (pkexec would normally strip the environment vars,
				// but we're using 'env' in the program portion to execute)
				string[] envv = GLib.Environ.get();

				// Spawn the pkexec process async
				Pid child_pid;
				GLib.Process.spawn_async(
					"/",                   // working dir (or null to inherit)
					argv,
					envv,
					GLib.SpawnFlags.SEARCH_PATH | GLib.SpawnFlags.DO_NOT_REAP_CHILD,
					null,
					out child_pid
				);
				GLib.ChildWatch.add(child_pid, (pid, status) => {
					GLib.Process.close_pid(pid);
				});

				return true;

			} catch (Error e) {
				warning("Failed to launch application '%s': %s", name, e.message);
				return false;
			}

			return true;
		}

		/**
		* Launch this application with the given action.
		*/
		public void launch_action(string action) {
			var context = create_launch_context();

			launch_action_with_context(action, context);
		}

		/**
		* Launch this application with the given action and launch context.
		*/
		public void launch_action_with_context(string action, AppLaunchContext context) {
			new DesktopAppInfo(this.desktop_id).launch_action(action, context);
		}
	}
}
