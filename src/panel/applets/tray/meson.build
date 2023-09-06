applet_tray_dir = applets_dir + '.tray'

custom_target('plugin-file-tray',
    input : 'TrayApplet.plugin.in',
    output : 'TrayApplet.plugin',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : applet_tray_dir)

gresource = join_paths(meson.current_source_dir(), 'plugin.gresource.xml')

applet_tray_resources = gnome.compile_resources(
    'tray-applet-resources',
    gresource,
    source_dir: meson.current_source_dir(),
    c_name: 'budgie_tray',
)

applet_tray_sources = [
    'DBusMenu.vala',
    'DBusMenuNode.vala',
    'TrayApplet.vala',
    'TrayItem.vala',
    applet_tray_resources,
]

applet_tray_deps = [
    libpanelplugin_vapi,
    dep_gtk3,
    dep_peas,
    link_libpanelplugin,
    meson.get_compiler('c').find_library('m', required: false)
]

shared_library(
    'trayapplet',
    applet_tray_sources,
    dependencies: applet_tray_deps,
    vala_args: [
        '--pkg', 'libpeas-1.0',
    ],
    install: true,
    install_dir: applet_tray_dir,
)

install_data(
    'com.solus-project.tray.gschema.xml',
    install_dir: join_paths(datadir, 'glib-2.0', 'schemas'),
)
