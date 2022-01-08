/*
 * This file is part of budgie-desktop
 *
 * Copyright © 2018-2022 Budgie Desktop Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

namespace Budgie.Notifications{
    public const int NOTIFICATION_SIZE = 400;

    /**
	 * This class is a notification popup with no content in it.
	 */
	public class PopupBase : Gtk.Window {
		protected Gtk.Box content_box;
		
		private uint expire_id { get; private set; }
		
		public signal void Closed(CloseReason reason);

		construct {
			this.resizable = false;
			this.skip_pager_hint = true;
			this.skip_taskbar_hint = true;
			this.set_decorated(false);

			var visual = this.screen.get_rgba_visual();
			if (visual != null) {
				this.set_visual(visual);
			}

			this.set_default_size(NOTIFICATION_SIZE, -1);
			this.get_style_context().add_class("budgie-notification-window");

			this.content_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			this.content_box.get_style_context().add_class("drop-shadow");

			var close_button = new Gtk.Button.from_icon_name("window-close-symbolic", Gtk.IconSize.BUTTON) {
				halign = Gtk.Align.END,
				valign = Gtk.Align.START
			};
			close_button.clicked.connect(() => {
				this.Closed(CloseReason.DISMISSED);
				this.dismiss();
			});
		}

		/**
		 * Destroy this notification popup.
		 */
		public void dismiss() {
			destroy();
		}

		/**
		 * Close this notification when it expires.
		 */
		bool do_expire() {
			this.expire_id = 0;

			this.Closed(CloseReason.EXPIRED);
			this.dismiss();
			return false;
		}

		/**
		 * Start the decay timer for this notification. At the end of the decay, the notification is closed.
		 */
		public void begin_decay(uint timeout) {
			if (this.expire_id != 0) {
				Source.remove(this.expire_id);
			}

			this.expire_id = Timeout.add(timeout, do_expire, Priority.HIGH);
		}

		/**
		 * Stop the decay timer for this notification.
		 */
		public void stop_decay() {
			if (this.expire_id > 0) {
				Source.remove(this.expire_id);
				this.expire_id = 0;
			}
		}
	}

	public class Popup : PopupBase {
		public Server owner { get; construct; }
		public Notification notification { get; construct; }

		public bool did_interact { get; private set; default = false; }

		/**
		 * Signal emitted when an action is clicked.
		 */
		public signal void ActionInvoked(string action_key);

		public Popup(Server? owner, Notification notification) {
			Object(
				type: Gtk.WindowType.POPUP,
				type_hint: Gdk.WindowTypeHint.NOTIFICATION,
				owner: owner,
				notification: notification
			);
		}

		construct {
			bool has_actions = this.notification.actions.length > 0;
			bool has_default_action = false;

			// Check for a default action
			foreach (string action in this.notification.actions) {
				if (action == "default") {
					has_default_action = true;
					break;
				}
			}

			// Create the content widgets for the popup
			var contents = new Body(this.notification);
			contents.ActionInvoked.connect((action_key) => {
				this.ActionInvoked(action_key);
				this.dismiss();
			});
			this.content_box.add(contents);

			// Handle mouse enter/leave events to pause/start popup decay
			this.enter_notify_event.connect(() => {
				this.stop_decay();
				return Gdk.EVENT_STOP;
			});

			this.leave_notify_event.connect(() => {
				this.begin_decay(this.notification.expire_timeout);
				return Gdk.EVENT_STOP;
			});

			// Handle interaction events
			this.button_release_event.connect(() => {
				if (has_default_action) {
					this.ActionInvoked("default");
				} else if (this.notification.app_info != null && !has_actions) {
					// Try to launch the application that generated the notification
					try {
						notification.app_info.launch(null, null);
					} catch (Error e) {
						critical("Unable to launch app: %s", e.message);
					}
				}

				this.dismiss();
				return Gdk.EVENT_STOP;
			});
		}

		/**
		 * Replace the content of this notification with a new notification.
		 */
		public void replace(Notification new_notif) {
			var new_contents = new Body(new_notif);
			new_contents.show_all();

			new_contents.ActionInvoked.connect((action_key) => {
				this.ActionInvoked(action_key);
				dismiss();
			});

			this.content_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			this.content_box.get_style_context().add_class("drop-shadow");
			this.content_box.add(new_contents);
		}
	}

	/**
	 * This class holds the widgets for all of the parts of a notification popup.
	 */
	private class Body: Gtk.Grid {
		public Notification notification { get; construct; }

		/**
		 * Signal emitted when an action is clicked.
		 */
		public signal void ActionInvoked(string action_key);

		public Body(Notification notification) {
			Object(notification: notification);
		}

		construct {
			this.get_style_context().add_class("budgie-notification");

			// TODO: See what more we need to do for the icon
			var app_icon = this.notification.notif_icon;
			if (app_icon != null) {
				app_icon.pixel_size = 48;
			}

			var title_label = new Gtk.Label(this.notification.summary) {
				ellipsize = Pango.EllipsizeMode.END,
				margin_top = 8,
				halign = 0
			};
			title_label.get_style_context().add_class("notification-title");

			var body_label = new Gtk.Label(this.notification.body) {
				ellipsize = Pango.EllipsizeMode.END,
				use_markup = true,
				wrap = true,
				wrap_mode = Pango.WrapMode.WORD_CHAR,
				halign = 0
			};
			body_label.get_style_context().add_class("notification-body");

			// Attach the icon and labels to our grid
			this.attach(app_icon, 0, 0, 1, 2);
			this.attach(title_label, 1, 0);
			this.attach(body_label, 1, 1);

			// Add notification actions if any are present
			if (this.notification.actions.length > 0) {
				var action_box = new Gtk.ButtonBox(Gtk.Orientation.HORIZONTAL) {
					layout_style = Gtk.ButtonBoxStyle.CENTER,
					margin_top = 6,
					margin_bottom = 3
				};
				action_box.get_style_context().add_class("linked");

				bool icons = this.notification.hints.contains("action-icons");

				for (int i = 0; i < this.notification.actions.length; i += 2) {
					// Only add an action if its not a default action
					if (this.notification.actions[i] != "default") {
						Gtk.Button? button = null;
						var action = this.notification.actions[i].dup();

						// If we have action icons, use those. Otherwise, just a labelled button
						if (icons) {
							if (!action.has_suffix("-symbolic")) {
								button = new Gtk.Button.from_icon_name("%s-symbolic".printf(action), Gtk.IconSize.MENU);
							} else {
								button = new Gtk.Button.from_icon_name(action, Gtk.IconSize.MENU);
							}
						} else {
							button = new Gtk.Button.with_label(this.notification.actions[i]);
							button.set_can_focus(false);
							button.set_can_default(false);
						}
	
						button.clicked.connect(() => {
							this.ActionInvoked(action);
						});
	
						action_box.add(button);
					} else {
						i += 2;
					}
				}

				this.attach(action_box, 0, 2, 2);
			}
		}
	}
}