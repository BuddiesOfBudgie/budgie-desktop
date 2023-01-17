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

const int BACKGROUND_SIZE = 250;

/**
 * A ClientWidget is simply used to control and display information in a two-way
 * fashion with an underlying MPRIS provider (MediaPlayer2)
 * It is "designed" to be self contained and added to a large UI, enabling multiple
 * MPRIS clients to be controlled with multiple widgets
 */
public class MprisClientWidget : Gtk.Box {
	private Gtk.Box? header = null;
	private Gtk.Image? header_icon = null;
	private Gtk.Label? header_label = null;
	private Gtk.Button? header_reveal_button = null;
	private Gtk.Button? header_close_button = null;
	private Gtk.Revealer? content_revealer = null;

	Gtk.Image background;
	Gtk.EventBox background_wrap;
	MprisClient client;
	Gtk.Label title_label;
	Gtk.Label artist_label;
	Gtk.Label album_label;
	Gtk.Button prev_btn;
	Gtk.Button play_btn;
	Gtk.Button next_btn;
	string filename = "";
	Cancellable? cancel;

	int our_width = BACKGROUND_SIZE;

	/**
	 * Create a new ClientWidget
	 *
	 * @param client The underlying MprisClient instance to use
	 */
	public MprisClientWidget(MprisClient client, int width) {
		Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);

		header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
		header.get_style_context().add_class("raven-header");
		add(header);

		header_icon = new Gtk.Image.from_icon_name("emblem-music-symbolic", Gtk.IconSize.MENU);
		header_icon.margin = 4;
		header_icon.margin_start = 12;
		header_icon.margin_end = 10;
		header.add(header_icon);

		header_label = new Gtk.Label(client.player.identity);
		header.add(header_label);

		Gtk.Widget? row = null;
		cancel = new Cancellable();

		our_width = width;

		this.client = client;

