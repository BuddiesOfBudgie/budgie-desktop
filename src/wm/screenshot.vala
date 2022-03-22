/*
 * This file is part of budgie-desktop
 *
 * Copyright © 2022 Budgie Desktop Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * Code has been inspired by the elementaryOS Gala developers
 */


namespace Budgie {
	const string EXTENSION = ".png";

	[DBus (name="org.buddiesofbudgie.Screenshot")]
	public class Screenshot : Object {
		static Screenshot? instance;

		[DBus (visible = false)]
		public static unowned Screenshot init (BudgieWM wm) {
			if (instance == null)
				instance = new Screenshot (wm);

			return instance;
		}

		BudgieWM? wm = null;
		unowned Meta.Display? display = null;
		Settings desktop_settings;

		string prev_font_regular;
		string prev_font_document;
		string prev_font_mono;
		uint conceal_timeout;

		construct {
			desktop_settings = new Settings ("org.gnome.desktop.interface");
		}

		Screenshot (BudgieWM _wm) {
			wm = _wm;
			display = wm.get_display();
		}

		public void flash_area (int x, int y, int width, int height) throws DBusError, IOError {
			double[] keyframes = { 0.3f, 0.8f };
			GLib.Value[] values = { 180U, 0U };

			var transition = new Clutter.KeyframeTransition ("opacity") {
				duration = 200,
				remove_on_complete = true,
				progress_mode = Clutter.AnimationMode.LINEAR
			};
			transition.set_key_frames (keyframes);
			transition.set_values (values);
			transition.set_to_value (0.0f);

			var flash_actor = new Clutter.Actor ();
			flash_actor.set_size (width, height);
			flash_actor.set_position (x, y);
			flash_actor.set_background_color (Clutter.Color.get_static (Clutter.StaticColor.WHITE));
			flash_actor.set_opacity (0);
			var top_display_group = Meta.Compositor.get_top_window_group_for_display(display);
			flash_actor.transitions_completed.connect ((actor) => {
				top_display_group.remove_child (actor);
				actor.destroy ();
			});

			top_display_group.add_child (flash_actor);
			flash_actor.add_transition ("flash", transition);
		}

		public async void screenshot (bool include_cursor, bool flash, string filename, out bool success, out string filename_used) throws DBusError, IOError {
			int width, height;
			display.get_size (out width, out height);

			var image = take_screenshot (0, 0, width, height, include_cursor);
			unconceal_text ();

			if (flash) {
				flash_area (0, 0, width, height);
			}

			success = yield save_image (image, filename, out filename_used);
		}

		public async void screenshot_area (int x, int y, int width, int height, bool include_cursor, bool flash, string filename, out bool success, out string filename_used) throws DBusError, IOError {
			yield wait_stage_repaint ();

			var image = take_screenshot (x, y, width, height, include_cursor);
			unconceal_text ();

			if (flash) {
				flash_area (x, y, width, height);
			}

			success = yield save_image (image, filename, out filename_used);
			if (!success)
				throw new DBusError.FAILED ("Failed to save image");
		}

		public async void screenshot_window (bool include_frame, bool include_cursor, bool flash, string filename, out bool success, out string filename_used) throws DBusError, IOError {
			var window = display.get_focus_window ();

			if (window == null) {
				unconceal_text ();
				throw new DBusError.FAILED ("Cannot find active window");
			}

			var window_actor = (Meta.WindowActor) window.get_compositor_private ();
			unowned Meta.ShapedTexture window_texture = (Meta.ShapedTexture) window_actor.get_texture ();

			float actor_x, actor_y;
			window_actor.get_position (out actor_x, out actor_y);

			var rect = window.get_frame_rect ();
			if ((include_frame && window.is_client_decorated ()) ||
                (!include_frame && !window.is_client_decorated ())) {
                rect = window.frame_rect_to_client_rect (rect);
            }


			Cairo.RectangleInt clip = { rect.x - (int) actor_x, rect.y - (int) actor_y, rect.width, rect.height };
			print("rect.x %d \n", rect.x);
			print("actor_x %d \n", (int) actor_x);
			print("rect.y %d \n", rect.y);
			print("actor_y %d \n", (int) actor_y);
			print("rect.width %d \n", rect.width);
			print("rect.height %d \n", rect.height);
			//var image = (Cairo.ImageSurface) window_texture.get_image (clip);
			//if (include_cursor) {
			//	image = composite_stage_cursor (image, { rect.x, rect.y, rect.width, rect.height });
			//}

			var image = take_screenshot ((int)actor_x, (int) actor_y, rect.width, rect.height, include_cursor);

			unconceal_text ();

			if (flash) {
				flash_area (rect.x, rect.y, rect.width, rect.height);
			}

			success = yield save_image (image, filename, out filename_used);
			if (!success)
				throw new DBusError.FAILED ("Failed to save image");
		}

