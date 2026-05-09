/*
 * This file is part of budgie-desktop
 *
 * Copyright Budgie Desktop Developers
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 */

/**
 * We need to probe the dbus daemon directly, hence this interface.
 */
[DBus (name="org.freedesktop.DBus")]
public interface MprisDBusImpl : Object {
	public abstract async string[] list_names() throws DBusError, IOError;
	public signal void name_owner_changed(string name, string old_owner, string new_owner);
	public signal void name_acquired(string name);
}

/**
 * Vala dbus property notifications are not working. Manually probe property changes.
 */
[DBus (name="org.freedesktop.DBus.Properties")]
public interface MprisDbusPropIface : GLib.Object {
	public signal void properties_changed(string iface, HashTable<string,Variant> changed, string[] invalid);
}

/**
 * Represents the base org.mpris.MediaPlayer2 spec.
 */
[DBus (name="org.mpris.MediaPlayer2")]
public interface MprisIface : GLib.Object {
	public abstract async void raise() throws DBusError, IOError;
	public abstract async void quit() throws DBusError, IOError;

	public abstract bool can_quit { get; set; }
	public abstract bool fullscreen { get; }
	public abstract bool can_set_fullscreen { get; }
	public abstract bool can_raise { get; }
	public abstract bool has_track_list { get; }
	public abstract string identity { owned get; }
	public abstract string desktop_entry { owned get; }
	public abstract string[] supported_uri_schemes { owned get; }
	public abstract string[] supported_mime_types { owned get; }
}

/**
 * Interface for the org.mpris.MediaPlayer2.Player spec.
 *
 * Inherits MprisIface so a single proxy covers both objects.
 */
[DBus (name="org.mpris.MediaPlayer2.Player")]
public interface MprisPlayerIface : MprisIface {
	public abstract async void next() throws DBusError, IOError;
	public abstract async void previous() throws DBusError, IOError;
	public abstract async void pause() throws DBusError, IOError;
	public abstract async void play_pause() throws DBusError, IOError;
	public abstract async void stop() throws DBusError, IOError;
	public abstract async void play() throws DBusError, IOError;
	public abstract async void seek(int64 offset) throws DBusError, IOError;
	public abstract async void open_uri(string uri) throws DBusError, IOError;

	public abstract string playback_status { owned get; }
	public abstract string loop_status { owned get; set; }
	public abstract double rate { get; set; }
	public abstract bool shuffle { set; get; }
	public abstract HashTable<string,Variant> metadata { owned get; }
	public abstract double volume { get; set; }
	public abstract int64 position { get; }
	public abstract double minimum_rate { get; }
	public abstract double maximum_rate { get; }
	public abstract bool can_go_next { get; }
	public abstract bool can_go_previous { get; }
	public abstract bool can_play { get; }
	public abstract bool can_pause { get; }
	public abstract bool can_seek { get; }
	public abstract bool can_control { get; }
}

/**
 * Simple wrapper that keeps a lifetime reference to both proxy interfaces
 * for a single MPRIS media player bus name.
 */
public class MprisClient : GLib.Object {
	/** The bus name this client was created for (e.g. "org.mpris.MediaPlayer2.vlc"). */
	public string bus_name { get; construct; }
	public MprisPlayerIface player { get; construct; }
	public MprisDbusPropIface prop { get; construct; }

	/** Monotonic timestamp of the last playback-state transition to Playing. */
	public int64 last_playing_time { get; set; default = 0; }

	public MprisClient(string bus_name, MprisPlayerIface player, MprisDbusPropIface prop) {
		Object(bus_name: bus_name, player: player, prop: prop);
	}
}

/**
 * Utility: construct a new MprisClient from a bus name, or return null on error.
 */
public async MprisClient? mpris_new_client(string busname) {
	MprisPlayerIface? play = null;
	MprisDbusPropIface? prop = null;

	try {
		play = yield Bus.get_proxy(BusType.SESSION, busname, "/org/mpris/MediaPlayer2");
	} catch (Error e) {
		warning("mpris_new_client: failed to get player proxy for %s: %s", busname, e.message);
		return null;
	}

	try {
		prop = yield Bus.get_proxy(BusType.SESSION, busname, "/org/mpris/MediaPlayer2");
	} catch (Error e) {
		warning("mpris_new_client: failed to get prop proxy for %s: %s", busname, e.message);
		return null;
	}

	return new MprisClient(busname, play, prop);
}

/**
 * MprisTracker tracks all running MPRIS players on the session bus.
 *
 * It maintains a notion of the "current" player: the one that most recently
 * transitioned into the Playing state.  When no player is playing, the most
 * recently active one is kept as current so that stop/prev/next still have
 * somewhere to go.
 *
 * Signals
 * -------
 * client_added(MprisClient)   – a new player appeared on the bus
 * client_removed(MprisClient) – a player vanished from the bus
 * current_player_changed(MprisClient?) – the "current" player changed
 *                                        (null means no players left)
 */
