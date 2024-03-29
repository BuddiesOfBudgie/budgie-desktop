# Main session scripts

# We bash-quote already.
session_data = configuration_data()
session_data.set('PACKAGE_VERSION', package_version)
session_data.set('libexecdir', libexecdir)

gnome_session_components = [
    'gnome-settings-daemon',
]

gnome_session_324_components = [
    'org.gnome.SettingsDaemon.A11ySettings',
    'org.gnome.SettingsDaemon.Color',
    'org.gnome.SettingsDaemon.Datetime',
    'org.gnome.SettingsDaemon.Housekeeping',
    'org.gnome.SettingsDaemon.Keyboard',
    'org.gnome.SettingsDaemon.MediaKeys',
    'org.gnome.SettingsDaemon.Power',
    'org.gnome.SettingsDaemon.PrintNotifications',
    'org.gnome.SettingsDaemon.Rfkill',
    'org.gnome.SettingsDaemon.ScreensaverProxy',
    'org.gnome.SettingsDaemon.Sharing',
    'org.gnome.SettingsDaemon.Smartcard',
    'org.gnome.SettingsDaemon.Sound',
    'org.gnome.SettingsDaemon.Wacom',
    'org.gnome.SettingsDaemon.XSettings',
]

gsd_324_key = [
    'org.gnome.SettingsDaemon.A11yKeyboard'
]

gsd_324_mc = [
    'org.gnome.SettingsDaemon.Clipboard',
    'org.gnome.SettingsDaemon.Mouse'
]


gsd_324_max = [
    'org.gnome.SettingsDaemon.Orientation',
    'org.gnome.SettingsDaemon.XRANDR',
]

# Always in Budgie
budgie_components = [
    'org.buddiesofbudgie.BudgieWm',
    'org.buddiesofbudgie.BudgieDaemon',
    'org.buddiesofbudgie.BudgiePanel',
    'org.buddiesofbudgie.BudgiePowerDialog'
]

if with_polkit == true
    budgie_components += 'org.buddiesofbudgie.BudgiePolkit'
endif

dep_gsd = dependency('gnome-settings-daemon', version: gnome_minimum_version)
# Merge the list depending on the gnome-settings-daemon version.
if dep_gsd.version().version_compare('>=3.33.90')
    session_components = budgie_components + gnome_session_324_components
elif dep_gsd.version().version_compare('>=3.27.90')
    session_components = budgie_components + gnome_session_324_components + gsd_324_mc
elif dep_gsd.version().version_compare('>=3.25.4')
    session_components = budgie_components + gnome_session_324_components + gsd_324_mc + gsd_324_key
elif dep_gsd.version().version_compare('>=3.23.3')
    session_components = budgie_components + gnome_session_324_components + gsd_324_mc + gsd_324_key + gsd_324_max
else
    session_components = gnome_session_components + budgie_components
endif

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

# Configure the xsession file
xsession_conf = configure_file(
    input: 'budgie-desktop.desktop.in.in',
    output: 'budgie-desktop.desktop.in',
    configuration: session_data,
)

# Now merge the translations of the .desktop.in to a .desktop
custom_target('desktop-file-xsession',
    input : xsession_conf,
    output : 'budgie-desktop.desktop',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : join_paths(datadir, 'xsessions'),
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
