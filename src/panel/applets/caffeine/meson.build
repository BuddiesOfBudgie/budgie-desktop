# Caffeine Applet build

applet_caffeine_dir = applets_dir + '.caffeine'

custom_target('plugin-file-caffeine',
    input : 'CaffeineApplet.plugin.in',
    output : 'CaffeineApplet.plugin',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : applet_caffeine_dir)

gresource = join_paths(meson.current_source_dir(), 'plugin.gresource.xml')

# Compile the assets into the binary
applet_caffeine_resources = gnome.compile_resources(
    'caffeine-applet-resources',
    gresource,
    source_dir: meson.current_source_dir(),
    c_name: 'budgie_caffeine',
)

applet_caffeine_sources = [
    'CaffeineApplet.vala',
    'CaffeineWindow.vala',
    'CaffeineSettings.vala',
    applet_caffeine_resources,
]

applet_caffeine_deps = [
    libpanelplugin_vapi,
    dep_gtk3,
    dep_peas,
    link_libpanelplugin,
]

shared_library(
    'caffeineapplet',
    applet_caffeine_sources,
    dependencies: applet_caffeine_deps,
    vala_args: [
        # Make gresource work
        '--target-glib=2.38',
        '--gresources=' + gresource,
    ],
    install: true,
    install_dir: applet_caffeine_dir,
)
