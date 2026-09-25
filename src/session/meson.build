# Main session scripts

# We bash-quote already.
session_data = configuration_data()
session_data.set('PACKAGE_VERSION', package_version)
session_data.set('libexecdir', libexecdir)
session_data.set('libexecdirroot', libexecdirroot)

# gnome-settings-daemon components
gsd_components_excluded = get_option('gsd-components-excluded')
gsd_components = []
foreach component: get_option('gsd-components')
    if component not in gsd_components_excluded
        gsd_components += component
    endif
endforeach

budgie_session_324_components = []
foreach component: gsd_components
    budgie_session_324_components += 'org.buddiesofbudgie.SettingsDaemon.' + component
endforeach

# Always in Budgie
budgie_components = [
    'org.buddiesofbudgie.BudgieDaemon',
    'org.buddiesofbudgie.BudgiePanel',
    'org.buddiesofbudgie.BudgiePowerDialog',
    'org.buddiesofbudgie.BudgieScreenshotDialog',
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
# Set bindir to budgie-desktop
session_data.set('bindir', bindir)
# Set datadir to budgie-desktop
session_data.set('datadir', datadir)

# Set bindir to labwc
labwc_bindir = get_option('labwc-bindir')
if labwc_bindir == ''
    labwc_bindir = bindir
endif
session_data.set('labwc_bindir', labwc_bindir)

# Set bindir to magpie-wm
#magpie_bindir = get_option('magpie-bindir')
#if magpie_bindir == ''
#    magpie_bindir = bindir
#endif
#session_data.set('magpie_bindir', magpie_bindir)

# Set libexecdir to budgie-session
budgie_session_libexecdir = get_option('budgie-session-libexecdir')
if budgie_session_libexecdir == ''
    budgie_session_libexecdir = libexecdirroot
endif
session_data.set('budgie_session_libexecdir', budgie_session_libexecdir)

# Set libexecdir to gnome-settings-daemon
# Unfortunately this info is not provided by its pkgconfig file
gsd_libexecdir = get_option('gsd-libexecdir')
if gsd_libexecdir == ''
    gsd_libexecdir = libexecdirroot
endif
session_data.set('gsd_libexecdir', gsd_libexecdir)

# Set the libexecdir for xdg-desktop-portal
xdp_libexecdir = get_option('xdp-libexecdir')
if xdp_libexecdir == ''
    xdp_libexecdir = libexecdirroot
endif
session_data.set('xdp_libexecdir', xdp_libexecdir)

# Start oo7-daemon with the session when oo7 support is enabled
if oo7 == true
    session_data.set('oo7_daemon', '  ' + join_paths(oo7_libexecdir, 'oo7-daemon') + ' &')
else
    session_data.set('oo7_daemon', '')
endif

# magpie is here while its merge is commented out, to keep its translations
budgie_pot_templates += files(
    'budgie-desktop.session.desktop.in.in',
    'budgie-desktop.desktop.in.in',
    'budgie-desktop-magpie.desktop.in.in',
    'budgie-desktop-nm-applet.desktop.in',
    'budgie-desktop-powerdialog.desktop.in.in',
    'budgie-desktop-screenshotdialog.desktop.in.in',
)

# Write the budgie-desktop.session.in file from the .in.in
session_conf = configure_file(
    input: 'budgie-desktop.session.desktop.in.in',
    output: 'budgie-desktop.session.in',
    configuration: session_data,
)

# Now merge the translations of the .desktop.in to a .desktop
i18n.merge_file(
    input : session_conf,
    output : 'org.buddiesofbudgie.BudgieDesktop.session',
    type : 'desktop',
    po_dir : podir,
    install : true,
    install_dir : join_paths(datadir, 'gnome-session', 'sessions'),
)

# Write /usr/bin/startbudgielabwc script
configure_file(
    input: 'startbudgielabwc.in',
    output: 'startbudgielabwc',
    configuration: session_data,
    install_dir: join_paths(get_option('prefix'), get_option('bindir')),
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
i18n.merge_file(
    input : waylandsession_conf,
    output : 'budgie-desktop.desktop',
    type : 'desktop',
    po_dir : podir,
    install : true,
    install_dir : join_paths(datadir, 'wayland-sessions'),
)

# Configure the magpie wayland-session file
#waylandmagpiesession_conf = configure_file(
#    input: 'budgie-desktop-magpie.desktop.in.in',
#    output: 'budgie-desktop-magpie.desktop.in',
#    configuration: session_data,
#)

# Now merge the translations of the .desktop.in to a .desktop
#i18n.merge_file(
#    input : waylandmagpiesession_conf,
#    output : 'budgie-desktop-magpie.desktop',
#    type : 'desktop',
#    po_dir : podir,
#    install : true,
#    install_dir : join_paths(datadir, 'wayland-sessions'),
#)

# Merge + install nm-applet
i18n.merge_file(
    input : 'budgie-desktop-nm-applet.desktop.in',
    output : 'org.buddiesofbudgie.BudgieDesktopNmApplet.desktop',
    type : 'desktop',
    po_dir : podir,
    install : true,
    install_dir : xdg_appdir,
)

# Merge + install power dialog
session_power_dialog_desktop = configure_file(
    input: 'budgie-desktop-powerdialog.desktop.in.in',
    output: 'budgie-desktop-powerdialog.desktop.in',
    configuration: session_data,
)

i18n.merge_file(
    input : session_power_dialog_desktop,
    output : 'org.buddiesofbudgie.BudgiePowerDialog.desktop',
    type : 'desktop',
    po_dir : podir,
    install : true,
    install_dir : xdg_appdir,
)

# Merge + install Screenshot dialog
session_screenshot_dialog_desktop = configure_file(
    input: 'budgie-desktop-screenshotdialog.desktop.in.in',
    output: 'budgie-desktop-screenshotdialog.desktop.in',
    configuration: session_data,
)

i18n.merge_file(
    input : session_screenshot_dialog_desktop,
    output : 'org.buddiesofbudgie.BudgieScreenshotDialog.desktop',
    type : 'desktop',
    po_dir : podir,
    install : true,
    install_dir : xdg_appdir,
)

# install gnome-settings-daemon desktop files to ensure they autostart

foreach component: budgie_session_324_components
    configure_file(
        input: join_paths('settingsdaemon', component + '.desktop.in'),
        output: '@BASENAME@',
        configuration: session_data,
        install_dir: xdg_appdir,
    )
endforeach

install_data(
    'org.buddiesofbudgie.settings-daemon.plugins.media-keys.gschema.xml',
    install_dir: join_paths(datadir, 'glib-2.0', 'schemas'),
)