		var player_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);

		background = new Gtk.Image.from_icon_name("emblem-music-symbolic", Gtk.IconSize.DIALOG);
		background.set_size_request(96, 96);
		background.pixel_size = 64;
		background.valign = Gtk.Align.START;
		background.get_style_context().add_class("raven-mpris");

		background_wrap = new Gtk.EventBox();
		background_wrap.add(background);
		background_wrap.button_release_event.connect(this.on_raise_player);

		var layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
		layout.margin_top = 12;
		layout.margin_start = 12;
		layout.margin_end = 12;
		player_box.pack_start(layout, true, true, 0);

		layout.add(background_wrap);

		/* normal info */
		var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 3);
		box.margin_start = 12;
		box.margin_end = 12;
		box.valign = Gtk.Align.CENTER;

		var controls = new Gtk.Grid();
		controls.get_style_context().add_class("raven-mpris-controls");
		controls.set_column_spacing(6);
		controls.set_column_homogeneous(true);

		row = create_row(_("Unknown Title"), "emblem-music-symbolic");
		title_label = row.get_data("label_item");
		box.pack_start(row, false, false, 0);
		row = create_row(_("Unknown Artist"), "user-info-symbolic");
		artist_label = row.get_data("label_item");
		box.pack_start(row, false, false, 0);
		row = create_row(_("Unknown Album"), "media-optical-symbolic");
		album_label = row.get_data("label_item");
		box.pack_start(row, false, false, 0);

		player_box.pack_start(controls, true, false, 6);

		var btn = new Gtk.Button.from_icon_name("media-skip-backward-symbolic", Gtk.IconSize.LARGE_TOOLBAR);
		btn.set_size_request(Gtk.IconSize.DND, Gtk.IconSize.DND);
		btn.set_sensitive(false);
		btn.set_can_focus(false);

		prev_btn = btn;
		btn.clicked.connect(() => {
			if (client.player.can_go_previous) {
				client.player.previous.begin((obj, res) => {
					try {
						try {
							client.player.previous.end(res);
						} catch (IOError e) {
							warning("Error going to the previous track %s: %s", client.player.identity, e.message);
						}
					} catch (DBusError e) {
						warning("Error going to the previous track %s: %s", client.player.identity, e.message);
					}
				});
			}
		});
		btn.get_style_context().add_class("flat");
		controls.attach(btn, 0, 0);

		btn = new Gtk.Button.from_icon_name("media-playback-start-symbolic", Gtk.IconSize.LARGE_TOOLBAR);
		play_btn = btn;
		btn.set_can_focus(false);
		btn.clicked.connect(() => {
			client.player.play_pause.begin((obj, res) => {
				try {
					try {
						client.player.play_pause.end(res);
					} catch (IOError e) {
						warning("Error toggling play state %s: %s", client.player.identity, e.message);
					}
				} catch (DBusError e) {
					warning("Error toggling the play state %s: %s", client.player.identity, e.message);
				}
			});
		});
		btn.get_style_context().add_class("flat");
		controls.attach_next_to(btn, prev_btn, Gtk.PositionType.RIGHT);

		btn = new Gtk.Button.from_icon_name("media-skip-forward-symbolic", Gtk.IconSize.LARGE_TOOLBAR);
		btn.set_sensitive(false);
		btn.set_can_focus(false);
		next_btn = btn;
		btn.clicked.connect(() => {
			if (client.player.can_go_next) {
				client.player.next.begin((obj, res) => {
					try {
						try {
							client.player.next.end(res);
						} catch (IOError e) {
							warning("Error going to the next track %s: %s", client.player.identity, e.message);
						}
					} catch (DBusError e) {
						warning("Error going to the next track %s: %s", client.player.identity, e.message);
					}
				});
			}
		});
		btn.get_style_context().add_class("flat");
		controls.attach_next_to(btn, play_btn, Gtk.PositionType.RIGHT);

		controls.set_halign(Gtk.Align.CENTER);
		controls.margin_bottom = 6;
		layout.add(box);

		update_from_meta();
		update_play_status();
		update_controls();

		client.prop.properties_changed.connect((i, p, inv) => {
			if (i == "org.mpris.MediaPlayer2.Player") {
				/* Handle mediaplayer2 iface */
				p.foreach((k, v) => {
					if (k == "Metadata") {
						update_from_meta();
					} else if (k == "PlaybackStatus") {
						update_play_status();
					} else if (k == "CanGoNext" || k == "CanGoPrevious") {
						update_controls();
					}
				});
			}
		});

		player_box.get_style_context().add_class("raven-background");

		/**
		 * Custom Player Styling
		 * We do this against the parent box itself so styling includes the header
		 */
		if ((client.player.desktop_entry != null) && (client.player.desktop_entry != "")) { // If a desktop entry is set
			get_style_context().add_class(client.player.desktop_entry); // Add our desktop entry, such as "spotify" to player_box
		} else if (client.player.identity != null) { // If no desktop entry is set, use identity
			get_style_context().add_class(client.player.identity.down()); // Lowercase identity
		}

		get_style_context().add_class("mpris-widget");

		content_revealer = new Gtk.Revealer();
		content_revealer.add(player_box);
		content_revealer.reveal_child = true;
		add(content_revealer);

		header_reveal_button = new Gtk.Button.from_icon_name("pan-down-symbolic", Gtk.IconSize.MENU);
		header_reveal_button.get_style_context().add_class("flat");
		header_reveal_button.get_style_context().add_class("expander-button");
		header_reveal_button.margin = 4;
		header_reveal_button.valign = Gtk.Align.CENTER;
		header_reveal_button.clicked.connect(() => {
			content_revealer.reveal_child = !content_revealer.child_revealed;
			var image = (Gtk.Image?) header_reveal_button.get_image();
			if (content_revealer.reveal_child) {
				image.set_from_icon_name("pan-down-symbolic", Gtk.IconSize.MENU);
			} else {
				image.set_from_icon_name("pan-end-symbolic", Gtk.IconSize.MENU);
			}
		});
		header.pack_end(header_reveal_button, false, false, 0);

		if (client.player.can_quit) {
			header_close_button = new Gtk.Button.from_icon_name("window-close-symbolic", Gtk.IconSize.MENU);
			header_close_button.get_style_context().add_class("flat");
			header_close_button.get_style_context().add_class("primary-control");
			header_close_button.valign = Gtk.Align.CENTER;
			header_close_button.clicked.connect(() => {
				if (client.player.can_quit) {
					client.player.quit.begin((obj, res) => {
						try {
							try {
								client.player.quit.end(res);
							} catch (IOError e) {
								warning("Error closing %s: %s", client.player.identity, e.message);
							}
						} catch (DBusError e) {
							warning("Error closing %s: %s", client.player.identity, e.message);
						}
					});
				}
			});
			header.pack_end(header_close_button, false, false, 0);
		}
	}

	public void update_width(int new_width) {
		this.our_width = new_width;
		// force the reload of the current art
		update_art(filename, true);
	}

	/**
	 * You raise me up ...
	 */
	private bool on_raise_player() {
		if (client == null || !client.player.can_raise) {
			return Gdk.EVENT_PROPAGATE;
		}

		client.player.raise.begin((obj, res) => {
			try {
				try {
					client.player.raise.end(res);
				} catch (IOError e) {
					warning("Error raising the client for %s: %s", client.player.identity, e.message);
				}
			} catch (DBusError e) {
				warning("Error raising the client for %s: %s", client.player.identity, e.message);
			}
		});

		return Gdk.EVENT_STOP;
	}

	/**
	 * Update play status based on player requirements
	 */
	void update_play_status() {
		switch (client.player.playback_status) {
			case "Playing":
				header_icon.set_from_icon_name("media-playback-start-symbolic", Gtk.IconSize.MENU);
				header_label.set_text(_("%s - Playing").printf(client.player.identity));
				((Gtk.Image) play_btn.get_image()).set_from_icon_name("media-playback-pause-symbolic", Gtk.IconSize.SMALL_TOOLBAR);
				break;
			case "Paused":
				header_icon.set_from_icon_name("media-playback-pause-symbolic", Gtk.IconSize.MENU);
				header_label.set_text(_("%s - Paused").printf(client.player.identity));
				((Gtk.Image) play_btn.get_image()).set_from_icon_name("media-playback-start-symbolic", Gtk.IconSize.SMALL_TOOLBAR);
				break;
			default:
				header_icon.set_from_icon_name("media-playback-stop-symbolic", Gtk.IconSize.MENU);
				header_label.set_text(client.player.identity);
				((Gtk.Image) play_btn.get_image()).set_from_icon_name("media-playback-start-symbolic", Gtk.IconSize.SMALL_TOOLBAR);
				break;
		}
	}

	/**
	 * Update prev/next sensitivity based on player requirements
	 */
	void update_controls() {
		prev_btn.set_sensitive(client.player.can_go_previous);
		next_btn.set_sensitive(client.player.can_go_next);
	}

	/**
	 * Utility, handle updating the album art
	 */
	void update_art(string uri, bool force_reload = false) {
		// Only load the same art again if a force reload was requested
		if (uri == this.filename && !force_reload) {
			return;
		}

		if (uri.has_prefix("http")) {
			// Cancel the previous fetch if necessary
			if (!this.cancel.is_cancelled()) {
				this.cancel.cancel();
			}
			this.cancel.reset();

			download_art.begin(uri);
		} else if (uri.has_prefix("file://")) {
			// local
			string fname = uri.split("file://")[1];
			try {
				var pbuf = new Gdk.Pixbuf.from_file_at_size(fname, 96, 96);
				background.set_from_pixbuf(pbuf);
				get_style_context().remove_class("no-album-art");
			} catch (Error e) {
				update_art_fallback();
			}
		} else {
			update_art_fallback();
		}

		// record the current uri
		this.filename = uri;
	}

	void update_art_fallback() {
		get_style_context().add_class("no-album-art");
		background.set_from_icon_name("emblem-music-symbolic", Gtk.IconSize.INVALID);
	}

	/**
	 * Fetch the cover art asynchronously and set it as the background image
	 */
	async void download_art(string uri) {
		// Spotify broke album artwork for open.spotify.com around time of this commit
		var proper_uri = uri.replace("https://open.spotify.com/image/", "https://i.scdn.co/image/");

		try {
			// open the stream
			var art_file = File.new_for_uri(proper_uri);
			// download the art
			var ins = yield art_file.read_async(Priority.DEFAULT, cancel);
			Gdk.Pixbuf? pbuf = yield new Gdk.Pixbuf.from_stream_at_scale_async(ins, 96, 96, true, cancel);
			background.set_from_pixbuf(pbuf);
			get_style_context().remove_class("no-album-art");
		} catch (Error e) {
			update_art_fallback();
		}
	}

	/* Work around Spotify, etc */
	string? get_meta_string(string key, string fallback) {
		if (key in client.player.metadata) {
			var label = client.player.metadata[key];
			string? lab = null;
			unowned VariantType type = label.get_type();

			/* Simple string */
			if (type.is_subtype_of(VariantType.STRING)) {
				lab = label.get_string();
			/* string[] */
			} else if (type.is_subtype_of(VariantType.STRING_ARRAY)) {
				string[] vals = label.dup_strv();
				lab = string.joinv(", ", vals);
			}
			/* Return if set */
			if (lab != null && lab != "") {
				return lab;
			}
		}
		/* Fallback to sanity */
		return fallback;
	}

	/**
	 * Update display info such as artist, the background image, etc.
	 */
	protected void update_from_meta() {
		if (client.player.metadata == null) { // Gnome MPV metadata are null when opened
			return;
		}

		if ("mpris:artUrl" in client.player.metadata) {
			var url = client.player.metadata["mpris:artUrl"].get_string();
			update_art(url);
		} else {
			update_art_fallback();
		}

		var title = get_meta_string("xesam:title", _("Unknown Title"));
		title_label.set_text(title);
		title_label.set_tooltip_text(title);

		var artist = get_meta_string("xesam:artist", _("Unknown Artist"));
		artist_label.set_markup("%s".printf(Markup.escape_text(artist)));
		artist_label.set_tooltip_text(artist);

		var album = get_meta_string("xesam:album", _("Unknown Album"));
		album_label.set_markup("%s".printf(Markup.escape_text(album)));
		album_label.set_tooltip_text(album);
	}
}

/**
 * Boring utility function, create an image/label row
 *
 * @param name Label to appear on row
 * @param icon Icon name to use, or NULL if using gicon
 * @param gicon A gicon to use, if not using icon
 *
 * @return A Gtk.Box with the boilerplate cruft out of the way
 */
public static Gtk.Widget create_row(string name, string? icon, Icon? gicon = null) {
	var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
	Gtk.Image img;

	if (icon == null && gicon != null) {
		img = new Gtk.Image.from_gicon(gicon, Gtk.IconSize.MENU);
	} else {
		img = new Gtk.Image.from_icon_name(icon, Gtk.IconSize.MENU);
	}

	img.pixel_size = 12;
	box.pack_start(img, false, false, 0);

	var label = new Gtk.Label(name) {
		valign = Gtk.Align.START,
		xalign = 0.0f,
		max_width_chars = 1,
		ellipsize = Pango.EllipsizeMode.END,
		hexpand = true,
	};

	// I don't know why, but if this is omitted then the widget explodes in size when
	// the placeholder is added
	label.set_line_wrap(true);

	box.pack_start(label, true, true, 0);

	box.set_data("label_item", label);
	box.set_data("image_item", img);

	return box;
}