		private void unconceal_text () {
			if (conceal_timeout == 0) {
				return;
			}

			desktop_settings.set_string ("font-name", prev_font_regular);
			desktop_settings.set_string ("monospace-font-name", prev_font_mono);
			desktop_settings.set_string ("document-font-name", prev_font_document);

			Source.remove (conceal_timeout);
			conceal_timeout = 0;
		}

		public async void conceal_text () throws DBusError, IOError {
			if (conceal_timeout > 0) {
				Source.remove (conceal_timeout);
			} else {
				prev_font_regular = desktop_settings.get_string ("font-name");
				prev_font_mono = desktop_settings.get_string ("monospace-font-name");
				prev_font_document = desktop_settings.get_string ("document-font-name");

				desktop_settings.set_string ("font-name", "Redacted Script Regular 9");
				desktop_settings.set_string ("monospace-font-name", "Redacted Script Light 10");
				desktop_settings.set_string ("document-font-name", "Redacted Script Regular 10");
			}

			conceal_timeout = Timeout.add (2000, () => {
				unconceal_text ();
				return Source.REMOVE;
			});
		}

		static string find_target_path () {
			/*
			 * If path in gnome-screenshots exists/or can be created then use this path
			 * otherwise use the PICTURES xdg-dir path
			 * default is the home folder as the ultimate fallback
			 */
			unowned string? base_path = Environment.get_user_special_dir (UserDirectory.PICTURES);
			if (base_path != null && FileUtils.test (base_path, FileTest.EXISTS)) {
				var path = "";
				var settings_schema = "org.gnome.gnome-screenshot";
				var schema = GLib.SettingsSchemaSource.get_default ().lookup (settings_schema, true);
				if (schema != null) { // settings schema does exist
					var settings = new Settings(settings_schema);
					path = settings.get_string("auto-save-directory");
				}
				if (FileUtils.test (path, FileTest.EXISTS)) {
					return path;
				} else if (DirUtils.create (path, 0755) == 0) {
					return path;
				} else {
					return base_path;
				}
			}

			return Environment.get_home_dir ();
		}

		private async bool save_image (Cairo.ImageSurface image, string filename, out string used_filename) {
			used_filename = filename;

			if (used_filename != "" && !Path.is_absolute (used_filename)) {
				if (!used_filename.has_suffix (EXTENSION)) {
					used_filename = used_filename.concat (EXTENSION);
				}

				var scale_factor = Meta.Backend.get_backend ().get_settings ().get_ui_scaling_factor ();
				if (scale_factor > 1) {
					var scale_pos = -EXTENSION.length;
					used_filename = used_filename.splice (scale_pos, scale_pos, "@%ix".printf (scale_factor));
				}

				var path = find_target_path ();
				used_filename = Path.build_filename (path, used_filename, null);
			}

			try {
				var screenshot = Gdk.pixbuf_get_from_surface (image, 0, 0, image.get_width (), image.get_height ());
				if (screenshot == null) {
					throw new GLib.Error(0, 1, "Invalid surface image to get pixbuf from");
				}

				if (used_filename == "") { // save to clipboard
					var selection = display.get_selection();
					var stream = new MemoryOutputStream.resizable();
					yield screenshot.save_to_stream_async (stream, "png");
					stream.close(null);
					var source = new Meta.SelectionSourceMemory("image/png", stream.steal_as_bytes());
					selection.set_owner(Meta.SelectionType.SELECTION_CLIPBOARD, source);
				}
				else { // save to file
					var file = File.new_for_path (used_filename);
					FileIOStream stream;
					if (file.query_exists ()) {
						stream = yield file.open_readwrite_async (FileCreateFlags.NONE);
					} else {
						stream = yield file.create_readwrite_async (FileCreateFlags.NONE);
					}
					yield screenshot.save_to_stream_async (stream.output_stream, "png");
				}

				return true;
			} catch (GLib.Error e) {
				if (e.message != null) {
					warning ("could not save file: %s", e.message);
				}
				return false;
			}
		}

