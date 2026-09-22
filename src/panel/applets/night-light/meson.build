# Night Light Applet build

applet_nightlight_dir = applets_dir + '.night-light'

budgie_pot_templates += files('NightLight.plugin.desktop.in')

i18n.merge_file(
    input : 'NightLight.plugin.desktop.in',
    output : 'NightLight.plugin',
    type : 'desktop',
    po_dir : podir,
    args : ['--keyword=Description'],
    install : true,
    install_dir : applet_nightlight_dir)

gresource = join_paths(meson.current_source_dir(), 'org.budgie-desktop.night-light.gresource.xml')

# Compile the assets into the binary
applet_nightlight_resources = gnome.compile_resources(
    'nightlight-applet-resources',
    gresource,
    source_dir: meson.current_source_dir(),
    c_name: 'budgie_nightlight',
)

lib_applet_nightlight_resources = static_library(
    'nightlight-applet-resources',
    applet_nightlight_resources,
    dependencies: [ dep_glib ],
    install: false,
    c_args: ['-Wno-overlength-strings'], # gresource generates overlength strings...
)

applet_nightlight_sources = [
    'NightLight.vala',
    'IndicatorWindow.vala',
]

applet_nightlight_deps = [
    libpanelplugin_vapi,
    dep_giounix,
    dep_gtk3,
    dep_peas,
    link_libpanelplugin,
]

budgie_pot_targets += shared_library(
    'nightlightapplet',
    applet_nightlight_sources,
    dependencies: applet_nightlight_deps,
    link_whole: [
        lib_applet_nightlight_resources,
    ],
    vala_args: [
        # Make gresource work
        '--target-glib=2.38',
        '--gresources=' + gresource
    ],
    install: true,
    install_dir: applet_nightlight_dir,
)
