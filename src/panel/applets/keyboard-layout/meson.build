# Clock Applet build

applet_keyboardlayout_dir = applets_dir + '.keyboard-layout'

custom_target('plugin-file-keyboardlayout',
    input : 'KeyboardLayoutApplet.plugin.in',
    output : 'KeyboardLayoutApplet.plugin',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : applet_keyboardlayout_dir)

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
    vala_args: [
        '--vapidir', join_paths(meson.project_source_root(), 'vapi'),
    ],
    c_args: [
        '-DGNOME_DESKTOP_USE_UNSTABLE_API',
    ],
    install: true,
    install_dir: applet_keyboardlayout_dir,
)
