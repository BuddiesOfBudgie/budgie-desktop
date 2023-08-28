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

using Gtk;

namespace Budgie {
	/**
	 * Wraps a `Gtk.Button` for use in the Budgie PowerDialog.
	 *
	 * It has a CSS class named power-dialog-button.
	 */
	public class DialogButton : Button {
		private Box? menu_item = null;
		private Image? button_image = null;
		private Label? button_label = null;

		private string? _image_source = null;
		public string? image_source {
			get { return _image_source; }
			set {
				_image_source = image_source;
				set_image(image_source);
			}
		}

		private string? _label_text = null;
		public string? label_text {
			get { return _label_text; }
			set {
				set_label(label_text);
			}
		}

		/**
		 * Creates a new [DialogButton].
		 *
		 * If characters in `label_text` are preceded by an underscore, they are underlined.
		 * If you need a literal underscore character in a label, use '__' (two underscores).
		 * The first underlined character represents a keyboard accelerator called a mnemonic.
		 * The mnemonic key can be used to activate this button.
		 */
		public DialogButton(string label_text, string image_source) {
			Object(can_focus: true, use_underline: true);

			set_image(image_source);
			set_label(label_text);

			menu_item = new Box(Orientation.VERTICAL, 12);
			menu_item.pack_start(button_image, false, false, 0);
			menu_item.pack_end(button_label, false, false, 0);
			menu_item.margin = 8;

			add(menu_item);
		}

		construct {
			get_style_context().add_class("flat");
			get_style_context().add_class("power-dialog-button");

			show_all();
		}

		/**
		 * Set the image for this item.
		 */
		public new void set_image(string source) {
			if (button_image == null) {
				button_image = new Image();
			}

			button_image.set_from_icon_name(source, IconSize.DIALOG); // 48px
		}

		/**
		 * Sets the label for this item.
		 *
		 * If characters in `text` are preceded by an underscore, they are underlined.
		 * If you need a literal underscore character in a label, use '__' (two underscores).
		 * The first underlined character represents a keyboard accelerator called a mnemonic.
		 * The mnemonic key can be used to activate this button.
		 */
		public new void set_label(string text) {
			_label_text = text.dup();

			if (button_label == null) {
				button_label = new Label.with_mnemonic(null) {
					halign = Align.CENTER,
				};
			}

			button_label.set_markup_with_mnemonic("<big>%s</big>".printf(_label_text));
		}
	}
}
