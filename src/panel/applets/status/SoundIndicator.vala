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

private class WpContext {
	public bool is_initialized = false;

	private static WpContext? instance;
	private Wp.Core core;
	private Wp.ObjectManager objmanager;
	private Wp.Plugin mixer_api;
	private Wp.Plugin default_nodes_api;
	private Wp.GlobalProxy proxy;

	private WpContext() {
		warning("New WpContext created");
	}

	public static unowned WpContext get_instance() {
		if (instance == null) {
			instance = new WpContext();
		}

		return instance;
	}

	public async void initialize() {
		Wp.init(Wp.InitFlags.PIPEWIRE);

		core = new Wp.Core(null, null);

		try {
			core.load_component("libwireplumber-module-default-nodes-api", "module", null);
			core.load_component("libwireplumber-module-mixer-api", "module", null);
		} catch (Error e) {
			critical("Failed to load required modules: %s", e.message);
			return;
		}

		if (!core.connect()) {
			critical("Failed to connect to the PipeWire daemon.");
			return;
		}

		Type global_proxy_type = Type.from_name("WpGlobalProxy");
		Type node_type = Type.from_name("WpNode");

		objmanager = new Wp.ObjectManager();
		objmanager.add_interest_full(new Wp.ObjectInterest.type(global_proxy_type));
		objmanager.add_interest_full(new Wp.ObjectInterest.type(node_type));
		objmanager.request_object_features(global_proxy_type, Wp.PIPEWIRE_OBJECT_FEATURES_MINIMAL);
		core.install_object_manager(objmanager);

		default_nodes_api = Wp.Plugin.find(core, "default-nodes-api");
		yield default_nodes_api.activate(Wp.PluginFeatures.ENABLED, null);
		Signal.connect(default_nodes_api, "changed", () => WpContext.get_instance().update_default_sink(), null);

		var default_sink_id = get_default_sink_id();

		var interest = new Wp.ObjectInterest.type(global_proxy_type);
		interest.add_constraint(Wp.ConstraintType.PW_GLOBAL_PROPERTY, "object.id", Wp.ConstraintVerb.EQUALS, default_sink_id);
		Object? proxy_lookup = objmanager.lookup_full(interest);
		if (proxy_lookup == null) {
			warning("Failed to get proxy to default audio sink.");
			return;
		}
		proxy = (Wp.GlobalProxy) proxy_lookup;

		mixer_api = Wp.Plugin.find(core, "mixer-api");
		mixer_api.set("scale", 1);
		yield mixer_api.activate(Wp.PluginFeatures.ENABLED, null);
		Signal.connect(mixer_api, "changed", () => WpContext.get_instance().changed(), null);

		is_initialized = true;
		initialized();
	}

	private void update_default_sink() {
		Type global_proxy_type = Type.from_name("WpGlobalProxy");
		var default_sink_id = get_default_sink_id();

		var interest = new Wp.ObjectInterest.type(global_proxy_type);
		interest.add_constraint(Wp.ConstraintType.PW_GLOBAL_PROPERTY, "object.id", Wp.ConstraintVerb.EQUALS, default_sink_id);
		Object? proxy_lookup = objmanager.lookup_full(interest);
		if (proxy_lookup == null) {
			warning("Failed to get proxy to default audio sink.");
			return;
		}
		proxy = (Wp.GlobalProxy) proxy_lookup;
		changed();
	}

	private uint32 get_default_sink_id() {
		var media_class = "Audio/Sink";

		uint32 res = 0;
		Signal.emit_by_name(default_nodes_api, "get-default-node", media_class, &res);
		warning("Default sink ID: %u", res);

		return res;
	}

	public bool get_volume(out double volume, out bool muted) {
		Variant? variant = null;
		Signal.emit_by_name(mixer_api, "get-volume", proxy.get_bound_id(), &variant);
		if (variant == null) {
			warning("Node %u does not support volume", proxy.get_bound_id());
			return false;
		}

		variant.lookup("volume", "d", &volume);
		variant.lookup("mute", "b", &muted);

		warning("Volume: %f, muted, %b", volume, muted);

		return true;
	}

	public bool set_volume(double volume, bool muted) {
		var vb = new VariantBuilder(VariantType.VARDICT);
		vb.add("{sv}", "volume", new Variant.double(volume));
		vb.add("{sv}", "mute", new Variant.boolean(muted));
		var variant = vb.end();
		Signal.emit_by_name(mixer_api, "set-volume", proxy.get_bound_id(), variant);
		return true;
	}

	public signal void initialized();
	public signal void changed();
}

public class SoundIndicator : Gtk.Bin {
	/** Current image to display */
	public Gtk.Image widget { protected set; public get; }

