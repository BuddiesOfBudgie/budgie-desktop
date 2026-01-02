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

public class SimpleTasklistButtonPopover : Gtk.Popover {
	public Xfw.Window window { get; construct; }

	private Gtk.Button? maximize_button;
	private Gtk.Button? minimize_button;

	public SimpleTasklistButtonPopover(TasklistButton button, Xfw.Window window) {
		Object(relative_to: button, window: window);
	}

	construct {
		width_request = 200;

		get_style_context().add_class("icon-popover");

		maximize_button = new Gtk.Button.with_label("") {
			relief = Gtk.ReliefStyle.NONE,
		};

		minimize_button = new Gtk.Button.with_label(_("Minimize")) {
			relief = Gtk.ReliefStyle.NONE,
		};

		var minimize_button_label = minimize_button.get_child() as Gtk.Label;
		minimize_button_label.halign = Gtk.Align.START;

		var list_box = new Gtk.ListBox() {
			selection_mode = Gtk.SelectionMode.NONE,
		};

		list_box.add(maximize_button);
		list_box.add(minimize_button);

		build_workspace_buttons(list_box);

		add(list_box);

		maximize_button.clicked.connect(() => {
			var maximized = window.is_maximized();

			try {
				window.set_maximized(!maximized);
			} catch (Error e) {
				warning("Unable to set maximized on window %s: %s", window.get_name(), e.message);
			}
		});

		minimize_button.clicked.connect(() => {
			try {
				window.set_minimized(true);
			} catch (Error e) {
				warning("Unable to set minimized on window %s: %s", window.get_name(), e.message);
			}
		});

		window.state_changed.connect((changed_mask, new_state) => {
			if (Xfw.WindowState.MAXIMIZED in changed_mask) {
				update_maximize_label();
			}
		});

		update_maximize_label();

		list_box.show_all();
	}

	private void build_workspace_buttons(Gtk.ListBox list_box) {
		unowned var current_workspace = window.get_workspace();

		if (current_workspace == null) return;

		unowned var workspace_group = current_workspace.get_workspace_group();

		if (workspace_group == null) return;

		foreach (var workspace in workspace_group.list_workspaces()) {
			// Translators: This is used for buttons to move applications to another Workspace
			var button = new Gtk.Button.with_label(_("Move to %s").printf(workspace.get_name())) {
				relief = Gtk.ReliefStyle.NONE,
			};
			var button_label = button.get_child() as Gtk.Label;
			button_label.halign = Gtk.Align.START;

			button.clicked.connect(() => {
				if (workspace == window.get_workspace()) {
					return;
				}

				try {
					window.move_to_workspace(workspace);
				} catch (Error e) {
					warning("Unable to move window '%s' to new workspace: %s", window.get_name(), e.message);
				}
			});

			list_box.add(button);
		}
	}

	private void update_maximize_label() {
		maximize_button.set_label(window.is_maximized() ? _("Unmaximize") : _("Maximize"));

		var maximize_button_label = maximize_button.get_child() as Gtk.Label;
		maximize_button_label.halign = Gtk.Align.START;
	}
}
