# Clock Applet build

applet_keyboardlayout_dir = applets_dir + '.keyboard-layout'

custom_target('plugin-file-keyboardlayout',
    input : 'KeyboardLayoutApplet.plugin.in',
    output : 'KeyboardLayoutApplet.plugin',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : applet_keyboardlayout_dir)

gresource = join_paths(meson.current_source_dir(), 'plugin.gresource.xml')

# Compile the assets into the binary
applet_keyboardlayout_resources = gnome.compile_resources(
    'keyboardlayout-applet-resources',
    gresource,
    source_dir: meson.current_source_dir(),
    c_name: 'budgie_keyboardlayout',
)

lib_applet_keyboardlayout_resources = static_library(
    'keyboardlayout-applet-resources',
    applet_keyboardlayout_resources,
    dependencies: [ dep_glib ],
    install: false,
    c_args: ['-Wno-overlength-strings'], # gresource generates overlength strings...
)

applet_keyboardlayout_sources = [
    'KeyboardLayoutApplet.vala',
]

applet_keyboardlayout_deps = [
    libpanelplugin_vapi,
    dep_gtk3,
    dep_peas,
    dep_gnomedesktop,
    dep_ibus,
    link_libpanelplugin,
]

shared_library(
    'keyboardlayoutapplet',
    applet_keyboardlayout_sources,
    dependencies: applet_keyboardlayout_deps,
    link_whole: [
        lib_applet_keyboardlayout_resources,
    ],
    vala_args: [
        '--pkg', 'libpeas-1.0',
        '--pkg', 'gtk+-3.0',
        '--pkg', 'ibus-1.0',
        '--pkg', 'gnome-desktop-3.0',
        '--vapidir', join_paths(meson.source_root(), 'vapi'),
        # Make gresource work
        '--target-glib=2.38',
        '--gresources=' + gresource,
    ],
    c_args: [
        '-DGNOME_DESKTOP_USE_UNSTABLE_API',
    ],
    install: true,
    install_dir: applet_keyboardlayout_dir,
)

install_data(
    'com.solus-project.keyboard-layout.gschema.xml',
    install_dir: join_paths(datadir, 'glib-2.0', 'schemas'),
)