	/** Our mixer */
	private unowned WpContext context;

	/** EventBox for popover management */
	public Gtk.EventBox? ebox;

	/** GtkPopover in which to show a volume control */
	public Budgie.Popover popover;

	private Gtk.ButtonBox buttons;
	private Gtk.Button settings_button;
	private Gtk.Button mute_button;
	private Gtk.Button volume_down;
	private Gtk.Button volume_up;

	private Gtk.Scale volume_scale;

	private double step_size;
	private ulong changed_id;

	/** Track the scale value_changed to prevent cross-noise */
	private ulong scale_id;

	public SoundIndicator() {
		context = WpContext.get_instance();
		if (!context.is_initialized) {
			context.initialize.begin();
		}

		context.initialized.connect(update_volume);
		context.changed.connect(update_volume);

		// Start off with at least some icon until we connect to pulseaudio */
		widget = new Gtk.Image.from_icon_name("audio-volume-muted-symbolic", Gtk.IconSize.MENU);
		ebox = new Gtk.EventBox();
		ebox.add(widget);
		ebox.margin = 0;
		ebox.border_width = 0;
		add(ebox);

		/* Sort out our popover */
		this.create_sound_popover();

		this.get_style_context().add_class("sound-applet");
		this.popover.get_style_context().add_class("sound-popover");

		/* Catch scroll wheel events */
		ebox.add_events(Gdk.EventMask.SCROLL_MASK);
		ebox.add_events(Gdk.EventMask.BUTTON_RELEASE_MASK);
		//  ebox.scroll_event.connect(on_scroll_event);
		ebox.button_release_event.connect(on_button_release_event);
		show_all();
	}

	private bool on_button_release_event(Gdk.EventButton e) {
		if (e.button == Gdk.BUTTON_MIDDLE) { // Middle click
			toggle_mute_state();
		} else {
			return Gdk.EVENT_PROPAGATE;
		}

		return Gdk.EVENT_STOP;
	}

	/**
	 * Create the GtkPopover to display on primary click action, with an adjustable
	 * scale
	 */
	private void create_sound_popover() {
		popover = new Budgie.Popover(ebox);

		Gtk.Box? main_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
		main_box.border_width = 6;

		Gtk.Box? direct_volume_controls = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);

		// Construct all the controls

