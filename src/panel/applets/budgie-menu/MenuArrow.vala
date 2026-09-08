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

/**
 * Stands in for the popover tail. Filled with the CSS color of its
 * .budgie-menu-arrow node so the theme can match it to the menu body.
 */
public class MenuArrow : Gtk.DrawingArea {
	public const int ARROW_BREADTH = 16;
	public const int ARROW_DEPTH = 8;

	public Budgie.PanelPosition position = Budgie.PanelPosition.BOTTOM;

	construct {
		this.get_style_context().add_class("budgie-menu-arrow");
	}

	private bool points_sideways() {
		return position == Budgie.PanelPosition.LEFT || position == Budgie.PanelPosition.RIGHT;
	}

	public override void get_preferred_width(out int min, out int nat) {
		min = points_sideways() ? ARROW_DEPTH : ARROW_BREADTH;
		nat = min;
	}

	public override void get_preferred_height(out int min, out int nat) {
		min = points_sideways() ? ARROW_BREADTH : ARROW_DEPTH;
		nat = min;
	}

	public override bool draw(Cairo.Context ctx) {
		int w = get_allocated_width();
		int h = get_allocated_height();
		if (w <= 0 || h <= 0) {
			return Gdk.EVENT_PROPAGATE;
		}

		Gdk.RGBA color = get_style_context().get_color(get_state_flags());
		ctx.set_source_rgba(color.red, color.green, color.blue, color.alpha);

		switch (position) {
			case Budgie.PanelPosition.TOP:
				ctx.move_to(0, h);
				ctx.line_to(w, h);
				ctx.line_to(w / 2.0, 0);
				break;
			case Budgie.PanelPosition.LEFT:
				ctx.move_to(w, 0);
				ctx.line_to(w, h);
				ctx.line_to(0, h / 2.0);
				break;
			case Budgie.PanelPosition.RIGHT:
				ctx.move_to(0, 0);
				ctx.line_to(0, h);
				ctx.line_to(w, h / 2.0);
				break;
			case Budgie.PanelPosition.BOTTOM:
			default:
				ctx.move_to(0, 0);
				ctx.line_to(w, 0);
				ctx.line_to(w / 2.0, h);
				break;
		}

		ctx.close_path();
		ctx.fill();
		return Gdk.EVENT_STOP;
	}
}
