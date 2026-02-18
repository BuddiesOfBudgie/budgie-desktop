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

using Gdk;
using Gtk;
using Xfw;
using Pango;

private const int BUTTON_MAX_WIDTH = 232;
public const int BUTTON_MIN_WIDTH = 164;
private const int LABEL_MAX_WIDTH = 24;
private const int BUTTON_PADDING = 8;

private const int DEFAULT_ICON_SIZE = 32;
private const int ICON_PADDING = 18;
private const double TARGET_ICON_SCALE = 2.0 / 3.0;
private const int FORMULA_SWAP_POINT = ICON_PADDING * 3;

public class TasklistButton : ToggleButton {
	private new Label label;
	private Image icon;
	private GLib.Settings settings;
	private TasklistButtonPopover popover;

	private Allocation definite_allocation;

	public Budgie.PopoverManager popover_manager { get; construct; }
	public Xfw.Window window { get; construct; }

	public bool show_label { get; set; }
	public bool show_icon { get; set; }

	private int target_icon_size = 0;

	public TasklistButton(Xfw.Window window, Budgie.PopoverManager popover_manager, GLib.Settings settings) {
		Object(window: window, popover_manager: popover_manager);

		this.settings = settings;
		settings.changed.connect(on_settings_changed);

		on_settings_changed("show-labels");
		on_settings_changed("show-icons");

		popover = new TasklistButtonPopover(this, window);
		popover_manager.register_popover(this, popover);
	}

	construct {
		get_style_context().add_class("launcher");
		add_events(EventMask.SCROLL_MASK);

		var container = new Box(Orientation.HORIZONTAL, 0);
		add(container);

		this.icon = new Image();

		this.label = new Label(null) {
			halign = START,
			valign = CENTER,
			max_width_chars = LABEL_MAX_WIDTH,
			ellipsize = EllipsizeMode.END,
			hexpand = true,
		};

		container.pack_start(this.icon, false, false, BUTTON_PADDING);
		container.pack_start(this.label, true, true, BUTTON_PADDING);

		on_window_name_changed();
		on_window_icon_changed();

		// Only show after setting the name
		this.show_all();

		// SIGNALS
		size_allocate.connect(on_size_allocate);
		window.name_changed.connect(on_window_name_changed);
		window.icon_changed.connect(on_window_icon_changed);
	}

	public void gracefully_die() {
		if (!this.get_settings().gtk_enable_animations) {
			this.hide();
			this.destroy();
			return;
		}

		// TODO: slick animation from ButtonWrapper
		this.hide();
		this.destroy();
	}



	private void on_settings_changed(string key) {
		switch (key) {
		case "show-labels":
			show_label = settings.get_boolean(key);
			update_state_cb();
			break;
		case "show-icons":
			show_icon = settings.get_boolean(key);
			update_state_cb();
			break;
		default:
			break;
		}
	}

	private void on_size_allocate(Allocation allocation) {
		if (this.definite_allocation == allocation) {
			return;
		}

		base.size_allocate(definite_allocation);

		// Determine icon size
		int max = (int) Math.fmin(allocation.width, allocation.height);

		if (max > FORMULA_SWAP_POINT) {
			target_icon_size = max - BUTTON_PADDING;
		} else {
			target_icon_size = (int) Math.round(TARGET_ICON_SCALE * max);
		}

		var min_width = get_css_width(this);
		min_width += get_css_width(this.get_child());
		var min_image_width = target_icon_size + min_width + (2 * BUTTON_PADDING);

		if (allocation.width < min_image_width + (2 * BUTTON_PADDING) &&
		    allocation.width >= min_image_width) {
			show_label = false;
		} else {
			if (settings.get_boolean("show-labels")) {
				show_label = true;
			} else {
				show_label = false;
			}
		}

		Idle.add(update_state_cb);

		this.definite_allocation = allocation;
	}

	public override void get_preferred_width(out int minimum_width, out int natural_width) {
		var min_width = get_css_width(this);
		//  message("min_width 1: %d", min_width);
		// min_width += get_css_width(this.get_child());
		// message("min_width 2: %d", min_width);
		var char_width = get_char_width();

		minimum_width = min_width + 2 * BUTTON_PADDING;
		natural_width = min_width + 2 * BUTTON_PADDING + 2 * BUTTON_PADDING;

		if (show_label) {
			minimum_width += char_width;
			natural_width += char_width * LABEL_MAX_WIDTH;
		}

		//  message("minimum_width: %d | natural_width: %d", minimum_width, natural_width);
	}

	private bool update_state_cb() {
		icon.visible = show_icon;
		label.visible = show_label;

		on_window_icon_changed();
		queue_draw();

		return Source.REMOVE;
	}

	private void on_window_name_changed() {
		var name = window.get_name();
		label.set_label(name);
		set_tooltip_text(name);
	}

	private void on_window_icon_changed() {
		var size = target_icon_size == 0 ? DEFAULT_ICON_SIZE : target_icon_size;
		//  message("icon_size: %d", size);
		unowned var pixbuf = window.get_icon(size, 1);
		icon.set_from_pixbuf(pixbuf);
	}

	private int get_css_width(Widget widget) {
		var context = widget.get_style_context();
		var state = context.get_state();

		var margin = context.get_margin(state);
		var padding = context.get_padding(state);
		var border = context.get_border(state);

		var min_width = margin.left + margin.right;
		min_width += padding.left + padding.right;
		min_width += border.left + border.right;

		return min_width;
	}

	private int get_char_width() {
		var context = label.get_pango_context();
		var style = label.get_style_context();

		Pango.FontDescription description = (Pango.FontDescription) style.get_property(STYLE_PROPERTY_FONT, style.get_state()).get_boxed();
		var metrics = context.get_metrics(description, context.get_language());

		var width = metrics.get_approximate_char_width();

		//  message("width: %d", ((int) (width) + 512) >> 10);

		// Taken from here: https://gitlab.gnome.org/GNOME/pango/-/blob/main/pango/pango-types.h#L97
		return ((int) (width) + 512) >> 10;
	}

	public override bool scroll_event(Gdk.EventScroll event) {
		return Gdk.EVENT_PROPAGATE;
	}
}