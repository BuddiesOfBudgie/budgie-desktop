# Clock Applet build

applet_spacer_dir = applets_dir + '.spacer'

custom_target('plugin-file-spacer',
    input : 'SpacerApplet.plugin.in',
    output : 'SpacerApplet.plugin',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : applet_spacer_dir)

gresource = join_paths(meson.current_source_dir(), 'plugin.gresource.xml')

# Compile the assets into the binary
applet_spacer_resources = gnome.compile_resources(
    'spacer-applet-resources',
    gresource,
    source_dir: meson.current_source_dir(),
    c_name: 'budgie_spacer',
)

applet_spacer_sources = [
    'SpacerApplet.vala',
    applet_spacer_resources,
]

applet_spacer_deps = [
    libpanelplugin_vapi,
    dep_gtk3,
    dep_peas,
    link_libpanelplugin,
]

shared_library(
    'spacerapplet',
    applet_spacer_sources,
    dependencies: applet_spacer_deps,
    vala_args: [
        # Make gresource work
        '--target-glib=2.38',
        '--gresources=' + gresource,
    ],
    install: true,
    install_dir: applet_spacer_dir,
)

install_data(
    'com.solus-project.spacer.gschema.xml',
    install_dir: join_paths(datadir, 'glib-2.0', 'schemas'),
)
