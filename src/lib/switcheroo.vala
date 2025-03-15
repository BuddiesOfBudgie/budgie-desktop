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
	[DBus (name = "net.hadess.SwitcherooControl")]
	public interface SwitcherooDBus : Object {
		/** Get whether or not this system has a dual-GPU setup. */
		[DBus (name = "HasDualGpu")]
		public abstract bool has_dual_gpu { owned get; }

		/** Get the GPUs for this system. */
		[DBus (name = "GPUs")]
		public abstract HashTable<string, Variant>[] gpus { owned get; }
	}

	/**
	* This class connects to switeroo-control via DBus for handling dual-GPUs.
	*/
	public class Switcheroo : Object {
		private static SwitcherooDBus switcheroo;

		/** Returns whether or not the system has a dual-GPU setup. */
		public bool dual_gpu {
			get {
				return switcheroo.has_dual_gpu;
			}
		}

		static construct {
			Bus.get_proxy.begin<SwitcherooDBus>(
				BusType.SYSTEM,
				"net.hadess.SwitcherooControl",
				"/net/hadess/SwitcherooControl",
				0,
				null,
				on_dbus_get
			);
		}

		private static void on_dbus_get(Object? o, AsyncResult? res) {
			try {
				switcheroo = Bus.get_proxy.end(res);
			} catch (Error e) {
				critical("Unable to connect to Switcheroo DBus: %s", e.message);
			}
		}

		/**
		* Attempt to apply a GPU environment to a launch context for an application.
		*/
		public void apply_gpu_profile(AppLaunchContext context, bool use_default_gpu) {
			// Make sure we have Switcheroo before trying to do anything
			if (switcheroo == null) {
				warning("switcheroo-control not available, can't apply GPU environment");
				return;
			}

			// Only one GPU, nothing to do
			if (!dual_gpu) {
				return;
			}

			// Iterate over the GPUs and check if we need to apply an environment
			// to our launch context
			foreach (HashTable<string, Variant> gpu in switcheroo.gpus) {
				bool default_gpu = gpu.get("Default").get_boolean();

				// Skip this GPU if:
				//   a. It is the default GPU but we want the non-default
				//   b. It isn't the default GPU but we do want the default
				if (default_gpu != use_default_gpu) {
					continue;
				}

				// Get the GPU's environment
				var env = gpu.get("Environment");
				var env_parts = env.get_strv();

				// Set all of the environment variables to our launch context
				for (int i = 0; env_parts[i] != null; i = i + 2) {
					context.setenv(env_parts[i], env_parts[i + 1]);
				}

				// We set an environment, exit here
				return;
			}

			// Log a message if no GPUs are found
			warning("No GPUs found, cannot apply profile");
		}
	}
}
