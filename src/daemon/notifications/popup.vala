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

namespace Budgie.Notifications {
	public const int NOTIFICATION_WIDTH = 400;
	public const int MIN_TIMEOUT = 4000;
	public const int MAX_TIMEOUT = 10000;

	/**
	 * This class is a notification popup with no content in it.
	 */
	public class PopupBase : Gtk.Window {
		protected Gtk.Stack content_stack;

		private uint expire_id { get; private set; }

		public signal void Closed(NotificationCloseReason reason);

		construct {
			this.resizable = false;
			this.skip_pager_hint = true;
			this.skip_taskbar_hint = true;
			this.set_decorated(false);

			this.halign = Gtk.Align.FILL;
			this.valign = Gtk.Align.FILL;

			var visual = this.screen.get_rgba_visual();
			if (visual != null) {
				this.set_visual(visual);
			}

			this.set_default_size(NOTIFICATION_WIDTH, -1);
			this.get_style_context().add_class("budgie-notification-window");

			this.content_stack = new Gtk.Stack() {
				transition_type = Gtk.StackTransitionType.SLIDE_LEFT,
				border_width = 8,
				halign = Gtk.Align.FILL,
				valign = Gtk.Align.FILL,
				vhomogeneous = false
			};
			this.content_stack.get_style_context().add_class("drop-shadow");

			this.add(this.content_stack);
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

			this.Closed(NotificationCloseReason.EXPIRED);
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

			var t = timeout;
			if (timeout < MIN_TIMEOUT) {
				t = MIN_TIMEOUT;
			} else if (timeout > MAX_TIMEOUT) {
				t = MAX_TIMEOUT;
			}

			this.expire_id = Timeout.add(t, do_expire, Priority.HIGH);
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

		public override void get_preferred_width(out int min, out int nat) {
			min = nat = NOTIFICATION_WIDTH;
		}

		public override void get_preferred_width_for_height(int h, out int min, out int nat) {
			min = nat = NOTIFICATION_WIDTH;
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
			var content_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				baseline_position = Gtk.BaselinePosition.CENTER
			};
			var contents = new Body(this.notification);
			this.content_stack.add(content_box);
			content_box.pack_start(contents, false, true, 0);

			// Hook up the close button
			contents.Closed.connect(() => {
				this.Closed(NotificationCloseReason.DISMISSED);
				this.dismiss();
			});

			// Add notification actions if any are present
			if (this.notification.actions.length > 0) {
				var actions = new ActionBox(this.notification.actions, this.notification.hints.contains("action-icons"));
				actions.ActionInvoked.connect((action_key) => {
					this.ActionInvoked(action_key);
					this.dismiss();
				});
				content_box.pack_start(actions, false, true, 0);
			}

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

				// Emit this signal since the notification will be closed to make sure
				// our latest popup tracking doesn't break.
				this.Closed(NotificationCloseReason.DISMISSED);
				this.dismiss();
				return Gdk.EVENT_STOP;
			});
		}

		/**
		 * Replace the content of this notification with a new notification.
		 */
		public void replace(Notification new_notif) {
			this.stop_decay();
			var content_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				baseline_position = Gtk.BaselinePosition.CENTER
			};

			var new_contents = new Body(new_notif);
			content_box.add(new_contents);

			new_contents.Closed.connect(() => {
				this.Closed(NotificationCloseReason.DISMISSED);
				this.dismiss();
			});

			// Add notification actions if any are present
			if (new_notif.actions.length > 0) {
				var actions = new ActionBox(new_notif.actions, new_notif.hints.contains("action-icons"));
				actions.ActionInvoked.connect((action_key) => {
					this.ActionInvoked(action_key);
				});
				content_box.pack_start(actions, false, true, 0);
			}

			content_box.show_all();

			this.content_stack.add(content_box);
			this.content_stack.visible_child = content_box;
			this.show_all();
			this.begin_decay(new_notif.expire_timeout);
		}
	}

	/**
	 * This class holds the widgets for all of the parts of a notification popup.
	 */
	private class Body: Gtk.Grid {
		public Notification notification { get; construct; }

		public signal void Closed();

		public Body(Notification notification) {
			Object(notification: notification);
		}

		construct {
			this.orientation = Gtk.Orientation.HORIZONTAL;
			this.margin = 4;
			this.halign = Gtk.Align.FILL;
			this.valign = Gtk.Align.FILL;
			this.get_style_context().add_class("budgie-notification");

			var app_icon = this.notification.image;
			app_icon.set_pixel_size(48);
			app_icon.margin_end = 8;
			app_icon.halign = Gtk.Align.FILL;
			app_icon.valign = Gtk.Align.START;
			app_icon.get_style_context().add_class("notification-icon");

			var title_label = new Gtk.Label(this.notification.summary) {
				ellipsize = Pango.EllipsizeMode.END,
				max_width_chars = 35,
				margin_bottom = 5,
				halign = Gtk.Align.START,
				hexpand = true
			};
			title_label.get_style_context().add_class("notification-title");

			var body_label = new Gtk.Label(this.notification.body) {
				ellipsize = Pango.EllipsizeMode.END,
				use_markup = true,
				wrap = true,
				wrap_mode = Pango.WrapMode.WORD_CHAR,
				max_width_chars = 35,
				halign = Gtk.Align.START,
				valign = Gtk.Align.START,
				hexpand = true,
				vexpand = true
			};
			body_label.get_style_context().add_class("notification-body");

			var close_button = new Gtk.Button.from_icon_name("window-close-symbolic", Gtk.IconSize.BUTTON) {
				halign = Gtk.Align.END,
				valign = Gtk.Align.START
			};
			close_button.clicked.connect(() => {
				this.Closed();
			});

			// Attach the icon and labels to our grid
			this.attach(app_icon, 0, 0, 1, 2);
			this.attach(title_label, 1, 0);
			this.attach(close_button, 2, 0);
			this.attach(body_label, 1, 1);
		}
	}

	/**
	 * Holds the buttons for notification action buttons.
	 */
	private class ActionBox : Gtk.ButtonBox {
		public string[] actions { get; construct set; }
		public bool has_icons { get; construct set; }

		/**
		 * Signal emitted when an action button is clicked.
		 */
		public signal void ActionInvoked(string action_key);

		public ActionBox(string[] actions, bool has_icons) {
			Object(actions: actions, has_icons: has_icons);
		}

		construct {
			this.orientation = Gtk.Orientation.HORIZONTAL;
			this.layout_style = Gtk.ButtonBoxStyle.CENTER;
			this.margin_top = 5;
			this.margin_bottom = 3;
			this.halign = Gtk.Align.FILL;
			this.get_style_context().add_class("linked");

			for (int i = 0; i < this.actions.length; i += 2) {
				// Only add an action if its not a default action
				if (this.actions[i] != "default") {
					Gtk.Button? button = null;
					var action = this.actions[i].dup();

					// If we have action icons, use those. Otherwise, just a labelled button
					if (this.has_icons) {
						if (!action.has_suffix("-symbolic")) {
							button = new Gtk.Button.from_icon_name("%s-symbolic".printf(action), Gtk.IconSize.MENU);
						} else {
							button = new Gtk.Button.from_icon_name(action, Gtk.IconSize.MENU);
						}
					} else {
						button = new Gtk.Button.with_label(this.actions[i + 1]);
						button.set_can_focus(false);
						button.set_can_default(false);
					}

					button.clicked.connect(() => {
						this.ActionInvoked(action);
					});

					this.add(button);
				} else {
					i += 2;
				}
			}
		}
	}
}