		Cairo.ImageSurface take_screenshot (int x, int y, int width, int height, bool include_cursor) {
			Cairo.ImageSurface image;
			int image_width, image_height;
			float scale;

			var stage = Meta.Compositor.get_stage_for_display(display) as Clutter.Stage;
			stage.get_capture_final_size ({x, y, width, height}, out image_width, out image_height, out scale);

			image = new Cairo.ImageSurface (Cairo.Format.ARGB32, image_width, image_height);

			var paint_flags = Clutter.PaintFlag.NO_CURSORS;
			if (include_cursor) {
				paint_flags |= Clutter.PaintFlag.FORCE_CURSORS;
			}

			if (GLib.ByteOrder.HOST == GLib.ByteOrder.LITTLE_ENDIAN) {
				try {
					stage.paint_to_buffer (
						{x, y, width, height},
						scale,
						image.get_data(),
						image.get_stride (),
						Cogl.PixelFormat.BGRA_8888_PRE,
						paint_flags
					);
				} catch (GLib.Error e) {
					warning("Cannot stage paint_to_buffer: %s", e.message);
				}

			} else {
				try {
					stage.paint_to_buffer (
						{x, y, width, height},
						scale,
						image.get_data(),
						image.get_stride (),
						Cogl.PixelFormat.ARGB_8888_PRE,
						paint_flags
					);
				} catch (GLib.Error e) {
					warning("Cannot stage paint_to_buffer(non endian): %s", e.message);
				}

			}
			return image;
		}

		Cairo.ImageSurface composite_capture_images (Clutter.Capture[] captures, int x, int y, int width, int height) {
			var image = new Cairo.ImageSurface (captures[0].image.get_format (), width, height);
			var cr = new Cairo.Context (image);

			foreach (unowned Clutter.Capture capture in captures) {
				// Ignore capture regions with scale other than 1 for now; mutter can't
				// produce them yet, so there is no way to test them.
				double capture_scale = 1.0;
				capture.image.get_device_scale (out capture_scale, null);
				if (capture_scale != 1.0)
					continue;

				cr.save ();
				cr.translate (capture.rect.x - x, capture.rect.y - y);
				cr.set_source_surface (capture.image, 0, 0);
				cr.restore ();
			}

			return image;
		}

		Cairo.ImageSurface composite_stage_cursor (Cairo.ImageSurface image, Cairo.RectangleInt image_rect) {
			unowned Meta.CursorTracker cursor_tracker = display.get_cursor_tracker();
			Graphene.Point coords = {};

			cursor_tracker.get_pointer (coords, null);

			var region = new Cairo.Region.rectangle (image_rect);
			if (!region.contains_point ((int) coords.x, (int) coords.y)) {
				return image;
			}

			unowned Cogl.Texture texture = cursor_tracker.get_sprite ();
			if (texture == null) {
				return image;
			}

			int width = (int)texture.get_width ();
			int height = (int)texture.get_height ();

			uint8[] data = new uint8[width * height * 4];
			texture.get_data (Cogl.PixelFormat.RGBA_8888, 0, data);

			var cursor_image = new Cairo.ImageSurface.for_data (data, Cairo.Format.ARGB32, width, height, width * 4);
			var target = new Cairo.ImageSurface (Cairo.Format.ARGB32, image_rect.width, image_rect.height);

			var cr = new Cairo.Context (target);
			cr.set_operator (Cairo.Operator.OVER);
			cr.set_source_surface (image, 0, 0);
			cr.paint ();

			cr.set_operator (Cairo.Operator.OVER);
			cr.set_source_surface (cursor_image, coords.x - image_rect.x, coords.y - image_rect.y);
			cr.paint ();

			return (Cairo.ImageSurface)cr.get_target ();
		}

		async void wait_stage_repaint () {
			ulong signal_id = 0UL;
			var stage = Meta.Compositor.get_stage_for_display(display) as Clutter.Stage;
			signal_id = stage.after_paint.connect (() => {
				stage.disconnect (signal_id);
				Idle.add (wait_stage_repaint.callback);
			});

			stage.queue_redraw ();
			yield;
		}
	}
}
