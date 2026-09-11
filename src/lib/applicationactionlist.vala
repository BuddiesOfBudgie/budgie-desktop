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
	* Lists an application's desktop actions as clickable rows.
	*/
	public class ApplicationActionList : Gtk.ListBox {
		public Application app { get; construct; }

		/**
		* Emitted once an action has been launched, so that whatever is
		* presenting this list can dismiss itself.
		*/
		public signal void action_launched();

		public ApplicationActionList(Application app) {
			Object(app: app, selection_mode: Gtk.SelectionMode.NONE);
		}

		construct {
			get_style_context().add_class("application-actions");

			foreach (unowned var action in app.get_actions()) {
				var button = new Gtk.Button.with_label(action.name) {
					relief = Gtk.ReliefStyle.NONE,
				};

				var label = button.get_child() as Gtk.Label;
				if (label != null) {
					label.set_xalign(0);
				}

				button.set_data<string>("action-id", action.id);
				button.clicked.connect(this.on_action_clicked);

				add(button);
			}
		}

		/**
		* Whether this application declares any actions to show.
		*/
		public bool is_empty() {
			return app.get_actions().length == 0;
		}

		private void on_action_clicked(Gtk.Button button) {
			unowned string? id = button.get_data<string>("action-id");
			if (id == null) {
				return;
			}

			app.launch_action(id);
			action_launched();
		}
	}
}
