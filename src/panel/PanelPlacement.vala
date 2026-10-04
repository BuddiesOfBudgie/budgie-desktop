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
	* Anchors a panel window to its screen edge, reserves its space, and
	* orients the boxes inside it for that edge
	*/
	public class PanelPlacement : GLib.Object {
		private unowned Panel panel; // the window being placed; it outlives us
		private unowned Gtk.Box main_layout; // the window's only child: holds the panel box and the shadow
		private unowned MainPanel layout; // the panel box carrying the regions
		private unowned Budgie.ShadowBlock shadow; // drop shadow drawn on the panel's screen-facing side
		private unowned ConstrainedBox start_box; // region at the start of the edge
		private unowned ConstrainedBox center_box; // region in the middle of the edge
		private unowned ConstrainedBox end_box; // region at the end of the edge

		private Gdk.Rectangle screen; // the monitor's logical geometry in monitor-local coordinates; layer-shell positions the window, this only sizes it
		private int target_monitor = 0; // index into the display's monitor list

		/**
		* Takes the already-built widget tree; apply() is left to the caller
		* once the window is ready
		*/
		public PanelPlacement(Panel panel, Gtk.Box main_layout, MainPanel layout, Budgie.ShadowBlock shadow,
							  ConstrainedBox start_box, ConstrainedBox center_box, ConstrainedBox end_box) {
			this.panel = panel;
			this.main_layout = main_layout;
			this.layout = layout;
			this.shadow = shadow;
			this.start_box = start_box;
			this.center_box = center_box;
			this.end_box = end_box;

			layout.size_allocate.connect(on_layout_allocated);
		}

		/**
		* Records where the panel lives; the manager calls this on creation and
		* whenever monitors change, then apply() takes it into account
		*/
		public void set_screen(Gdk.Rectangle screen, int monitor_index) {
			this.screen = screen;
			if (monitor_index >= 0) { // callers that only re-place the panel on its edge leave the monitor alone
				target_monitor = monitor_index;
			}
		}

		/**
		* Returns whether the panel runs horizontally (top, bottom, or unplaced)
		*/
		public bool is_horizontal() {
			return (panel.position != Budgie.PanelPosition.LEFT && panel.position != Budgie.PanelPosition.RIGHT);
		}

		/**
		* The window's size: its full thickness (panel plus shadow) on the
		* axis it is thin on, the screen's extent on the other
		*/
		public void get_target_extents(out int width, out int height) {
			if (is_horizontal()) {
				width = screen.width;
				height = int.min(panel.targeted_size, screen.height);
			} else {
				width = int.min(panel.targeted_size, screen.width);
				height = screen.height;
			}
		}

		/**
		* Re-anchors the window and re-aligns its contents. Runs on every
		* position, dock mode, size or scale change and on map.
		*/
		public void apply() {
			update_layer_shell_props();

			bool horizontal = is_horizontal();
			main_layout.child_set(shadow, "position", (panel.position == Budgie.PanelPosition.TOP || panel.position == Budgie.PanelPosition.LEFT) ? 1 : 0); // the shadow is packed on the side that faces the screen center
			orient_contents(horizontal);
			request_size(horizontal);
		}

		/**
		* Sets the orientation and alignment of the region boxes, the panel
		* box and the main layout to match the panel's edge and dock mode
		*/
		private void orient_contents(bool horizontal) {
			var panel_orientation = horizontal ? Gtk.Orientation.HORIZONTAL : Gtk.Orientation.VERTICAL; // the regions and the panel box run along the edge
			var stack_orientation = horizontal ? Gtk.Orientation.VERTICAL : Gtk.Orientation.HORIZONTAL; // the panel box and the shadow stack through the thickness

			align_region(start_box, Gtk.Align.START, horizontal);
			align_region(center_box, Gtk.Align.CENTER, horizontal);
			align_region(end_box, Gtk.Align.END, horizontal);
			start_box.set_orientation(panel_orientation);
			center_box.set_orientation(panel_orientation);
			end_box.set_orientation(panel_orientation);
			layout.set_orientation(panel_orientation);

			var dock_align = panel.dock_mode ? Gtk.Align.CENTER : Gtk.Align.FILL; // a dock is centered inside its full-length surface
			main_layout.set_orientation(stack_orientation);
			main_layout.halign = horizontal ? dock_align : Gtk.Align.FILL;
			main_layout.valign = horizontal ? Gtk.Align.FILL : dock_align;
			main_layout.hexpand = !horizontal;
		}

		/**
		* Aligns one region box for the panel's axis: placed along the edge,
		* filling across it
		*/
		private static void align_region(Gtk.Widget region, Gtk.Align place, bool horizontal) {
			region.halign = horizontal ? place : Gtk.Align.FILL;
			region.valign = horizontal ? Gtk.Align.FILL : place;
		}

		/**
		* Requests the window's and the panel box's sizes for the current edge,
		* capping a dock's length to what its applets need
		*/
		private void request_size(bool horizontal) {
			int width, height;
			get_target_extents(out width, out height);

			if (panel.dock_mode) {
				// A dock is only as long as its applets: cap it at the screen if they
				// overflow, otherwise request a small size and let them set the length
				Gtk.Allocation alloc;
				main_layout.get_allocation(out alloc);
				if (horizontal) {
					width = (alloc.width > screen.width) ? screen.width : 100;
				} else {
					height = (alloc.height > screen.height) ? screen.height : 100;
				}
			}

			layout.set_size_request( // the panel box is intended_size thick; the window adds the shadow on top of that
				horizontal ? width : panel.intended_size,
				horizontal ? panel.intended_size : height
			);
			panel.set_size_request(width, height);
		}

		/**
		* Moves the surface to its monitor and anchors it to the configured
		* edge; margins and exclusive zone follow
		*/
		public void update_layer_shell_props() {
			var default_display = Gdk.Display.get_default();
			if (default_display != null && default_display.get_n_monitors() > target_monitor) {
				var monitor = default_display.get_monitor(target_monitor);
				if (monitor != null) {
					debug("Setting panel to monitor index %d", target_monitor);
					GtkLayerShell.set_monitor(panel, monitor);
				}
			}

			GtkLayerShell.Edge position_edge = position_to_layer_shell_edge(panel.position);

			GtkLayerShell.set_anchor(panel, GtkLayerShell.Edge.TOP, false); // anchoring opposite edges stretches the surface across the screen, so clear the old edge first
			GtkLayerShell.set_anchor(panel, GtkLayerShell.Edge.BOTTOM, false);
			GtkLayerShell.set_anchor(panel, GtkLayerShell.Edge.LEFT, false);
			GtkLayerShell.set_anchor(panel, GtkLayerShell.Edge.RIGHT, false);
			GtkLayerShell.set_anchor(panel, position_edge, true);
			GtkLayerShell.set_margin(panel, position_edge, -1);

			update_exclusive_zone();
		}

		/**
		* Maps a Budgie edge to the layer-shell anchor; NONE counts as BOTTOM,
		* the same fallback the manager uses for an unplaced panel
		*/
		private static GtkLayerShell.Edge position_to_layer_shell_edge(Budgie.PanelPosition position) {
			switch (position) {
				case PanelPosition.TOP:
					return GtkLayerShell.Edge.TOP;
				case PanelPosition.LEFT:
					return GtkLayerShell.Edge.LEFT;
				case PanelPosition.RIGHT:
					return GtkLayerShell.Edge.RIGHT;
				case PanelPosition.BOTTOM:
				case PanelPosition.NONE:
					return GtkLayerShell.Edge.BOTTOM;
			}
			return GtkLayerShell.Edge.BOTTOM;
		}

		/**
		* Tells the compositor how much of the edge to keep maximized and tiled
		* windows out of
		*/
		public void update_exclusive_zone() {
			if (panel.dock_mode || panel.autohide != AutohidePolicy.NONE) { // a dock would reserve its whole edge; an autohide panel is meant to be covered
				GtkLayerShell.set_exclusive_zone(panel, 0);
			} else {
				GtkLayerShell.set_exclusive_zone(panel, panel.reserved_size);
			}
		}

		/**
		* The panel box just got a new allocation; if its thickness changed,
		* the reserved space has to follow
		*/
		private void on_layout_allocated(Gtk.Allocation allocation) {
			if (panel.position == PanelPosition.NONE) { // not placed yet, nothing to reserve
				return;
			}

			int allocated_size = is_horizontal() ? allocation.height : allocation.width; // what the panel box was given, not requested; the shadow is outside it
			if (allocated_size == panel.reserved_size) {
				return;
			}

			panel.reserved_size = allocated_size;
			update_exclusive_zone();
		}
	}
}
