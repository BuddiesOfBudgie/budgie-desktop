# Places Indicator Build

applet_placesindicator_dir = applets_dir + '.places-indicator'

budgie_pot_templates += files('PlacesIndicator.plugin.desktop.in')

i18n.merge_file(
    input : 'PlacesIndicator.plugin.desktop.in',
    output : 'PlacesIndicator.plugin',
    type : 'desktop',
    po_dir : podir,
    args : ['--keyword=Description'],
    install : true,
    install_dir : applet_placesindicator_dir)

gresource = join_paths(meson.current_source_dir(), 'plugin.gresource.xml')

# Compile the assets into the binary
applet_placesindicator_resources = gnome.compile_resources(
    'places-applet-resources',
    gresource,
    source_dir: meson.current_source_dir(),
    c_name: 'budgie_placesindicator',
)

lib_applet_placesindicator_resources = static_library(
    'places-applet-resources',
    applet_placesindicator_resources,
    dependencies: [ dep_glib ],
    install: false,
    c_args: ['-Wno-overlength-strings'], # gresource generates overlength strings...
)

applet_placesindicator_sources = [
    'PlacesIndicator.vala',
    'PlacesIndicatorWindow.vala',
    'MessageRevealer.vala',
    'PlacesSection.vala',
    'ListItem.vala',
    'VolumeItem.vala',
    'MountItem.vala',
    'PlaceItem.vala',
    'MountHelper.vala',
]

applet_placesindicator_deps = [
    libpanelplugin_vapi,
    dep_gtk3,
    dep_peas,
    link_libpanelplugin,
]

budgie_pot_targets += shared_library(
    'placesindicator',
    applet_placesindicator_sources,
    dependencies: applet_placesindicator_deps,
    link_whole: [
        lib_applet_placesindicator_resources,
    ],
    vala_args: [
        # Make gresource work
        '--target-glib=2.38',
        '--gresources=' + gresource,
    ],
    install: true,
    install_dir: applet_placesindicator_dir,
)

install_data(
    'com.solus-project.places-indicator.gschema.xml',
    install_dir: join_paths(datadir, 'glib-2.0', 'schemas'),
)
