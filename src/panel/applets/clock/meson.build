# Clock Applet build

gnome = import('gnome')

applet_clock_dir = applets_dir + '.clock'

budgie_pot_templates += files('ClockApplet.plugin.desktop.in')

i18n.merge_file(
    input : 'ClockApplet.plugin.desktop.in',
    output : 'ClockApplet.plugin',
    type : 'desktop',
    po_dir : podir,
    args : ['--keyword=Description'],
    install : true,
    install_dir : applet_clock_dir)

gresource = join_paths(meson.current_source_dir(), 'plugin.gresource.xml')

# Compile the assets into the binary
applet_clock_resources = gnome.compile_resources(
    'clock-applet-resources',
    gresource,
    source_dir: meson.current_source_dir(),
    c_name: 'budgie_Clock',
)

lib_applet_clock_resources = static_library(
    'clock-applet-resources',
    applet_clock_resources,
    dependencies: [ dep_glib ],
    install: false,
    c_args: ['-Wno-overlength-strings'], # gresource generates overlength strings...
)

applet_clock_sources = [
    'ClockApplet.vala',
]


budgie_pot_targets += shared_library(
    'clockapplet',
    applet_clock_sources,
    dependencies: [
        libpanelplugin_vapi,
        dep_giounix,
        dep_gtk3,
        dep_peas,
        link_libpanelplugin,
    ],
    link_whole: [
        lib_applet_clock_resources,
    ],
    vala_args: [
        # Make gresource work
        '--target-glib=2.38',
        '--gresources=' + gresource,
    ],
    install: true,
    install_dir: applet_clock_dir,
)

install_data(
    'com.solus-project.clock.gschema.xml',
    install_dir: join_paths(datadir, 'glib-2.0', 'schemas'),
)
