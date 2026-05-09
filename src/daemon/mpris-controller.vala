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
	public const string MPRIS_CONTROLLER_DBUS_NAME = "org.buddiesofbudgie.BudgieMprisController";
	public const string MPRIS_CONTROLLER_DBUS_PATH = "/org/buddiesofbudgie/MprisController";

	/**
	 * MprisController is exposed on the session bus and forwards media-key
	 * commands to whichever MPRIS player MprisTracker considers "current".
	 */
	[DBus (name="org.buddiesofbudgie.BudgieMprisController")]
	public class MprisController : GLib.Object {
		private MprisTracker tracker;

		[DBus (visible=false)]
		public MprisController() {
			tracker = new MprisTracker();
		}

		[DBus (visible=false)]
		public void setup_dbus(bool replace) {
			var flags = BusNameOwnerFlags.ALLOW_REPLACEMENT;
			if (replace) flags |= BusNameOwnerFlags.REPLACE;
			Bus.own_name(BusType.SESSION, MPRIS_CONTROLLER_DBUS_NAME, flags,
				on_bus_acquired, () => {}, Budgie.DaemonNameLost);
		}

		private void on_bus_acquired(DBusConnection conn) {
			try {
				conn.register_object(MPRIS_CONTROLLER_DBUS_PATH, this);
				debug("MprisController: registered on DBus");
			} catch (Error e) {
				critical("MprisController: failed to register: %s", e.message);
			}
		}

		// ------------------------------------------------------------------ //
		// Helpers
		// ------------------------------------------------------------------ //

		/** Returns the name of the currently active player, or an empty string. */
		public string current_player() throws DBusError, IOError {
			var c = tracker.current_client;
			return c != null ? c.player.identity : "";
		}

		// ------------------------------------------------------------------ //
		// DBus Tracker methods
		// ------------------------------------------------------------------ //

		/** Toggle play / pause on the current player. */
		public void play_pause() throws DBusError, IOError {
			var c = tracker.current_client;
			if (c == null) {
				debug("MprisController.PlayPause: no active player");
				return;
			}
			c.player.play_pause.begin((obj, res) => {
				try {
					c.player.play_pause.end(res);
				} catch (Error e) {
					warning("MprisController.PlayPause failed for %s: %s", c.bus_name, e.message);
				}
			});
		}

		/** Start playback on the current player. */
		public void play() throws DBusError, IOError {
			var c = tracker.current_client;
			if (c == null) {
				debug("MprisController.Play: no active player");
				return;
			}
			c.player.play.begin((obj, res) => {
				try {
					c.player.play.end(res);
				} catch (Error e) {
					warning("MprisController.Play failed for %s: %s", c.bus_name, e.message);
				}
			});
		}

		/** Pause the current player. */
		public void pause() throws DBusError, IOError {
			var c = tracker.current_client;
			if (c == null) {
				debug("MprisController.Pause: no active player");
				return;
			}
			c.player.pause.begin((obj, res) => {
				try {
					c.player.pause.end(res);
				} catch (Error e) {
					warning("MprisController.Pause failed for %s: %s", c.bus_name, e.message);
				}
			});
		}

		/** Stop the current player. */
		public void stop() throws DBusError, IOError {
			var c = tracker.current_client;
			if (c == null) {
				debug("MprisController.Stop: no active player");
				return;
			}
			c.player.stop.begin((obj, res) => {
				try {
					c.player.stop.end(res);
				} catch (Error e) {
					warning("MprisController.Stop failed for %s: %s", c.bus_name, e.message);
				}
			});
		}

		/** Skip to the next track on the current player. */
		public void next() throws DBusError, IOError {
			var c = tracker.current_client;
			if (c == null) {
				debug("MprisController.Next: no active player");
				return;
			}
			if (!c.player.can_go_next) {
				debug("MprisController.Next: player reports can_go_next=false");
				return;
			}
			c.player.next.begin((obj, res) => {
				try {
					c.player.next.end(res);
				} catch (Error e) {
					warning("MprisController.Next failed for %s: %s", c.bus_name, e.message);
				}
			});
		}

		/** Go back to the previous track on the current player. */
		public void previous() throws DBusError, IOError {
			var c = tracker.current_client;
			if (c == null) {
				debug("MprisController.Previous: no active player");
				return;
			}
			if (!c.player.can_go_previous) {
				debug("MprisController.Previous: player reports can_go_previous=false");
				return;
			}
			c.player.previous.begin((obj, res) => {
				try {
					c.player.previous.end(res);
				} catch (Error e) {
					warning("MprisController.Previous failed for %s: %s", c.bus_name, e.message);
				}
			});
		}
	}
}
