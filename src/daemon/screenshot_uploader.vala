using Soup;
using Json;

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

namespace BudgieScr {

	public enum Providers {
		IMGUR = 1,
		NULLPOINTER = 2, // 0x0
		TMPFILES = 3,
		TEMPFILES = 4,
	}

	public class Uploader : GLib.Object {

		public const string imgur_str = "imgur.com";
		public const string nullpointer_str = "0x0.st";
		public const string tmpfiles_str = "tmpfiles.org";
		public const string tempfiles_str = "tempfiles.ninja";

		private Soup.Session session;
		private Soup.Logger logger;
		private Json.Parser parser;

		public Uploader() {
			session = new Soup.Session();
			if (GLib.Log.get_debug_enabled() == true) {
				logger = new Soup.Logger(Soup.LoggerLogLevel.HEADERS);
				session.add_feature(logger);
			}
			parser = new Json.Parser();
		}

		public const BudgieScr.Providers[] provider = {
			BudgieScr.Providers.IMGUR,
			BudgieScr.Providers.NULLPOINTER, // 0x0
			BudgieScr.Providers.TMPFILES,
			BudgieScr.Providers.TEMPFILES,
		};

		public string provider_string_to_display(BudgieScr.Providers provider) {
			switch (provider) {
				case Providers.IMGUR:
					return _(imgur_str);
				case Providers.NULLPOINTER:
					return _(nullpointer_str);
				case Providers.TMPFILES:
					return _(tmpfiles_str);
				case Providers.TEMPFILES:
					return _(tempfiles_str);
				default:
					return _(nullpointer_str);
			}
		}

		// Choose uploader from provided string, return status and link
		public bool upload_to_provider(string chosenprovider, string path, out string? link) {
			bool status = false;
			link = null;
			switch (chosenprovider) {
				case imgur_str:
					status = upload_image_imgur(path, out link);
					break;
				case nullpointer_str:
					status = upload_image_nullpointer(path, out link);
					break;
				case tmpfiles_str:
					status = upload_image_tmpfiles(path, out link);
					break;
				case tempfiles_str:
					status = upload_image_tempfilesninja(path, out link);
					break;
				default:
					status = upload_image_nullpointer(path, out link);
					break;
			}
			return status;
		}

		// Upload image to https://imgur.com/ web service
		private bool upload_image_imgur(string path, out string? link) {
			link = null;

			// TODO: Provide your own via meson options
			string imgur_clientid = "";
			string imgur_apikey = "";

			// Read file into memory
			uint8[] data;
			try {
				GLib.FileUtils.get_data(path, out data);
			} catch (GLib.FileError e) {
				warning(e.message);
				return false;
			}

			// Encode to base64
			string image = GLib.Base64.encode(data);

			// Setup POST request
			Soup.Message message = new Soup.Message("POST", "https://api.imgur.com/3/upload.json");
			message.request_headers.append("Authorization", "Client-ID " + imgur_clientid);
			string req = "api_key=" + imgur_apikey + "&image=" + GLib.Uri.escape_string(image);

			// Encode to Bytes and set message body
			var finalreq = new GLib.Bytes(req.data);
			message.set_request_body_from_bytes(Soup.FORM_MIME_TYPE_URLENCODED, finalreq);

			// Async send message & get Bytes from response
			GLib.Bytes? payloadbytes = null;
			var loop = new MainLoop();
			session.send_and_read_async.begin(message, 0, null, (obj,res) => {
				try {
					payloadbytes = session.send_and_read_async.end(res);
				} catch (Error e) {
					stderr.printf(e.message);
				}
				loop.quit();
			});
			loop.run();

			// Encode back to string for json parsing
			string payload = (string)payloadbytes.get_data();
			if (payload == null) {
				return false;
			}

			debug("%s payload: %s\n", imgur_str, payload);

			// parse the json payload response
			try {
				int64 len = payload.length;
				parser.load_from_data(payload, (ssize_t)len);
			} catch (GLib.Error e) {
				stderr.printf(e.message);
			}

			// Ensure we got a valid response
			unowned Json.Object node_obj = parser.get_root().get_object();
			if (node_obj == null) {
				return false;
			}
			node_obj = node_obj.get_object_member("data");
			if (node_obj == null) {
				return false;
			}

			// Finally, get the link.
			string? url = node_obj.get_string_member("link") ?? null;
			if (url == null) {
				warning("ERROR: %s\n", node_obj.get_string_member("error"));
				return false;
			}

			link = url;
			debug("%s: link from response: %s\n", imgur_str, link);

			return true;
		}

