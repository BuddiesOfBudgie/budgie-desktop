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
	 * A Box that constrains its preferred size and children to prevent overflow
	 */
	public class ConstrainedBox : Gtk.Box {
		private bool calculating_preferred_width = false;
		private bool calculating_preferred_height = false;
		
		public ConstrainedBox(Gtk.Orientation orientation, int spacing = 0) {
			Object(orientation: orientation, spacing: spacing);
			// Ensure boxes don't expand beyond their natural size
			hexpand = false;
			vexpand = false;
		}

		public override void get_preferred_width(out int minimum_width, out int natural_width) {
			// Prevent infinite recursion - if we're already calculating, just return base values
			if (calculating_preferred_width) {
				base.get_preferred_width(out minimum_width, out natural_width);
				if (natural_width < 0) natural_width = 0;
				if (minimum_width < 0) minimum_width = 0;
				return;
			}
			
			calculating_preferred_width = true;
			base.get_preferred_width(out minimum_width, out natural_width);
			calculating_preferred_width = false;
			
			// Don't request infinite width
			if (natural_width < 0) natural_width = 0;
			if (minimum_width < 0) minimum_width = 0;
			
			// Cap to reasonable maximum (screen width) without querying parent to avoid recursion
			// Use a large but reasonable cap - actual constraint happens in size_allocate
			const int MAX_REASONABLE_WIDTH = 10000;
			if (natural_width > MAX_REASONABLE_WIDTH) {
				natural_width = MAX_REASONABLE_WIDTH;
			}
			if (minimum_width > MAX_REASONABLE_WIDTH) {
				minimum_width = MAX_REASONABLE_WIDTH;
			}
		}

		public override void get_preferred_height(out int minimum_height, out int natural_height) {
			// Prevent infinite recursion - if we're already calculating, just return base values
			if (calculating_preferred_height) {
				base.get_preferred_height(out minimum_height, out natural_height);
				if (natural_height < 0) natural_height = 0;
				if (minimum_height < 0) minimum_height = 0;
				return;
			}
			
			calculating_preferred_height = true;
			base.get_preferred_height(out minimum_height, out natural_height);
			calculating_preferred_height = false;
			
			// Don't request infinite height
			if (natural_height < 0) natural_height = 0;
			if (minimum_height < 0) minimum_height = 0;
			
			// Cap to reasonable maximum (screen height) without querying parent to avoid recursion
			// Use a large but reasonable cap - actual constraint happens in size_allocate
			const int MAX_REASONABLE_HEIGHT = 10000;
			if (natural_height > MAX_REASONABLE_HEIGHT) {
				natural_height = MAX_REASONABLE_HEIGHT;
			}
			if (minimum_height > MAX_REASONABLE_HEIGHT) {
				minimum_height = MAX_REASONABLE_HEIGHT;
			}
		}

		public override void size_allocate(Gtk.Allocation allocation) {
			var parent = get_parent();
			Gtk.Allocation constrained_alloc = allocation;
			
			if (parent != null && parent is MainPanel) {
				var main_panel = parent as MainPanel;
				Gtk.Allocation parent_alloc;
				main_panel.get_allocation(out parent_alloc);
				
				// Constrain this box's allocation to fit within parent bounds
				if (main_panel.get_orientation() == Gtk.Orientation.HORIZONTAL) {
					// For horizontal layout, constrain width
					int max_width = parent_alloc.width;
					
					// Calculate relative position within parent
					int relative_x = allocation.x - parent_alloc.x;
					
					// Ensure we don't extend beyond parent width
					if (relative_x + allocation.width > max_width) {
						constrained_alloc.width = int.max(0, max_width - relative_x);
					}
				} else {
					// For vertical layout, constrain height
					int max_height = parent_alloc.height;
					
					// Calculate relative position within parent
					int relative_y = allocation.y - parent_alloc.y;
					
					// Ensure we don't extend beyond parent height
					if (relative_y + allocation.height > max_height) {
						constrained_alloc.height = int.max(0, max_height - relative_y);
					}
				}
			}
			
			// Allocate with constrained size
			base.size_allocate(constrained_alloc);
			
			// After base allocation, ensure all children respect the constrained allocation bounds
			foreach (var child in get_children()) {
				Gtk.Allocation child_alloc;
				child.get_allocation(out child_alloc);
				
				// Make child allocation relative to this box
				int relative_x = child_alloc.x - constrained_alloc.x;
				int relative_y = child_alloc.y - constrained_alloc.y;
				
				// Constrain child allocation to box bounds
				if (get_orientation() == Gtk.Orientation.HORIZONTAL) {
					// For horizontal layout, constrain width
					if (relative_x + child_alloc.width > constrained_alloc.width) {
						child_alloc.width = int.max(0, constrained_alloc.width - relative_x);
						child.size_allocate(child_alloc);
					}
				} else {
					// For vertical layout, constrain height
					if (relative_y + child_alloc.height > constrained_alloc.height) {
						child_alloc.height = int.max(0, constrained_alloc.height - relative_y);
						child.size_allocate(child_alloc);
					}
				}
			}
		}
	}
}

