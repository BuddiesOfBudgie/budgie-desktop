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
	* The main panel area - i.e. the bit that's rendered; holds the three
	* applet regions
	*/
	public class MainPanel : Gtk.Box {
		private bool updating_constraints = false; // guards update_box_constraints against re-entry from the allocations it triggers

		/**
		* Starts horizontal; PanelPlacement flips the orientation for left and
		* right panels
		*/
		public MainPanel() {
			Object(orientation: Gtk.Orientation.HORIZONTAL);
			get_style_context().add_class("budgie-panel");
			get_style_context().add_class(Gtk.STYLE_CLASS_BACKGROUND);
		}

		/**
		* The theme draws the panel background see-through while the class is set
		*/
		public void set_transparent(bool transparent) {
			if (transparent) {
				get_style_context().add_class("transparent");
			} else {
				get_style_context().remove_class("transparent");
			}
		}

		/**
		* Lets the theme style a dock differently from a full-width panel
		*/
		public void set_dock_mode(bool dock_mode) {
			if (dock_mode) {
				get_style_context().add_class("dock-mode");
			} else {
				get_style_context().remove_class("dock-mode");
			}
		}

		/**
		* Caps each of the start, center and end boxes at the space the other
		* two leave over, so one overflowing region cannot push the others off
		* the panel
		*/
		public void update_box_constraints(Gtk.Allocation allocation) {
			if (updating_constraints) { // size_allocate on a child re-enters here through that child's own allocation
				return;
			}
			updating_constraints = true;

			bool horizontal = get_orientation() == Gtk.Orientation.HORIZONTAL;
			Gtk.Widget? start_widget = null;
			Gtk.Widget? center_widget = null;
			Gtk.Widget? end_widget = null;

			foreach (var child in get_children()) { // a child's alignment along the panel's axis, set by PanelPlacement, says which region it is
				var align = horizontal ? child.get_halign() : child.get_valign();
				if (align == Gtk.Align.START) {
					start_widget = child;
				} else if (align == Gtk.Align.CENTER) {
					center_widget = child;
				} else if (align == Gtk.Align.END) {
					end_widget = child;
				}
			}

			int total = horizontal ? allocation.width : allocation.height;
			int start_length = region_length(start_widget);
			int center_length = region_length(center_widget);
			int end_length = region_length(end_widget);

			shrink_region(start_widget, total - center_length - end_length);
			start_length = region_length(start_widget); // the shrunk size is what the next two have to leave room for
			shrink_region(center_widget, total - start_length - end_length);
			center_length = region_length(center_widget);
			shrink_region(end_widget, total - start_length - center_length);

			updating_constraints = false; // allocations triggered above have run by now
		}

		/**
		* The region's extent along the panel; an absent region takes no space
		*/
		private int region_length(Gtk.Widget? region) {
			if (region == null) {
				return 0;
			}
			Gtk.Allocation alloc;
			region.get_allocation(out alloc);
			return get_orientation() == Gtk.Orientation.HORIZONTAL ? alloc.width : alloc.height;
		}

		/**
		* Re-allocates the region at max_length when it is longer; a region
		* that fits is left alone
		*/
		private void shrink_region(Gtk.Widget? region, int max_length) {
			if (region == null) {
				return;
			}
			if (max_length < 0) {
				max_length = 0;
			}

			Gtk.Allocation alloc;
			region.get_allocation(out alloc);
			if (get_orientation() == Gtk.Orientation.HORIZONTAL) {
				if (alloc.width <= max_length) {
					return;
				}
				alloc.width = max_length;
			} else {
				if (alloc.height <= max_length) {
					return;
				}
				alloc.height = max_length;
			}
			region.size_allocate(alloc);
		}
	}
}
