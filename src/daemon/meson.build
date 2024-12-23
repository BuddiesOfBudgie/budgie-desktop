# Provides budgie-daemon component

custom_target('desktop-file-daemon',
    input : 'budgie-daemon.desktop.in',
    output : 'org.buddiesofbudgie.BudgieDaemon.desktop',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : join_paths(datadir, 'applications'))

# Compile the assets into the binary
daemon_resources = gnome.compile_resources(
    'budgie-daemon-resources',
    'budgie-daemon.gresource.xml',
    source_dir: '.',
    c_name: 'budgie_polkit',
)

lib_daemon_resources = static_library(
    'budgie-daemon-resources',
    daemon_resources,
    dependencies: [ dep_glib ],
    install: false,
    c_args: ['-Wno-overlength-strings'], # gresource generates overlength strings...
)

daemon_sources = [
    'endsession.vala',
    'notifications/dbus.vala',
    'notifications/popup.vala',
    'screenshot.vala',
    'background.vala',
    'statusnotifier.vala',
    'main.vala',
    'manager.vala',
    'menus.vala',
    'osd.vala',
    'settings.vala',
    'screenlock.vala',
    'tabswitcher.vala',
    'xdgdirtracker/dbus.vala',
]

daemon_deps = [
    dep_canberra,
    dep_canberra_gtk3,
    dep_giounix,
    dep_gtk3,
    dep_gdkx11,
    dep_notify,
    dep_gnomedesktop,
    dep_wnck,
    dep_xfce4windowing,
    dep_gst,
    dep_cairo,
    link_libbudgieprivate,
    libpanelplugin_vapi,
    link_libappsys,
    link_libconfig,
    link_libtheme,
    link_libsession,
]

# Need absolute path to gresource
gresource = join_paths(meson.current_source_dir(), 'budgie-daemon.gresource.xml')

daemon_vala_args = ['--pkg', 'gnome-desktop-3.0']

dep_gsd_doubles = dependency('gnome-settings-daemon', version: '>=3.33.90', required: false)
if dep_gsd.found()
    daemon_vala_args += ['-D', 'USE_GSD_DOUBLES']
    message('Found GNOME Settings Daemon >= 3.33.90')
endif

top_vapidir = join_paths(meson.source_root(), 'vapi')

executable(
    'budgie-daemon', daemon_sources,
    dependencies: daemon_deps,
    link_whole: [
        lib_daemon_resources,
    ],
    vala_args: [
        '--vapidir', dir_libtheme,
        '--vapidir', dir_libconfig,
        '--vapidir', dir_libappsys,
        '--vapidir', top_vapidir,
        '--pkg', 'theme',
        '--pkg', 'budgie-config',
        '--pkg', 'gio-unix-2.0',
        '--pkg', 'gtk+-3.0',
        '--pkg', 'gdk-x11-3.0',
        '--pkg', 'libxfce4windowing-0',
        # Make gresource work
        '--target-glib=2.38',
        '--gresources=' + gresource,
        daemon_vala_args,
    ],
    c_args: [
        '-DWNCK_I_KNOW_THIS_IS_UNSTABLE',
        '-DGNOME_DESKTOP_USE_UNSTABLE_API'
    ],
    install: true,
)

main_sources = [
  'screenshot_main.vala',
]

ScreenshotMainDependencies = [
    dependency('gtk+-3.0'),
]

executable(
    'org.buddiesofbudgie.BudgieScreenshot', main_sources,
    dependencies: ScreenshotMainDependencies,
    install: true,
    vala_args: daemon_vala_args,
)

install_data('org.buddiesofbudgie.budgie-desktop.screenshot.gschema.xml',
    install_dir: join_paths(datadir, 'glib-2.0', 'schemas')
)

install_data('icons/org.buddiesofbudgie.BudgieScreenshot.svg',
    install_dir: join_paths(datadir, 'icons', 'hicolor', 'scalable', 'apps')
)

# Now merge the translations of the .desktop.in to a .desktop
custom_target('org.buddiesofbudgie.BudgieScreenshot',
    input : 'org.buddiesofbudgie.BudgieScreenshot.desktop.in',
    output : 'org.buddiesofbudgie.BudgieScreenshot.desktop',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : join_paths(datadir, 'applications'),
)

# gschemas
install_data(
    files('notifications/20_buddiesofbudgie.budgie-desktop.notifications.gschema.override'),
    install_dir: join_paths(datadir, 'glib-2.0', 'schemas')
)
