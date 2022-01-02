![main_desktop](https://github.com/BuddiesOfBudgie/budgie-desktop/raw/master/.github/screenshots/MainDesktop.png)

# Budgie Desktop

![GitHub release (latest by date)](https://img.shields.io/github/v/release/BuddiesOfBudgie/budgie-desktop)
[![Translate into your language!](https://img.shields.io/badge/help%20translate-Transifex-4AB)](https://www.transifex.com/buddiesofbudgie/budgie-10)

The Budgie Desktop is a feature-rich, modern desktop designed to keep out the way of the user.

![Budgie logo](https://github.com/BuddiesOfBudgie/budgie-desktop/raw/master/.github/logo.png)

## Components

Budgie Desktop consists of a number of components to provide a more complete desktop experience.

### Budgie Menu

The main Budgie menu provides a quick and easy to use menu, suitable for both mouse and keyboard driven users. Features search-as-you-type and category based filtering.

![main_menu](https://github.com/BuddiesOfBudgie/budgie-desktop/raw/master/.github/screenshots/MainMenu.png)

### Raven

Raven provides an all-in-one center for accessing your calendar, controlling sound output and input (including per-app volume control), media playback and more. As well as supporting the usual level of media integration you'd expect, such as media player controls on notifications, support for cover artwork, and global media key support for keyboards, Raven supports all MPRIS compliant media players.

When one of these players are running, such as VLC, Rhythmbox or even Spotify, an MPRIS controller is made available in Raven for quick and simple control of the player, as well as data on the current media selection.

Raven also enables you to access missed notifications, with the ability to swipe away individual notifications, app notifications, and all notifications.

![raven](https://github.com/BuddiesOfBudgie/budgie-desktop/raw/master/.github/screenshots/Raven.png)

#### Notifications

Budgie Desktop supports the freedesktop notifications specification, enabling applications to send visual alerts to the user. These notifications support actions, icons as well as passive modes.

![notification](https://github.com/BuddiesOfBudgie/budgie-desktop/raw/master/.github/screenshots/Notification.png)

### Run Dialog

The Budgie Run Dialog provides the means to quickly find an application in a popup window. This window by default is activated with the `ALT+F2` keyboard shortcut, providing keyboard driven launcher facilities.

![run_dialog](https://github.com/BuddiesOfBudgie/budgie-desktop/raw/master/.github/screenshots/RunDialog.png)

### Other

#### End Session Dialog

The session dialog provides the usual shutdown, logout, options which can be activated using the User Indicator applet.

![end_session_dialog](https://github.com/BuddiesOfBudgie/budgie-desktop/raw/master/.github/screenshots/EndSession.png)

#### PolicyKit integration

The `budgie-polkit-dialog` provides a PolicyKit agent for the session, ensuring a cohesive and integrated experience whilst authenticating for actions on modern Linux desktop systems.

![budgie_polkit](https://github.com/BuddiesOfBudgie/budgie-desktop/raw/master/.github/screenshots/Polkit.png)

## Testing

As and when new features are implemented - it can be helpful to reset the configuration to the defaults to ensure everything is still working ok. To reset the entire configuration tree, issue:

```bash
budgie-panel --reset --replace &!
```

## License

budgie-desktop is available under a split license model. This enables developers to link against the libraries of budgie-desktop without affecting their choice of license and distribution.

The shared libraries are available under the terms of the LGPL-2.1, allowing developers to link against the API without any issue, and to use all exposed APIs without affecting their project license.

The background shipped in data/backgrounds was originally shipped as part of [gnome-backgrounds](https://gitlab.gnome.org/GNOME/gnome-backgrounds), Copyright © 2012 Garrett LeSage and licensed under the Creative Commons Attribution-ShareAlike 3.0 License. [Source commit here](https://gitlab.gnome.org/GNOME/gnome-backgrounds/-/commit/33c37ed6e55218210f6ad9877091f5849bea2d4d).

The remainder of the project (i.e. installed binaries) is available under the terms of the GPL 2.0 license. This is clarified in the headers of each source file.

## Authors

Copyright © 2014-2021 Budgie Desktop Developers

See our [contributors graph](https://github.com/BuddiesOfBudgie/budgie-desktop/graphs/contributors)!