		// Upload image to https://0x0.st/ web service
		private bool upload_image_nullpointer(string path, out string? link) {
			link = null;

			// Read file into memory
			uint8[] data;
			try {
				GLib.FileUtils.get_data(path, out data);
			} catch (GLib.FileError e) {
				warning(e.message);
				return false;
			}

			// Encode to Bytes
			var imagebytes = new GLib.Bytes.take(data);

			// Setup our multipart message
			string mime_type = "application/octet-stream";
			Soup.Multipart multipart = new Soup.Multipart(mime_type);
			multipart.append_form_file("file", path, mime_type, imagebytes);
			Soup.Message message = new Soup.Message.from_multipart("https://0x0.st/", multipart);

			// Set and get content type
			GLib.HashTable<string, string> content_type_params;
			message.request_headers.get_content_type(out content_type_params);
			message.request_headers.set_content_type(Soup.FORM_MIME_TYPE_MULTIPART, content_type_params);

			// Async send message & get Bytes from response
			Bytes? payloadbytes = null;
			var loop = new MainLoop();
			session.send_and_read_async.begin(message, 0, null, (obj,res) => {
				try {
					payloadbytes = session.send_and_read_async.end(res);
				} catch (Error e) {
					stderr.printf(e.message);
				}
				loop.quit();
			});
			loop.run();

			// Encode back to string for parsing
			string payload = (string)payloadbytes.get_data();
			if (payload == null) {
				return false;
			}

			debug("%s payload: %s\n", nullpointer_str, payload);

			// Get link from reponse
			if (!payload.has_prefix("http")) {
				return false;
			}
			link = payload.strip();

			debug("%s: link from response %s\n", nullpointer_str, link);

			return true;
		}

		// Upload to https://tmpfiles.org
		private bool upload_image_tmpfiles(string path, out string? link) {
			link = null;

			// Read file into memory
			uint8[] data;
			try {
				GLib.FileUtils.get_data(path, out data);
			} catch (GLib.FileError e) {
				warning(e.message);
				return false;
			}
			var databytes = new GLib.Bytes(data);

			// Create a randomized filename
			string uploaded_filename = "%d.jpeg".printf(Random.int_range(1000, 10000));

			// Setup multipart form request
			string mime_type = "application/octet-stream";
			Soup.Multipart multipart = new Soup.Multipart(mime_type);
			multipart.append_form_file("file", uploaded_filename, mime_type, databytes);
			Soup.Message message = new Soup.Message.from_multipart("https://tmpfiles.org/api/v1/upload", multipart);

			// Set and get content type
			GLib.HashTable<string, string> content_type_params;
			message.request_headers.get_content_type(out content_type_params);
			message.request_headers.set_content_type(Soup.FORM_MIME_TYPE_MULTIPART, content_type_params);

			// Async send message & get Bytes from response
			GLib.Bytes? payloadbytes = null;
			var loop = new MainLoop();
			session.send_and_read_async.begin(message, 0, null, (obj,res) => {
				try {
					payloadbytes = session.send_and_read_async.end(res);
				} catch (Error e) {
					stderr.printf(e.message);
				}
				loop.quit();
			});
			loop.run();

			// Encode back to string for parsing
			string payload = (string)payloadbytes.get_data();
			if (payload == null) {
				return false;
			}

			debug("%s payload: %s\n", tmpfiles_str, payload);

			// parse the json payload response
			try {
				int64 len = payload.length;
				parser.load_from_data(payload, (ssize_t)len);
			} catch (GLib.Error e) {
				stderr.printf(e.message);
			}

			// Ensure we got a valid response
			unowned Json.Object node_obj = parser.get_root().get_object();
			if (node_obj == null) {
				return false;
			}
			node_obj = node_obj.get_object_member("data");
			if (node_obj == null) {
				return false;
			}

			// Finally, get the link.
			string? url = node_obj.get_string_member("url") ?? null;
			if (url == null) {
				warning("ERROR: %s\n", node_obj.get_string_member("error"));
				return false;
			}

			link = url;
			debug("%s: link from response: %s\n", tmpfiles_str, link);

			return true;
		}

		// Upload to https://tempfiles.ninja
		private bool upload_image_tempfilesninja(string path, out string? link) {
			link = null;

			// Read file into memory
			uint8[] data;
			try {
				GLib.FileUtils.get_data(path, out data);
			} catch (GLib.FileError e) {
				warning(e.message);
				return false;
			}
			var databytes = new GLib.Bytes(data);

			// Setup POST request
			Soup.Message message = new Soup.Message("POST", "https://tempfiles.ninja/api/upload?filename=" + path);
			message.set_request_body_from_bytes("image/jpeg", databytes);

			// Async send message & get Bytes from response
			GLib.Bytes? payloadbytes = null;
			var loop = new MainLoop();
			session.send_and_read_async.begin(message, 0, null, (obj,res) => {
				try {
					payloadbytes = session.send_and_read_async.end(res);
				} catch (Error e) {
					stderr.printf(e.message);
				}
				loop.quit();
			});
			loop.run();

			// Encode back to string for parsing
			string payload = (string)payloadbytes.get_data();
			if (payload == null) {
				return false;
			}

			debug("%s payload: %s\n", tempfiles_str, payload);

			// parse the json payload response
			try {
				int64 len = payload.length;
				parser.load_from_data(payload, (ssize_t)len);
			} catch (GLib.Error e) {
				stderr.printf(e.message);
			}

			// Ensure we got a valid response
			unowned Json.Object node_obj = parser.get_root().get_object();
			if (node_obj == null) {
				return false;
			}

			// Finally, get the link.
			string? url = node_obj.get_string_member("download_url") ?? null;
			if (url == null) {
				warning("ERROR: %s\n", node_obj.get_string_member("error"));
				return false;
			}

			link = url;
			debug("%s: link from response: %s\n", tempfiles_str, link);

			return true;
		}
	}
}