public class MprisTracker : GLib.Object {
	private MprisDBusImpl? dbus_impl = null;

	/** All known players keyed by bus name. */
	private HashTable<string, MprisClient> clients;

	/** The player that most recently went to Playing (or last survivor). */
	private MprisClient? _current_client = null;

	public MprisClient? current_client {
		get { return _current_client; }
		private set {
			if (_current_client == value) return;
			_current_client = value;
			current_player_changed(value);
		}
	}

	public signal void client_added(MprisClient client);
	public signal void client_removed(MprisClient client);
	public signal void current_player_changed(MprisClient? client);

	public MprisTracker() {
		clients = new HashTable<string, MprisClient>(str_hash, str_equal);
		setup_dbus.begin();
	}

	/**
	 * Return a snapshot list of all tracked clients.
	 * The list is valid for the current main-loop iteration only;
	 * do not cache it across async yields or signal handlers.
	 */
	public List<MprisClient> get_clients() {
		var list = new List<MprisClient>();
		clients.foreach((k, v) => list.append(v));
		return (owned) list;
	}

	// ------------------------------------------------------------------ //
	// Private helpers
	// ------------------------------------------------------------------ //

	private async void setup_dbus() {
		try {
			dbus_impl = yield Bus.get_proxy(BusType.SESSION,
				"org.freedesktop.DBus", "/org/freedesktop/DBus");

			var names = yield dbus_impl.list_names();
			foreach (var name in names) {
				if (name.has_prefix("org.mpris.MediaPlayer2.")) {
					yield add_client(name);
				}
			}

			dbus_impl.name_owner_changed.connect(on_name_owner_changed);
		} catch (Error e) {
			warning("MprisTracker: failed to initialise dbus: %s", e.message);
		}
	}

	private void on_name_owner_changed(string name, string old_owner, string new_owner) {
		if (!name.has_prefix("org.mpris.MediaPlayer2.")) return;

		if (old_owner == "") {
			// Player appeared
			add_client.begin(name);
		} else {
			// Player vanished
			Idle.add(() => {
				remove_client(name);
				return false;
			});
		}
	}

	private async void add_client(string bus_name) {
		var client = yield mpris_new_client(bus_name);
		if (client == null) return;

		clients.insert(bus_name, client);

		// Watch for playback-status changes so we can elect the current player.
		client.prop.properties_changed.connect((iface_name, changed, _invalid) => {
			if (iface_name != "org.mpris.MediaPlayer2.Player") return;
			changed.foreach((key, _val) => {
				if (key == "PlaybackStatus") {
					on_playback_status_changed(client);
				}
			});
		});

		// Seed last_playing_time if it is already playing when we discover it.
		if (client.player.playback_status == "Playing") {
			client.last_playing_time = GLib.get_monotonic_time();
		}

		// Make it current if we have no current player, or it is already playing.
		if (current_client == null || client.player.playback_status == "Playing") {
			current_client = client;
		}

		client_added(client);
	}

	private void remove_client(string bus_name) {
		var client = clients.lookup(bus_name);
		if (client == null) return;

		clients.remove(bus_name);
		client_removed(client);

		// Elect a new current player if needed.
		if (current_client == client) {
			current_client = elect_current_player();
		}
	}

	/**
	 * Called when a client's PlaybackStatus changes.
	 * Promotes the client to current if it just started Playing.
	 */
	private void on_playback_status_changed(MprisClient client) {
		var status = client.player.playback_status;
		if (status == "Playing") {
			client.last_playing_time = GLib.get_monotonic_time();
			current_client = client;
		} else {
			// If the current player stopped/paused, check if another is still playing.
			if (current_client == client) {
				var playing = find_playing_client();
				if (playing != null) {
					current_client = playing;
				}
				// else: keep current_client as-is so controls still target it.
			}
		}
	}

	/**
	 * Find the client that is currently in Playing state and most recently
	 * became active, or null if none are playing.
	 */
	private MprisClient? find_playing_client() {
		MprisClient? best = null;
		clients.foreach((k, c) => {
			if (c.player.playback_status == "Playing") {
				if (best == null || c.last_playing_time > best.last_playing_time) {
					best = c;
				}
			}
		});
		return best;
	}

	/**
	 * Elect a current player from all remaining clients.
	 * Prefer whichever was Playing most recently; fall back to any survivor.
	 */
	private MprisClient? elect_current_player() {
		var playing = find_playing_client();
		if (playing != null) return playing;

		// Nothing is playing — pick the most recently active one.
		MprisClient? best = null;
		clients.foreach((k, c) => {
			if (best == null || c.last_playing_time > best.last_playing_time) {
				best = c;
			}
		});
		return best;
	}
}
