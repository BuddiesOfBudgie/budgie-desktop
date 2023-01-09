applet_sntray_dir = applets_dir + '.sntray'

custom_target('plugin-file-sntray',
    input : 'SnTrayApplet.plugin.in',
    output : 'SnTrayApplet.plugin',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : applet_sntray_dir)

gresource = join_paths(meson.current_source_dir(), 'plugin.gresource.xml')

applet_sntray_resources = gnome.compile_resources(
    'sntray-applet-resources',
    gresource,
    source_dir: meson.current_source_dir(),
    c_name: 'budgie_sntray',
)

applet_sntray_sources = [
    'SnTrayApplet.vala',
    'SnTrayItem.vala',
    applet_sntray_resources,
]

applet_sntray_deps = [
    libplugin_vapi,
    dep_gtk3,
    dep_peas,
    dep_dbusmenugtk3,
    link_libplugin,
    meson.get_compiler('c').find_library('m', required: false)
]

shared_library(
    'sntrayapplet',
    applet_sntray_sources,
    dependencies: applet_sntray_deps,
    vala_args: [
        '--vapidir', join_paths(meson.source_root(), 'vapi'),
        '--pkg', 'Dbusmenu-0.4',
        '--pkg', 'libpeas-1.0',
    ],
    install: true,
    install_dir: applet_sntray_dir,
)

install_data(
    'org.buddiesofbudgie.sntray.gschema.xml',
    install_dir: join_paths(datadir, 'glib-2.0', 'schemas'),
)
