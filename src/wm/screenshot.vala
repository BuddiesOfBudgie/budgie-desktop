/*
 * This file is part of budgie-desktop
 *
 * Copyright Budgie Desktop Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * Code has been inspired by the elementaryOS Gala ScreenshotManager.vala
 * and the GNOME 42 shell-screenshot.c techniques.
 */


namespace Budgie {
	const string EXTENSION = ".png";
	const string DBUS_SCREENSHOT = "org.buddiesofbudgie.BudgieScreenshot";
	const string DBUS_SCREENSHOT_PATH = "/org/buddiesofbudgie/Screenshot";

	[DBus (name="org.buddiesofbudgie.BudgieScreenshot")]
	public class ScreenshotManager : Object {
		static ScreenshotManager? instance;

		[DBus (visible = false)]
		public static unowned ScreenshotManager init(BudgieWM wm) {
			if (instance == null)
				instance = new ScreenshotManager(wm);

			return instance;
		}

		BudgieWM? wm = null;
		unowned Meta.Display? display = null;

		ScreenshotManager(BudgieWM _wm) {
			wm = _wm;
			display = wm.get_display();
		}

		[DBus (visible = false)]
		public void setup_dbus() {
			/* Hook up screenshot dbus */
			Bus.own_name(BusType.SESSION, DBUS_SCREENSHOT, BusNameOwnerFlags.REPLACE,
				on_bus_acquired,
				() => {},
				() => {} );
		}

		void on_bus_acquired(DBusConnection conn) {
			try {
				conn.register_object(DBUS_SCREENSHOT_PATH, this);
			} catch (Error e) {
				message("Unable to register Screenshot: %s", e.message);
			}
		}

		public void flash_area(int x, int y, int width, int height) throws DBusError, IOError {
			double[] keyframes = { 0.3f, 0.8f };
			GLib.Value[] values = { 180U, 0U };

			// do some sizing checks
			if (!(width >= 1 && height >= 1)) {
				throw new DBusError.FAILED("flash area - Invalid sizing parameters");
			}

			var transition = new Clutter.KeyframeTransition("opacity") {
				duration = 200,
				remove_on_complete = true,
				progress_mode = Clutter.AnimationMode.LINEAR
			};
			transition.set_key_frames(keyframes);
			transition.set_values(values);
			transition.set_to_value(0.0f);

			var flash_actor = new Clutter.Actor();
			flash_actor.set_size(width, height);
			flash_actor.set_position(x, y);
			flash_actor.set_background_color(Clutter.Color.get_static(Clutter.StaticColor.WHITE));
			flash_actor.set_opacity(0);
			var top_display_group = Meta.Compositor.get_top_window_group_for_display(display);
			flash_actor.transitions_completed.connect((actor) => {
				top_display_group.remove_child(actor);
				actor.destroy();
			});

			top_display_group.add_child(flash_actor);
			flash_actor.add_transition("flash", transition);
		}

		public async void screenshot(bool include_cursor, bool flash, string filename, out bool success, out string filename_used) throws DBusError, IOError {
			int width, height;
			display.get_size(out width, out height);
			yield screenshot_area(0, 0, width, height, include_cursor, flash, filename, out success, out filename_used);
		}

		public async void screenshot_area(int x, int y, int width, int height, bool include_cursor, bool flash, string filename, out bool success, out string filename_used) throws DBusError, IOError {
			var existing_unredirect = wm.enable_unredirect;
			wm.set_redirection_mode(false); // Force the disabling of unredirect for clutter capture
			yield wait_stage_repaint();

			// do some sizing checks
			if (!(width >= 1 && height >= 1)) {
				success = false;
				throw new DBusError.FAILED("screenshot_area Invalid sizing parameters");
			}

			var image = take_screenshot(x, y, width, height, include_cursor);

			if (flash) {
				flash_area(x, y, width, height);
			}

			wm.set_redirection_mode(existing_unredirect); // Restore old value

			success = yield save_image(image, filename, out filename_used);
			if (!success) {
				throw new DBusError.FAILED("Failed to save image");
			}
		}

		public async void screenshot_window(bool include_frame, bool include_cursor, bool flash, string filename, out bool success, out string filename_used) throws DBusError, IOError {
			var existing_unredirect = wm.enable_unredirect;
			wm.set_redirection_mode(false); // Force the disabling of unredirect for clutter capture
			yield wait_stage_repaint();

			var window = display.get_focus_window();

			if (window == null) {
				throw new DBusError.FAILED("Cannot find active window");
			}

			if (window.get_window_type() == Meta.WindowType.DESKTOP) {
				yield screenshot(include_cursor, flash, filename, out success, out filename_used);
				return;
			}

			var window_actor = (Meta.WindowActor) window.get_compositor_private();

			float actor_x, actor_y;
			window_actor.get_position(out actor_x, out actor_y);

			var rect = window.get_frame_rect();
			if ((include_frame && window.is_client_decorated()) ||
				(!include_frame && !window.is_client_decorated())) {
				rect = window.frame_rect_to_client_rect(rect);
			}

			// do some sizing checks
			if (!(rect.width >= 1 && rect.height >= 1)) {
				throw new DBusError.FAILED("screenshot_window Invalid sizing parameters");
			}

			Cairo.RectangleInt clip = { rect.x - (int)actor_x, rect.y - (int)actor_y, rect.width, rect.height };
			var image = (Cairo.ImageSurface) window_actor.get_image(clip);
			if (image == null) {
				throw new DBusError.FAILED("Failed to get image from the focus window");
			}

			if (include_cursor) {
				image = composite_stage_cursor(image, { rect.x, rect.y, rect.width, rect.height });
			}

			if (flash) {
				flash_area(rect.x, rect.y, rect.width, rect.height);
			}

			wm.set_redirection_mode(existing_unredirect); // Restore old value

			success = yield save_image(image, filename, out filename_used);
			if (!success) {
				throw new DBusError.FAILED("Failed to save image");
			}
		}

