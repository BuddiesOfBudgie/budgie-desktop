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
	* Which way the panel is currently sliding. NONE means it is at rest,
	* either fully shown or fully hidden.
	*/
	public enum PanelAnimation {
		NONE = 0,
		SHOW,
		HIDE
	}

	/**
	* Shows and hides a panel. Hidden means the surface draws nothing and only
	* a strip along its screen edge takes pointer input; the window never unmaps
	*/
	public class PanelVisibility : GLib.Object {
		private const int PEEK_SIZE = 3; // logical px of the hidden surface, along its screen edge, that still accept pointer input
		private const uint HIDE_DELAY = 175; // ms between a state change and acting on it; a pointer leaving and returning within this never hides the panel
		private const uint SHOW_DELAY = 150; // ms the pointer has to stay on the strip before the panel reveals, so brushing the edge does nothing

		private unowned Panel panel; // the window this controller drives; it outlives us
		private unowned PanelManager manager; // owns fullscreen_active

		private bool render_panel = true; // false while hidden: draw() paints transparent and only the strip takes input
		private bool pointer_inside = false; // tracked from enter and leave events, since Wayland has no global pointer position to query
		private bool popover_visible = false; // any registered popover of this panel is mapped
		private bool screen_occluded = false; // the manager's verdict on whether a window covers the panel
		private bool allow_animation = false; // nothing animates or maps until the applets have loaded
		private bool started = false; // start() ran already
		private bool summoned = false; // brought up by summon(), kept shown until dismiss()
		private bool on_overlay = false; // the panel's surface is on the overlay layer, above fullscreen windows
		private uint visibility_update_id = 0; // pending debounced update_visibility() source, 0 when none
		private uint show_panel_id = 0; // pending delayed show_panel() source, 0 when none
		private Budgie.Animation? slide = null; // the slide currently running, if any
		private PanelAnimation animation = PanelAnimation.SHOW; // SHOW so the first update runs show_panel(), which is what maps the window
		private double render_scale = 1.0; // backing store for slide_progress

		public signal void usage_changed(); // in_use may have changed

		/**
		* Whether the user is working with the panel: one of its popovers is
		* open or the pointer is on it
		*/
		public bool in_use {
			get {
				return popover_visible || pointer_inside;
			}
		}

		/**
		* Whether the panel has slid out and only its edge strip is left
		*/
		public bool hidden {
			get {
				return !render_panel;
			}
		}

		/**
		* 0.0 fully off-screen to 1.0 fully on
		*/
		public double slide_progress {
			public set {
				render_scale = value;
				panel.queue_draw();
			}
			public get {
				return render_scale;
			}
		}

		public PanelVisibility(Panel panel, PanelManager manager, PopoverManager popover_manager) {
			this.panel = panel;
			this.manager = manager;
			panel.enter_notify_event.connect(on_enter_notify);
			panel.leave_notify_event.connect(on_leave_notify);
			panel.size_allocate.connect(on_size_allocated);
			popover_manager.visibility_changed.connect(on_popover_visibility_changed);
			manager.notify["fullscreen-active"].connect(on_fullscreen_changed);
		}

		/**
		* Starts the state machine on the next idle; its first evaluation maps
		* the window through show_panel()
		*/
		public void start() {
			if (started) {
				return;
			}
			started = true;
			Idle.add(on_start_idle);
		}

		/**
		* Lets the panel animate and runs the first visibility evaluation
		*/
		private bool on_start_idle() {
			allow_animation = true;
			update_visibility();
			return false;
		}

		/**
		* Records whether a maximized window covers the panel's monitor
		*/
		public void set_occluded(bool occluded) {
			screen_occluded = occluded;
			if (panel.autohide == AutohidePolicy.NONE) { // a Never panel never hides, so the flag is only stored for a later policy change
				return;
			}
			queue_visibility_update();
		}

		/**
		* Moves the panel to the matching layer when a fullscreen window comes
		* or goes, and lets it hide or show accordingly
		*/
		private void on_fullscreen_changed() {
			update_layer();
			queue_visibility_update();
		}

		/**
		* Re-evaluates the layer and visibility without the debounce
		*/
		public void update() {
			update_layer();
			update_visibility();
		}

		/**
		* Brings the panel up without the show delay, above a fullscreen
		* window, and keeps it shown until dismiss()
		*/
		public void summon() {
			cancel(ref visibility_update_id);
			summoned = true;
			update_layer();
			show_panel();
		}

		/**
		* Ends a summon: puts a Never panel back behind a fullscreen window and
		* lets autohide decide again
		*/
		public void dismiss() {
			if (!summoned) {
				return;
			}
			summoned = false;
			update_layer();
			queue_visibility_update();
		}

		/**
		* Puts the panel on the overlay layer while a fullscreen window is up
		* and the panel either autohides or is summoned, and on the top layer
		* otherwise
		*/
		private void update_layer() {
			bool want_overlay = manager.fullscreen_active && (panel.autohide != AutohidePolicy.NONE || summoned);
			if (want_overlay == on_overlay) {
				return;
			}
			on_overlay = want_overlay;
			if (want_overlay) {
				raise_above_fullscreen();
			} else {
				GtkLayerShell.set_layer(panel, GtkLayerShell.Layer.TOP); // on the overlay layer the surface was visible, so frame callbacks flow and a plain set_layer lands
			}
		}

		/**
		* Moves the panel to the overlay layer, which fullscreen windows do not
		* cover
		*/
		private void raise_above_fullscreen() {
			// Hiding and showing remaps the surface onto the new layer. The compositor sends no frame
			// callbacks to a surface covered by a fullscreen window, and GTK holds the commit carrying a
			// plain set_layer until one arrives. gtk-layer-shell remaps the same way on compositors that
			// can't move a mapped surface.
			bool mapped = panel.get_mapped();
			if (mapped) {
				panel.hide();
			}
			GtkLayerShell.set_layer(panel, GtkLayerShell.Layer.OVERLAY);
			if (mapped) {
				panel.show();
			}
		}

		/**
		* Decides whether the panel should be shown: never-hide policy, a
		* summon, pointer inside, an open popover, or neither a maximized nor a
		* fullscreen window covering it. Popovers are separate surfaces, so the
		* popover flag covers a pointer that moved into one.
		*/
		private bool should_be_visible() {
			return panel.autohide == AutohidePolicy.NONE || summoned || in_use || !(screen_occluded || manager.fullscreen_active);
		}

		/**
		* Restarts the HIDE_DELAY timer; the state is only acted on once the
		* inputs have been quiet for that long
		*/
		private void queue_visibility_update() {
			cancel(ref visibility_update_id);
			visibility_update_id = Timeout.add(HIDE_DELAY, update_visibility);
		}

		/**
		* Removes a pending timeout, if any, and clears its id
		*/
		private static void cancel(ref uint source_id) {
			if (source_id > 0) {
				Source.remove(source_id);
				source_id = 0;
			}
		}

		/**
		* Moves the panel toward the state should_be_visible() asks for,
		* unless it is already there or already heading there
		*/
		private bool update_visibility() {
			visibility_update_id = 0;
			if (!allow_animation) {
				return false;
			}

			bool visible = should_be_visible();
			if (visible && render_panel && animation == PanelAnimation.NONE) { // fully shown; this also absorbs the leave event the compositor sends when the input region shrinks under the pointer
				return false;
			}
			if (!visible && !render_panel) { // fully hidden
				return false;
			}

			if (visible) {
				show_panel();
			} else {
				hide_panel();
			}
			return false;
		}

		/**
		* The popover manager reports when the first popover maps and the
		* last one unmaps
		*/
		private void on_popover_visibility_changed(bool visible) {
			popover_visible = visible;
			usage_changed();
			queue_visibility_update();
		}

		/**
		* The pointer entered the surface, which while hidden means the edge
		* strip: cancel a pending hide and reveal after SHOW_DELAY
		*/
		private bool on_enter_notify(Gdk.EventCrossing event) {
			if (event.detail == Gdk.NotifyType.INFERIOR) { // a crossing between the panel's own child windows, not an entry from outside
				return Gdk.EVENT_PROPAGATE;
			}
			pointer_inside = true;
			usage_changed();
			if (panel.autohide == AutohidePolicy.NONE) {
				return Gdk.EVENT_PROPAGATE;
			}
			cancel(ref visibility_update_id);
			if (render_panel && animation == PanelAnimation.NONE) { // already fully shown, nothing to reveal
				return Gdk.EVENT_PROPAGATE;
			}
			cancel(ref show_panel_id);
			show_panel_id = Timeout.add(SHOW_DELAY, show_panel);
			return Gdk.EVENT_STOP;
		}

		/**
		* The pointer left the surface: drop a reveal that has not fired yet
		* and schedule a hide evaluation
		*/
		private bool on_leave_notify(Gdk.EventCrossing event) {
			if (event.detail == Gdk.NotifyType.INFERIOR) {
				return Gdk.EVENT_PROPAGATE;
			}
			pointer_inside = false;
			usage_changed();
			if (panel.autohide == AutohidePolicy.NONE) {
				return Gdk.EVENT_PROPAGATE;
			}
			cancel(ref show_panel_id);
			queue_visibility_update();
			return Gdk.EVENT_STOP;
		}

		/**
		* Re-applies the input region after a resize, since a dock changes
		* length as applets come and go
		*/
		private void on_size_allocated(Gtk.Allocation allocation) {
			if (render_panel && animation != PanelAnimation.HIDE) {
				set_input_region();
			} else {
				unset_input_region();
			}
		}

		/**
		* Makes the panel drawable and interactive, then slides it in. Doubles
		* as the SHOW_DELAY timeout callback, hence the bool return.
		*/
		private bool show_panel() {
			show_panel_id = 0;
			if (!allow_animation) {
				return false;
			}

			render_panel = true;
			animation = PanelAnimation.SHOW;

			set_input_region(); // full input before the slide starts, so clicks land while it is still moving in
			panel.queue_draw();
			panel.show(); // maps the window on the very first call; a no-op afterwards

			slide_to(1.0, on_show_animation_done);
			return false;
		}

		/**
		* At rest and fully shown; draw() hands rendering back to the window
		*/
		private void on_show_animation_done(Budgie.Animation? finished) {
			animation = PanelAnimation.NONE;
		}

		/**
		* Slides the panel out; the hidden state itself is only entered in
		* on_hide_animation_done so the slide stays visible
		*/
		private void hide_panel() {
			unset_input_region(); // shrink input first so clicks during the slide-out already reach the window beneath
			animation = PanelAnimation.HIDE;
			slide_to(0.0, on_hide_animation_done);
		}

		/**
		* The panel is now hidden: nothing is drawn and only the strip takes input
		*/
		private void on_hide_animation_done(Budgie.Animation? finished) {
			render_panel = false;
			animation = PanelAnimation.NONE;
			unset_input_region(); // the allocation may have changed during the slide
			panel.queue_draw();
		}

		/**
		* Animates slide_progress to target and calls on_done at the end;
		* jumps straight there when the user turned animations off
		*/
		private void slide_to(double target, Budgie.AnimCompletionFunc on_done) {
			if (slide != null) { // a slide in the opposite direction may still be running; its completion callback would undo this one
				slide.stop();
				slide = null;
			}

			if (!panel.get_settings().gtk_enable_animations) {
				slide_progress = target;
				on_done(null);
				return;
			}

			slide = new Budgie.Animation();
			slide.widget = panel; // supplies the frame clock
			slide.object = this; // owns the animated property
			slide.length = 360 * Budgie.MSECOND;
			slide.tween = Budgie.expo_ease_out;
			slide.changes = new Budgie.PropChange[] {
				Budgie.PropChange() {
					property = "slide-progress",
					old = slide_progress, // continues from wherever a stopped slide left it
					@new = target
				}
			};
			slide.start(on_done);
		}

		/**
		* The surface's full thickness, limited along the edge to the panel
		* box and its shadow
		*/
		private Cairo.RectangleInt input_area() {
			Gtk.Allocation box;
			panel.get_child().get_allocation(out box);

			var area = Cairo.RectangleInt() { // surface-local logical px, no scale factor
				x = 0, y = 0,
				width = panel.get_allocated_width(),
				height = panel.get_allocated_height()
			};
			if (panel.position == PanelPosition.LEFT || panel.position == PanelPosition.RIGHT) {
				area.y = box.y;
				area.height = box.height;
			} else {
				area.x = box.x;
				area.width = box.width;
			}
			return area;
		}

		/**
		* The panel accepts pointer input everywhere it is drawn
		*/
		private void set_input_region() {
			apply_input_region(input_area());
		}

		/**
		* Only a PEEK_SIZE strip along the screen edge accepts input; clicks
		* on the rest of the transparent surface fall through to the window
		* beneath
		*/
		private void unset_input_region() {
			var strip = input_area();

			switch (panel.position) { // the strip hugs the edge the panel is anchored to
				case PanelPosition.TOP:
					strip.height = PEEK_SIZE;
					break;
				case PanelPosition.LEFT:
					strip.width = PEEK_SIZE;
					break;
				case PanelPosition.RIGHT:
					strip.x = strip.width - PEEK_SIZE;
					strip.width = PEEK_SIZE;
					break;
				case PanelPosition.BOTTOM:
				default:
					strip.y = strip.height - PEEK_SIZE;
					strip.height = PEEK_SIZE;
					break;
			}
			apply_input_region(strip);
		}

		/**
		* GDK forwards the region to the compositor as the surface's
		* wl_surface input region
		*/
		private void apply_input_region(Cairo.RectangleInt rectangle) {
			var window = panel.get_window();
			if (window == null) { // not realized yet; show_panel() applies the full region again once it is
				return;
			}
			window.input_shape_combine_region(new Cairo.Region.rectangle(rectangle), 0, 0);
		}

		/**
		* Paints the hidden or sliding panel on the window's behalf. Returns
		* false when fully shown so the window draws itself normally.
		*/
		public bool draw(Cairo.Context context) {
			if (!render_panel) { // transparent, not unmapped: the surface has to stay alive for the strip to take input
				context.set_operator(Cairo.Operator.CLEAR);
				context.paint();
				return true;
			}
			if (animation == PanelAnimation.NONE) {
				return false;
			}

			var window = panel.get_window();
			if (window == null) {
				return true;
			}

			Gtk.Allocation allocation;
			panel.get_allocation(out allocation);
			var buffer = window.create_similar_image_surface(Cairo.Format.ARGB32,
															allocation.width,
															allocation.height,
															1);
			var buffer_context = new Cairo.Context(buffer);

			panel.propagate_draw(panel.get_child(), buffer_context); // render the child tree once into the buffer, then blit it shifted by the slide progress
			var visible_height = ((double)allocation.height) * render_scale; // how much of the panel's thickness is on screen
			var visible_width = ((double)allocation.width) * render_scale;

			switch (panel.position) { // the off-screen part is always on the anchored edge's side
				case Budgie.PanelPosition.TOP:
					context.set_source_surface(buffer, 0, visible_height - allocation.height); // slides down into view
					break;
				case Budgie.PanelPosition.LEFT:
					context.set_source_surface(buffer, visible_width - allocation.width, 0); // slides in from the left
					break;
				case Budgie.PanelPosition.RIGHT:
					context.set_source_surface(buffer, allocation.width - visible_width, 0); // slides in from the right
					break;
				case Budgie.PanelPosition.BOTTOM:
				default:
					context.set_source_surface(buffer, 0, allocation.height - visible_height); // slides up into view
					break;
			}

			context.paint();

			return true;
		}
	}
}
