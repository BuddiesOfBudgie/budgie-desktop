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

public abstract class BaseDialog : Gtk.Dialog {
	public Bluetooth.Obex.Transfer transfer;
	public Bluetooth.Device device;

	protected int start_time = 0;
	protected uint64 total_size = 0;

	protected Gtk.ProgressBar progress_bar;
	protected Gtk.Label device_label;
	protected Gtk.Label directory_label;
	protected Gtk.Label progress_label;
	protected Gtk.Label filename_label;
	protected Gtk.Label rate_label;
	protected Gtk.Image device_image;

	BaseDialog(Gtk.Application application) {
		Object(application: application, resizable: false);
	}

	construct {
		var icon_image = new Gtk.Image.from_icon_name("bluetooth-active", Gtk.IconSize.DIALOG) {
			valign = Gtk.Align.END,
			halign = Gtk.Align.END,
		};

		device_image = new Gtk.Image() {
			valign = Gtk.Align.END,
			halign = Gtk.Align.END,
		};

		var overlay = new Gtk.Overlay() {
			margin_right = 12,
		};
		overlay.add(icon_image);
		overlay.add_overlay(device_image);

		directory_label = new Gtk.Label(null) {
			max_width_chars = 45,
			wrap = true,
			xalign = 0,
			use_markup = true,
		};

		device_label = new Gtk.Label(null) {
			max_width_chars = 45,
			wrap = true,
			xalign = 0,
			use_markup = true,
		};

		filename_label = new Gtk.Label(Markup.printf_escaped("<b>%s</b>:", _("File name"))) {
			max_width_chars = 45,
			wrap = true,
			xalign = 0,
			use_markup = true,
		};

		rate_label = new Gtk.Label(Markup.printf_escaped("<b>%s</b>:", _("Transfer rate"))) {
			max_width_chars = 45,
			wrap = true,
			xalign = 0,
			use_markup = true,
		};

		progress_bar = new Gtk.ProgressBar() {
			hexpand = true,
			margin_top = 4,
			margin_bottom = 4,
		};

		progress_label = new Gtk.Label(null) {
			max_width_chars = 45,
			hexpand = false,
			wrap = true,
			xalign = 0,
			margin_bottom = 4,
		};

		var message_grid = new Gtk.Grid() {
			column_spacing = 0,
			row_spacing = 4,
			width_request = 450,
			margin = 10,
		};

		message_grid.attach(overlay, 0, 0, 1, 3);
		message_grid.attach(directory_label, 1, 0, 1, 1);
		message_grid.attach(device_label, 1, 1, 1, 1);
		message_grid.attach(filename_label, 1, 2, 1, 1);
		message_grid.attach(rate_label, 1, 3, 1, 1);
		message_grid.attach(progress_bar, 1, 4, 1, 1);
		message_grid.attach(progress_label, 1, 5, 1, 1);

		get_content_area().add(message_grid);

		// Now add the dialog buttons
		add_button(_("Close"), Gtk.ResponseType.CLOSE);
		var reject_transfer = add_button(_("Cancel"), Gtk.ResponseType.CANCEL);
		reject_transfer.get_style_context().add_class(Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);

		// Hook up the responses
		response.connect((response_id) => {
			if (response_id == Gtk.ResponseType.CANCEL) {
				// Cancel the current transfer if it is active
				if (transfer != null && transfer.status == "active") {
					try {
						transfer.cancel();
					} catch (Error e) {
						warning("Error cancelling Bluetooth transfer: %s", e.message);
					}
				}

				destroy();
			} else {
				// Close button clicked, hide or close
				if (transfer.status == "active") {
					hide_on_delete();
				} else {
					destroy();
				}
			}
		});

		delete_event.connect(() => {
			if (transfer.status == "active") {
				return hide_on_delete();
			} else {
				destroy();
			}
		});
	}

	protected void on_transfer_progress(uint64 transferred) {
		progress_bar.fraction = (double) transferred / (double) total_size;
		int current_time = (int) get_real_time();
		int elapsed_time = (current_time - start_time) / 1000000;

		if (current_time < start_time + 1000000) return;
		if (elapsed_time == 0) return;

		uint64 transfer_rate = transferred / elapsed_time;

		if (transfer_rate == 0) return;

		rate_label.label = Markup.printf_escaped(_("<b>Transfer rate:</b> %s / s"), format_size(transfer_rate));
		uint64 remaining_time = (total_size - transferred) / transfer_rate;
		progress_label.label = _("%s / %s: Time remaining: %s").printf(format_size(transferred), format_size(total_size), format_time((int) remaining_time));
	}

	protected string format_time(int seconds) {
		if (seconds < 0) seconds = 0;

		var hours = seconds / 3600;
		var minutes = (seconds - hours * 3600) / 60;
		seconds = seconds - hours * 3600 - minutes * 60;

		if (hours > 0) {
			var h = ngettext("%u hour", "%u hours", hours).printf(hours);
			var m = ngettext("%u minute", "%u minutes", minutes).printf(minutes);
			return "%s, %s".printf(h, m);
		}

		if (minutes > 0) {
			var m = ngettext("%u minute", "%u minutes", minutes).printf(minutes);
			var s = ngettext("%u second", "%u seconds", seconds).printf(seconds);
			return "%s, %s".printf(m, s);
		}

		return ngettext("%d second", "%d seconds", seconds).printf(seconds);
	}
}
