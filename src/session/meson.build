# Main session scripts

# We bash-quote already.
session_data = configuration_data()
session_data.set('PACKAGE_VERSION', package_version)
session_data.set('libexecdir', libexecdir)

# mandatory gnome-settings-daemon components
budgie_session_324_components = [
    'org.buddiesofbudgie.SettingsDaemon.A11ySettings',
    'org.buddiesofbudgie.SettingsDaemon.Datetime',
    'org.buddiesofbudgie.SettingsDaemon.Housekeeping',
    'org.buddiesofbudgie.SettingsDaemon.Power',
    'org.buddiesofbudgie.SettingsDaemon.PrintNotifications',
    'org.buddiesofbudgie.SettingsDaemon.Rfkill',
    'org.buddiesofbudgie.SettingsDaemon.Sharing',
    'org.buddiesofbudgie.SettingsDaemon.Smartcard',
    'org.buddiesofbudgie.SettingsDaemon.Sound',
    'org.buddiesofbudgie.SettingsDaemon.Wacom',
]

# Always in Budgie
budgie_components = [
    'org.buddiesofbudgie.BudgieDaemon',
    'org.buddiesofbudgie.BudgiePanel',
    'org.buddiesofbudgie.BudgiePowerDialog'
]

if with_polkit == true
    budgie_components += 'org.buddiesofbudgie.BudgiePolkit'
endif

dep_gsd = dependency('gnome-settings-daemon', version: gnome_minimum_version)
session_components = budgie_components + budgie_session_324_components

# Set the session list
session_data.set('SESSION_COMPONENTS', ';'.join(session_components))
# Set the prefix
session_data.set('prefix', join_paths(get_option('prefix')))

# Write the budgie-desktop.session.in file from the .in.in
session_conf = configure_file(
    input: 'budgie-desktop.session.in.in',
    output: 'budgie-desktop.session.in',
    configuration: session_data,
)

# Now merge the translations of the .desktop.in to a .desktop
custom_target('desktop-file-session-main',
    input : session_conf,
    output : 'org.buddiesofbudgie.BudgieDesktop.session',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : join_paths(datadir, 'gnome-session', 'sessions'),
)

# Write /usr/bin/budgie-desktop script
configure_file(
    input: 'budgie-desktop.in',
    output: 'budgie-desktop',
    configuration: session_data,
    install_dir: join_paths(get_option('prefix'), get_option('bindir')),
)

# Configure the default wayland-session file
waylandsession_conf = configure_file(
    input: 'budgie-desktop.desktop.in.in',
    output: 'budgie-desktop.desktop.in',
    configuration: session_data,
)

# Now merge the translations of the .desktop.in to a .desktop
custom_target('desktop-file-waylandsession',
    input : waylandsession_conf,
    output : 'budgie-desktop.desktop',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : join_paths(datadir, 'wayland-sessions'),
)

# Configure the labwc wayland-session file
waylandlabwcsession_conf = configure_file(
    input: 'budgie-desktop-labwc.desktop.in.in',
    output: 'budgie-desktop-labwc.desktop.in',
    configuration: session_data,
)

# Now merge the translations of the .desktop.in to a .desktop
custom_target('desktop-file-waylandlabwcsession',
    input : waylandlabwcsession_conf,
    output : 'budgie-desktop-labwc.desktop',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : join_paths(datadir, 'wayland-sessions'),
)

# Merge + install nm-applet
custom_target('desktop-file-nm-applet',
    input : 'budgie-desktop-nm-applet.desktop.in',
    output : 'org.buddiesofbudgie.BudgieDesktopNmApplet.desktop',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : xdg_appdir,
)

# Write the budgie-desktop-screensaver.in file from the appropriate .in.in
if with_gnome_screensaver == true
    session_screensaver = configure_file(
        input: 'budgie-desktop-screensaver-gnome.desktop.in.in',
        output: 'budgie-desktop-screensaver.desktop.in',
        configuration: session_data,
    )
else
    session_screensaver = configure_file(
        input: 'budgie-desktop-screensaver.desktop.in.in',
        output: 'budgie-desktop-screensaver.desktop.in',
        configuration: session_data,
    )
endif

# Merge + install screensaver
custom_target('desktop-file-screensaver',
    input : session_screensaver,
    output : 'org.buddiesofbudgie.BudgieDesktopScreensaver.desktop',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : xdg_appdir,
)

# Merge + install power dialog
session_power_dialog_desktop = configure_file(
    input: 'budgie-desktop-powerdialog.desktop.in.in',
    output: 'budgie-desktop-powerdialog.desktop.in',
    configuration: session_data,
)

custom_target('desktop-file-powerdialog',
    input : session_power_dialog_desktop,
    output : 'org.buddiesofbudgie.BudgiePowerDialog.desktop',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : xdg_appdir,
)

# install gnome-settings-daemon desktop files to ensure they autostart

install_subdir(
    'settingsdaemon',
    install_dir: xdg_appdir,
    strip_directory: true
)
