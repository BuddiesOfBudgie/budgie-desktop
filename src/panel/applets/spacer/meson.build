# Clock Applet build

applet_spacer_dir = applets_dir + '.spacer'

budgie_pot_templates += files('SpacerApplet.plugin.desktop.in')

i18n.merge_file(
    input : 'SpacerApplet.plugin.desktop.in',
    output : 'SpacerApplet.plugin',
    type : 'desktop',
    po_dir : podir,
    args : ['--keyword=Description'],
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

budgie_pot_targets += shared_library(
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