		private async bool save_image(Cairo.ImageSurface image, string filename, out string used_filename) {
			used_filename = filename;

			if (used_filename != "" && !Path.is_absolute(used_filename)) {
				if (!used_filename.has_suffix(EXTENSION)) {
					used_filename = used_filename.concat(EXTENSION);
				}
				Meta.Display display = wm.get_display();
				Meta.Context ctx = display.get_context();
				var scale_factor = ctx.get_backend().get_settings().get_ui_scaling_factor();
				if (scale_factor > 1) {
					var scale_pos = -EXTENSION.length;
					used_filename = used_filename.splice(scale_pos, scale_pos, "@%ix".printf(scale_factor));
				}

				var path = Environment.get_tmp_dir();
				used_filename = Path.build_filename(path, used_filename, null);
			}

			try {
				var screenshot = Gdk.pixbuf_get_from_surface(image, 0, 0, image.get_width(), image.get_height());
				if (screenshot == null) {
					throw new GLib.Error(0, 1, "Invalid surface image to get pixbuf from");
				}

				if (used_filename == "") { // save to clipboard
					var selection = display.get_selection();
					var stream = new MemoryOutputStream.resizable();
					yield screenshot.save_to_stream_async(stream, "png");
					stream.close(null);
					var source = new Meta.SelectionSourceMemory("image/png", stream.steal_as_bytes());
					selection.set_owner(Meta.SelectionType.SELECTION_CLIPBOARD, source);
				} else { // save to file
					var file = File.new_for_path(used_filename);
					FileIOStream stream;
					if (file.query_exists()) {
						stream = yield file.open_readwrite_async(FileCreateFlags.NONE);
					} else {
						stream = yield file.create_readwrite_async(FileCreateFlags.NONE);
					}
					yield screenshot.save_to_stream_async(stream.output_stream, "png");
				}

				return true;
			} catch (GLib.Error e) {
				if (e.message != null) {
					warning("could not save file: %s", e.message);
				}
				return false;
			}
		}

		Cairo.ImageSurface take_screenshot(int x, int y, int width, int height, bool include_cursor) {
			Cairo.ImageSurface image;
			int image_width, image_height;
			float scale;

			var stage = Meta.Compositor.get_stage_for_display(display) as Clutter.Stage;

			stage.get_capture_final_size({x, y, width, height}, out image_width, out image_height, out scale);

			image = new Cairo.ImageSurface(Cairo.Format.ARGB32, image_width, image_height);

			var paint_flags = Clutter.PaintFlag.CLEAR | Clutter.PaintFlag.NO_CURSORS;

			bool is_little_endian = GLib.ByteOrder.HOST == GLib.ByteOrder.LITTLE_ENDIAN;

			try {
				stage.paint_to_buffer(
					{x, y, width, height},
					scale,
					image.get_data(),
					image.get_stride(),
					(is_little_endian ? Cogl.PixelFormat.BGRA_8888_PRE : Cogl.PixelFormat.ARGB_8888_PRE),
					paint_flags
				);
			} catch (Error e) {
				message("Unable to paint_to_buffer (%s): %s", is_little_endian ? "BGRA" : "RGBA", e.message);
			}

			return include_cursor ? composite_stage_cursor(image, { x, y, width, height }) : image;
		}

		Cairo.ImageSurface composite_stage_cursor(Cairo.ImageSurface image, Cairo.RectangleInt image_rect) {
			Graphene.Point coords = {};
			int xhot, yhot;
			unowned Meta.CursorTracker cursor_tracker = display.get_cursor_tracker();
			unowned Cogl.Texture texture = cursor_tracker.get_sprite();

			if (texture == null) {
				return image;
			}

			var region = new Cairo.Region.rectangle(image_rect);
			cursor_tracker.get_pointer(out coords, null);

			if (!region.contains_point((int)coords.x, (int)coords.y)) {
				return image;
			}

			cursor_tracker.get_hot(out xhot, out yhot);

			int width = (int)texture.get_width();
			int height = (int)texture.get_height();

			uint8[] data = new uint8[width * height * 4];
			texture.get_data(Cogl.PixelFormat.RGBA_8888, 0, data);

			var cursor_image = new Cairo.ImageSurface.for_data(data, Cairo.Format.ARGB32, width, height, width * 4);
			var target = new Cairo.ImageSurface(Cairo.Format.ARGB32, image_rect.width, image_rect.height);

			var cr = new Cairo.Context(target);
			cr.set_operator(Cairo.Operator.OVER);
			image.mark_dirty();
			cr.set_source_surface(image, 0, 0);
			cr.paint();

			cr.set_operator(Cairo.Operator.OVER);
			cr.set_source_surface(cursor_image, coords.x - image_rect.x - xhot,
				coords.y - image_rect.y - yhot);
			cr.paint();

			return (Cairo.ImageSurface)cr.get_target();
		}

		async void wait_stage_repaint() {
			ulong signal_id = 0UL;
			var stage = Meta.Compositor.get_stage_for_display(display) as Clutter.Stage;
			signal_id = stage.after_paint.connect(() => {
				stage.disconnect(signal_id);
				Idle.add(wait_stage_repaint.callback);
			});

			stage.queue_redraw();
			yield;
		}
	}
}
