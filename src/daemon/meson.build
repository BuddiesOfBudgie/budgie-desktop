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

# Shared Brightness Utility (used by both daemon and helper)
brightness_util_sources = files(
    'brightness-util.vala',
)

daemon_sources = [
    brightness_util_sources,
    'brightness-manager.vala',
    'crystal_dock_helper.vala',
    'endsession.vala',
    'notifications/dbus.vala',
    'notifications/popup.vala',
    'background.vala',
    'statusnotifier.vala',
    'main.vala',
    'manager.vala',
    'nightlight.vala',
    'osd.vala',
    'settings.vala',
    'screenlock.vala',
    'screenshot.vala',
    'xdgdirtracker/dbus.vala',
    'osdkeys.vala'
]

daemon_deps = [
    dep_canberra,
    dep_canberra_gtk3,
    dep_giounix,
    dep_gtk3,
    dep_notify,
    dep_gnomedesktop,
    dep_xfce4windowing,
    dep_gst,
    dep_cairo,
    gvc.get_variable('libgvc_dep'),
    meson.get_compiler('c').find_library('m', required: false),
    dep_upower,
    link_libbudgieprivate,
    libpanelplugin_vapi,
    link_libappsys,
    link_libconfig,
    link_libtheme,
    link_libsession,
    link_libbudgiewayland
]

# Need absolute path to gresource
gresource = join_paths(meson.current_source_dir(), 'budgie-daemon.gresource.xml')

daemon_vala_args = ['--pkg', 'gnome-desktop-3.0']

dep_gsd_doubles = dependency('gnome-settings-daemon', version: '>=3.33.90', required: false)
if dep_gsd.found()
    daemon_vala_args += ['-D', 'USE_GSD_DOUBLES']
    message('Found GNOME Settings Daemon >= 3.33.90')
endif

top_vapidir = join_paths(meson.project_source_root(), 'vapi')

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
        '--pkg', 'gvc-1.0',
        '--pkg', 'posix',
        # Make gresource work
        '--target-glib=2.38',
        '--gresources=' + gresource,
        daemon_vala_args,
    ],
    c_args: [
        '-DGNOME_DESKTOP_USE_UNSTABLE_API'
    ],
    install: true,
    install_rpath: rpath_libdir,
)

# Brightness Helper executable
budgie_brightness_helper = executable(
    'budgie-brightness-helper',
    sources: [
        brightness_util_sources,
        'brightness-helper.vala',
    ],
    dependencies: [
        dep_giounix,
        dep_glib,
    ],
    vala_args: [
        '--pkg', 'posix',
    ],
    install: true,
    install_dir: bindir,
)

install_data('gammastep.config',
    install_dir: join_paths(datadir, 'budgie-desktop')
)

# gschemas
install_data(
    files('notifications/20_buddiesofbudgie.budgie-desktop.notifications.gschema.override'),
    install_dir: join_paths(datadir, 'glib-2.0', 'schemas')
)