		volume_scale = new Gtk.Scale.with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 1);
		volume_scale.set_draw_value(false);
		volume_scale.set_can_focus(false);
		volume_scale.set_inverted(false);
		volume_scale.set_size_request(140, -1);

		settings_button = new Gtk.Button.from_icon_name("preferences-system-symbolic", Gtk.IconSize.BUTTON);
		mute_button = new Gtk.Button.from_icon_name("audio-volume-high-symbolic", Gtk.IconSize.BUTTON); // Default to high, this gets changed via update_volume
		volume_down = new Gtk.Button.from_icon_name("list-remove-symbolic", Gtk.IconSize.BUTTON);
		volume_up = new Gtk.Button.from_icon_name("list-add-symbolic", Gtk.IconSize.BUTTON);

		Gtk.Button[] b_list = { settings_button, mute_button, volume_down, volume_up };
		for (var i = 0; i < b_list.length; i++) { // Iterate on all the buttons
			Gtk.Button button = b_list[i]; // Get the button
			button.set_can_focus(false); // Don't allow focus
			button.get_style_context().add_class(Gtk.STYLE_CLASS_FLAT); // Add flat class
			button.get_style_context().add_class("image-button"); // Set as image-button
		}

		buttons = new Gtk.ButtonBox(Gtk.Orientation.HORIZONTAL); // Set as horizontal
		buttons.set_layout(Gtk.ButtonBoxStyle.EXPAND); // Expand the buttons

		// Pack all the things

		buttons.add(mute_button); // Mute button
		buttons.add(settings_button); // Settings button

		direct_volume_controls.pack_start(volume_down, false, false, 1);
		direct_volume_controls.pack_start(volume_scale, false, false, 0);
		direct_volume_controls.pack_start(volume_up, false, false, 1);

		main_box.pack_start(direct_volume_controls, false, false, 0);
		main_box.pack_start(buttons, false, false, 0);

		popover.add(main_box);

		// Set up event bindings

		scale_id = volume_scale.value_changed.connect(on_scale_changed);
		mute_button.clicked.connect(toggle_mute_state);

		settings_button.clicked.connect(open_sound_settings);

		volume_down.clicked.connect(() => {
			adjust_volume_increment(-step_size);
		});

		volume_up.clicked.connect(() => {
			adjust_volume_increment(+step_size);
		});

		// Show the things

		popover.get_child().show_all();
	}

	/**
	 * Update from scroll events. turn volume up + down.
	 */
	protected bool on_scroll_event(Gdk.EventScroll event) {
		if (!context.is_initialized) {
			return true;
		}

		double vol = 1.0;
		bool muted = false;
		context.get_volume(out vol, out muted);
		var orig_vol = vol;

		switch (event.direction) {
			case Gdk.ScrollDirection.UP:
				vol += (uint32) step_size;
				break;
			case Gdk.ScrollDirection.DOWN:
				vol -= (uint32) step_size;
				// uint. im lazy :p
				if (vol > orig_vol) {
					vol = 0;
				}
				break;
			default:
				// Go home, you're drunk.
				return false;
		}

		/* Ensure sanity + amp capability */
		var max_amp = 1.5;
		var norm = 1.0;
		if (max_amp < norm) {
			max_amp = norm;
		}

		if (vol > max_amp) {
			vol = (uint32)max_amp;
		}

		/* Prevent amplification using scroll on sound indicator */
		if (vol >= norm) {
			vol = (uint32)norm;
		}

		SignalHandler.block(volume_scale, scale_id);
		context.set_volume((double) vol, false);
		SignalHandler.unblock(volume_scale, scale_id);

		return true;
	}

	private void toggle_mute_state() {
		bool muted = false;
		double vol = 1.0;
		context.get_volume(out vol, out muted);
		context.set_volume(vol, !muted);
	}

	/**
	 * Update our icon when something changed (volume/mute)
	 */
	public void update_volume() {
		if (!context.is_initialized) {
			return;
		}

		double vol_norm = 1.0;
		double vol = 1.0;
		bool muted = false;
		context.get_volume(out vol, out muted);

		/* Same maths as computed by volume.js in gnome-shell, carried over
		 * from C->Vala port of budgie-panel */
		int n = (int) Math.floor(3*vol/vol_norm)+1;
		string image_name;

		// Work out an icon
		if (muted || vol <= 0) {
			image_name = "audio-volume-muted-symbolic";
		} else {
			switch (n) {
				case 1:
					image_name = "audio-volume-low-symbolic";
					break;
				case 2:
					image_name = "audio-volume-medium-symbolic";
					break;
				default:
					image_name = "audio-volume-high-symbolic";
					break;
			}
		}
		widget.set_from_icon_name(image_name, Gtk.IconSize.MENU);

		Gtk.Image? mute_button_image = (Gtk.Image) mute_button.get_image();

		if (mute_button_image != null) {
			mute_button_image.set_from_icon_name(image_name, Gtk.IconSize.BUTTON); // Also update our mute button
		}

		// Each scroll increments by 5%, much better than units..
		step_size = vol_norm / 20;

		// Use rounding to ensure volume is displayed exactly as 5% steps
		var pct = (vol / vol_norm)*100;
		var ipct = (uint) Math.round(pct);
		widget.set_tooltip_text(@"$ipct%");

		/* We're ignoring anything beyond our vol_norm.. */
		SignalHandler.block(volume_scale, scale_id);
		volume_scale.set_range(0, vol_norm);
		if (vol > vol_norm) {
			volume_scale.set_value(vol);
		} else {
			volume_scale.set_value(vol);
		}
		volume_scale.get_adjustment().set_page_increment(step_size);
		SignalHandler.unblock(volume_scale, scale_id);

		show_all();
		queue_draw();
	}

	/**
	 * The scale changed value - update the stream volume to match
	 */
	private void on_scale_changed() {
		if (!context.is_initialized) {
			return;
		}
		double scale_value = volume_scale.get_value();

		/* Avoid recursion ! */
		SignalHandler.block(volume_scale, scale_id);
		context.set_volume(scale_value, false);
		SignalHandler.unblock(volume_scale, scale_id);
	}

	/**
	 * Adjust the volume by a given +/- increment and bounds limit it
	 */
	private void adjust_volume_increment(double increment) {
		if (!context.is_initialized) {
			return;
		}

		double vol_norm = 1.0;
		double vol = 1.0;
		bool muted = false;
		context.get_volume(out vol, out muted);
		vol += (int32)increment;

		if (vol < 0) {
			vol = 0;
		} else if (vol > vol_norm) {
			vol = (int32) vol_norm;
		}

		SignalHandler.block(volume_scale, scale_id);
		context.set_volume((double) vol, false);
		SignalHandler.unblock(volume_scale, scale_id);
	}

	void open_sound_settings() {
		popover.hide();

		var app_info = new DesktopAppInfo("budgie-sound-panel.desktop");

		if (app_info == null) {
			return;
		}

		try {
			app_info.launch(null, null);
		} catch (Error e) {
			message("Unable to launch budgie-sound-panel.desktop: %s", e.message);
		}
	}
}
