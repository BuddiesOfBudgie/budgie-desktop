/**
 * Simple widget that shows an application icon, name, and description.
 */
public class LauncherButton : Gtk.Box {
	public Budgie.Application application { get; construct; }

	construct {
		this.get_style_context().add_class("launcher-button");

		var image = new Gtk.Image.from_gicon(application.icon, Gtk.IconSize.DIALOG) {
			pixel_size = 48,
			margin_start = 8
		};

		var right_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);

		var app_name = Markup.escape_text(application.name);
		var sdesc = application.description ?? "";

		var desc = Markup.escape_text(sdesc);
		var name_label = new Gtk.Label("<big>%s</big>".printf(app_name)) {
			halign = Gtk.Align.START,
			xalign = 0,
			use_markup = true,
		};

		var desc_label = new Gtk.Label(desc) {
			halign = Gtk.Align.START,
			xalign = 0,
			wrap = true,
			max_width_chars = 240, // TODO: do this dynamically somehow?
			use_markup = true
		};
		desc_label.get_style_context().add_class("dim-label");

		right_box.pack_start(name_label, false, false, 0);
		right_box.pack_start(desc_label, true, true, 0);

		this.pack_start(image, false, false, 0);
		this.pack_start (right_box, true, true, 0);
		this.set_tooltip_text(application.name);
	}

	public LauncherButton(Budgie.Application app) {
		Object(
			application: app,
			orientation: Gtk.Orientation.HORIZONTAL,
			spacing: 12,
			hexpand: false,
			vexpand: false,
			halign: Gtk.Align.START,
			valign: Gtk.Align.START,
			margin_top: 3,
			margin_bottom: 3
		);
	}
}
