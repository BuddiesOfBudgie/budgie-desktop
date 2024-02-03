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

namespace Workspaces {
	public const int WORKSPACE_ICON_SIZE = 16;

	public class WindowIcon : Gtk.Button {
		private libxfce4windowing.Window window;

		public WindowIcon(libxfce4windowing.Window window) {
			this.window = window;

			this.set_relief(Gtk.ReliefStyle.NONE);
			this.get_style_context().add_class("workspace-icon-button");
			this.set_tooltip_text(window.get_name());

			Gtk.Image icon = new Gtk.Image.from_gicon(window.get_gicon(), Gtk.IconSize.INVALID);
			icon.set_pixel_size(WORKSPACE_ICON_SIZE);
			this.add(icon);
			icon.show();

			window.name_changed.connect(() => {
				this.set_tooltip_text(window.get_name());
			});

			window.icon_changed.connect(() => {
				icon.set_from_gicon(window.get_gicon(), Gtk.IconSize.INVALID);
				icon.queue_draw();
			});

			Gtk.drag_source_set(
				this,
				Gdk.ModifierType.BUTTON1_MASK,
				target_list,
				Gdk.DragAction.MOVE
			);

			Gtk.drag_source_set_icon_gicon(this, window.get_gicon());

			this.drag_begin.connect(on_drag_begin);
			this.drag_end.connect(on_drag_end);
			this.drag_data_get.connect(on_drag_data_get);

			this.show_all();
		}

		public override bool button_release_event(Gdk.EventButton event) {
			if (event.button != 1) return Gdk.EVENT_STOP;

			try {
				window.activate(event.time);
			} catch (Error e) {
				warning("Failed to activate window: %s", e.message);
			}
			return Gdk.EVENT_STOP;
		}

		private void on_drag_begin(Gtk.Widget widget, Gdk.DragContext context) {
			WorkspacesApplet.dragging = true;
		}

		private void on_drag_end(Gtk.Widget widget, Gdk.DragContext context) {
			WorkspacesApplet.dragging = false;
		}

		public void on_drag_data_get(Gtk.Widget widget, Gdk.DragContext context, Gtk.SelectionData selection_data, uint target_type, uint time) {
			ulong window_xid = (ulong)window.get_id();
			uchar[] buf;
			convert_ulong_to_bytes(window_xid, out buf);
			selection_data.set(
				selection_data.get_target(),
				8,
				buf
			);
		}

		private void convert_ulong_to_bytes(ulong number, out uchar[] buffer) {
			buffer = new uchar[sizeof(ulong)];
			for (int i=0; i<sizeof(ulong); i++) {
				buffer[i] = (uchar)(number & 0xFF);
				number = number >> 8;
			}
		}
	}
}
