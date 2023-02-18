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
		IMAGEBIN = 2,
		NULLPOINTER = 3, // 0x0
	}

	public class Uploader {

		public signal void progress_updated(int64 size, int64 chunk);

		public const BudgieScr.Providers[] provider = {
			BudgieScr.Providers.IMGUR,
			BudgieScr.Providers.IMAGEBIN,
			BudgieScr.Providers.NULLPOINTER, // 0x0
		};

		public static string provider_string_to_display(BudgieScr.Providers provider) {
			switch (provider) {
				case Providers.IMGUR:
					return _("Imgur");
				case Providers.IMAGEBIN:
					return _("ImageBin");
				case Providers.NULLPOINTER:
					return _("0x0");
				default:
					return _("0x0");
			}
		}

		// Choose uploader from provided string, return status and link
		public static bool upload_to_provider(string chosenprovider, string path, out string? link) {
			bool status = false;
			link = null;
			switch (chosenprovider) {
				case "Imgur":
					status = upload_image_imgur(path, out link);
					break;
				case "ImageBin":
					status = upload_image_imagebin(path, out link);
					break;
				case "0x0":
					status = upload_image_nullpointer(path, out link);
					break;
				default:
					status = upload_image_nullpointer(path, out link);
					break;
			}
			return status;
		}

		// Upload image to https://imgur.com/ web service
		private static bool upload_image_imgur(string uri, out string? link) {
			link = null;

			// TODO: Provide your own via meson options
			string imgur_clientid = "";
			string imgur_apikey = "";

			var session = new Soup.Session();

			// Setup soup logger if we're debugging
			if (GLib.Log.get_debug_enabled() == true) {
				Soup.Logger logger = new Soup.Logger(Soup.LoggerLogLevel.HEADERS);
				session.add_feature(logger);
			}

			// Read file into memory
			uint8[] data;
			try {
				GLib.FileUtils.get_data(uri, out data);
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

			/*message.wrote_body_data.connect((chunk) => {
				progress_updated(message.request_body.length, chunk.length);
			}); */

			// Send message & get Bytes from response
			// TODO: Async
			GLib.Bytes? payloadbytes = null;
			try {
				payloadbytes = session.send_and_read(message);
			} catch (GLib.Error e) {
				stderr.printf(e.message);
				return false;
			}

			// Encode back to string for json parsing
			string payload = (string)payloadbytes.get_data();
			if (payload == null) {
				return false;
			}

			// Setup json parser with our payload reponse
			Json.Parser parser = new Json.Parser();
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
			debug("imgur: link from response: %s\n", link);

			return true;
		}

		// Upload image to https://0x0.st/ web service
		private static bool upload_image_nullpointer(string uri, out string? link) {
			link = null;

			var session = new Soup.Session();

			// Setup soup logger if we're debugging
			if (GLib.Log.get_debug_enabled() == true) {
				Soup.Logger logger = new Soup.Logger(Soup.LoggerLogLevel.HEADERS);
				session.add_feature(logger);
			}

			// Read file into memory
			uint8[] data;
			try {
				GLib.FileUtils.get_data(uri, out data);
			} catch (GLib.FileError e) {
				warning(e.message);
				return false;
			}

			// Encode to Bytes
			var imagebytes = new GLib.Bytes.take(data);

			// Setup our multipart message
			string mime_type = "application/octet-stream";
			Soup.Multipart multipart = new Soup.Multipart(mime_type);
			multipart.append_form_file("file", uri, mime_type, imagebytes);
			Soup.Message message = new Soup.Message.from_multipart("https://0x0.st/", multipart);

			// Set and get content type
			GLib.HashTable<string, string> content_type_params;
			message.request_headers.get_content_type(out content_type_params);
			message.request_headers.set_content_type(Soup.FORM_MIME_TYPE_MULTIPART, content_type_params);

			// Send message & get Bytes from response
			Bytes? payloadbytes = null;
			try {
				payloadbytes = session.send_and_read(message);
			} catch (GLib.Error e) {
				stderr.printf(e.message);
				return false;
			}

			// Encode back to string for parsing
			string payload = (string)payloadbytes.get_data();
			if (payload == null) {
				return false;
			}

			// Get link from reponse
			if (!payload.has_prefix("http")) {
				return false;
			}
			link = payload.strip();

			debug("0x0: link from response %s\n", link);

			return true;
		}

		// Upload image to https://www.imagebin.ca/ web service
		private static bool upload_image_imagebin(string uri, out string? link) {
			link = null;

			var session = new Soup.Session();

			// Setup soup logger if we're debugging
			if (GLib.Log.get_debug_enabled() == true) {
				Soup.Logger logger = new Soup.Logger(Soup.LoggerLogLevel.HEADERS);
				session.add_feature(logger);
			}

			// Read file into memory
			uint8[] data;
			try {
				GLib.FileUtils.get_data(uri, out data);
			} catch (GLib.FileError e) {
				warning(e.message);
				return false;
			}

			// Encode to Bytes
			var imagebytes = new GLib.Bytes.take(data);

			// Setup our multipart message
			string mime_type = "application/octet-stream";
			Soup.Multipart multipart = new Soup.Multipart(mime_type);
			multipart.append_form_file("file", uri, mime_type, imagebytes);
			var message = new Soup.Message.from_multipart("https://imagebin.ca/upload.php", multipart);

			// get and set content type
			GLib.HashTable<string, string> content_type_params;
			message.request_headers.get_content_type(out content_type_params);
			message.request_headers.set_content_type(Soup.FORM_MIME_TYPE_MULTIPART, content_type_params);

			// Send message & get Bytes from response
			// TODO: Async
			GLib.Bytes? payloadbytes = null;
			try {
				payloadbytes = session.send_and_read(message);
			} catch (GLib.Error e) {
				stderr.printf(e.message);
				return false;
			}

			// Encode back to string for parsing
			string payload = (string)payloadbytes.get_data();
			if (payload == null) {
				return false;
			}

			// Get link from reponse
			string? url = payload.split("url:")[1];
			if (url == null || !url.has_prefix("http")) {
				return false;
			}
			link = url.strip();

			debug("imagebin: link from response %s\n", link);

			return true;
		}
	}
}
