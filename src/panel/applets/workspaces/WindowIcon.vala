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
	public const string FALLBACK_ICON_NAME = "image-missing";

	public class WindowIcon : Gtk.Button {
		public Xfw.Window window { get; construct; }

		construct {
			this.set_relief(Gtk.ReliefStyle.NONE);
			this.get_style_context().add_class("workspace-icon-button");
			this.set_tooltip_text(window.get_name());

			Gtk.Image icon;

			// When a window has just been created, its application
			// may not be set yet, so default to a generic icon if
			// there is no application. It will be set when the
			// icon_changed signal is called.
			if (this.window.application != null) {
				unowned var pixbuf = window.get_icon(WORKSPACE_ICON_SIZE, get_scale_factor());
				icon = new Gtk.Image.from_pixbuf(pixbuf);
			} else {
				icon = new Gtk.Image.from_icon_name(FALLBACK_ICON_NAME, Gtk.IconSize.INVALID);
				icon.pixel_size = WORKSPACE_ICON_SIZE;
			}

			this.add(icon);
			icon.show();

			window.name_changed.connect(() => {
				this.set_tooltip_text(window.get_name());
			});

			window.icon_changed.connect(() => {
				unowned var pixbuf = window.get_icon(WORKSPACE_ICON_SIZE, get_scale_factor());
				icon.set_from_pixbuf(pixbuf);
				icon.queue_draw();
				Gtk.drag_source_set_icon_pixbuf(this, pixbuf);
			});

			Gtk.drag_source_set(
				this,
				Gdk.ModifierType.BUTTON1_MASK,
				target_list,
				Gdk.DragAction.MOVE
			);

			this.drag_begin.connect(on_drag_begin);
			this.drag_end.connect(on_drag_end);
			this.drag_data_get.connect(on_drag_data_get);

			this.show_all();
		}

		public WindowIcon(Xfw.Window window) {
			Object(window: window);
		}

		public override bool button_release_event(Gdk.EventButton event) {
			if (event.button != 1) return Gdk.EVENT_STOP;

			try {
				window.activate(null, event.time);
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
			selection_data.set_text(string.joinv(",", window.get_class_ids()), -1);
		}
	}
}
